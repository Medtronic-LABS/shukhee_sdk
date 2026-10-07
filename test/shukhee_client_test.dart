import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

/// A scripted [HttpClientAdapter]: returns one response per call, in order
/// (the last entry repeats if more calls happen than entries provided).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._responses);

  final List<Future<ResponseBody> Function(RequestOptions)> _responses;
  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final index = callCount < _responses.length ? callCount : _responses.length - 1;
    callCount++;
    return _responses[index](options);
  }
}

ResponseBody _jsonResponse(int statusCode, Map<String, dynamic> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(
    bytes,
    statusCode,
    headers: {
      'content-type': ['application/json; charset=utf-8'],
    },
  );
}

Future<ResponseBody> Function(RequestOptions) _ok(Map<String, dynamic> message) {
  return (_) async => _jsonResponse(200, {'message': message});
}

Future<ResponseBody> Function(RequestOptions) _error(int status, {String? serverMessage}) {
  return (_) async => _jsonResponse(status, {
        if (serverMessage != null)
          '_server_messages': jsonEncode([
            jsonEncode({'message': serverMessage}),
          ]),
      });
}

ShukheeClient _clientWith(
  List<Future<ResponseBody> Function(RequestOptions)> responses, {
  Future<String?> Function()? authTokenProvider,
  Future<String?> Function()? languageCodeProvider,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _ScriptedAdapter(responses);
  final config = ShukheeConfig(
    baseUrl: 'https://example.test',
    authTokenProvider: authTokenProvider ?? () async => 'test-token',
    languageCodeProvider: languageCodeProvider,
  );
  return ShukheeClient(config, dio: dio);
}

void main() {
  group('getSpecialities', () {
    test('parses specialityId and title for each entry', () async {
      final client = _clientWith([
        _ok({
          'specialities': [
            {'specialityId': '1', 'title': 'General Physician'},
            {'specialityId': '2', 'title': 'Sexual Wellness'},
          ],
        }),
      ]);

      final specialities = await client.getSpecialities();

      expect(specialities, hasLength(2));
      expect(specialities[0].specialityId, '1');
      expect(specialities[0].title, 'General Physician');
      expect(specialities[1].specialityId, '2');
      expect(specialities[1].title, 'Sexual Wellness');
    });

    test('drops entries with no title and returns empty list when specialities key is missing', () async {
      final client = _clientWith([
        _ok({
          'specialities': [
            {'specialityId': '1', 'title': 'General Physician'},
            {'specialityId': '2'},
          ],
        }),
      ]);

      final specialities = await client.getSpecialities();

      expect(specialities, hasLength(1));
      expect(specialities.single.title, 'General Physician');
    });

    test('maps a not-provisioned error to ShukheeNotProvisionedException', () async {
      final client = _clientWith([
        _error(404, serverMessage: 'No Provider record found for the calling user.'),
      ]);

      await expectLater(
        client.getSpecialities(),
        throwsA(isA<ShukheeNotProvisionedException>()),
      );
    });
  });

  group('startConsultation', () {
    test('parses a successful booking', () async {
      final client = _clientWith([
        _ok({'call_log': 'CL-1', 'call_url': 'https://call.example/join', 'status': 'confirmed'}),
      ]);

      final booking = await client.startConsultation(
        contactNumber: '+8801000000000',
        reason: 'Fever',
      );

      expect(booking.callLog, 'CL-1');
      expect(booking.callUrl, 'https://call.example/join');
      expect(booking.status, 'confirmed');
      expect(booking.isTerminal, isFalse);
    });

    test('coerces a numeric call_log (autoincrement-named doctype) to a string', () async {
      final client = _clientWith([
        _ok({'call_log': 22285, 'call_url': 'https://call.example/join', 'status': 'confirmed'}),
      ]);

      final booking = await client.startConsultation(
        contactNumber: '+8801000000000',
        reason: 'Fever',
      );

      expect(booking.callLog, '22285');
    });

    test('sends each media group under its own medias_<type> multipart field', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _ScriptedAdapter([
          (options) async {
            captured = options;
            return _jsonResponse(200, {
              'message': {
                'call_log': 'CL-1',
                'call_url': 'https://call.example/join',
                'status': 'confirmed',
              },
            });
          },
        ]);
      final client = ShukheeClient(
        ShukheeConfig(baseUrl: 'https://example.test', authTokenProvider: () async => 'test-token'),
        dio: dio,
      );

      await client.startConsultation(
        contactNumber: '+8801000000000',
        reason: 'Fever',
        mediaGroups: {
          'prescription': [
            ShukheeMediaFile(filename: 'rx.jpg', bytes: [1, 2, 3], mimeType: 'image/jpeg'),
          ],
          'lab_report': [
            ShukheeMediaFile(filename: 'report.jpg', bytes: [4, 5, 6], mimeType: 'image/jpeg'),
          ],
        },
      );

      final formData = captured!.data as FormData;
      expect(formData.fields.where((f) => f.key == 'document_type'), isEmpty);

      final prescriptionFiles = formData.files.where((f) => f.key == 'medias_prescription').toList();
      expect(prescriptionFiles, hasLength(1));
      expect(prescriptionFiles.single.value.filename, 'rx.jpg');

      final labReportFiles = formData.files.where((f) => f.key == 'medias_lab_report').toList();
      expect(labReportFiles, hasLength(1));
      expect(labReportFiles.single.value.filename, 'report.jpg');
    });

    test('sends clinicalData as a JSON-encoded form field when provided', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _ScriptedAdapter([
          (options) async {
            captured = options;
            return _jsonResponse(200, {
              'message': {
                'call_log': 'CL-1',
                'call_url': 'https://call.example/join',
                'status': 'confirmed',
              },
            });
          },
        ]);
      final client = ShukheeClient(
        ShukheeConfig(baseUrl: 'https://example.test', authTokenProvider: () async => 'test-token'),
        dio: dio,
      );

      await client.startConsultation(
        contactNumber: '+8801000000000',
        reason: 'Fever',
        clinicalData: {
          'vitals': [
            {'temperature': '99'},
          ],
        },
      );

      final formData = captured!.data as FormData;
      final field = formData.fields.singleWhere((f) => f.key == 'clinical_data');
      expect(
        jsonDecode(field.value),
        {
          'vitals': [
            {'temperature': '99'},
          ],
        },
      );
    });

    test('no clinical_data field sent when clinicalData is omitted', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _ScriptedAdapter([
          (options) async {
            captured = options;
            return _jsonResponse(200, {
              'message': {
                'call_log': 'CL-1',
                'call_url': 'https://call.example/join',
                'status': 'confirmed',
              },
            });
          },
        ]);
      final client = ShukheeClient(
        ShukheeConfig(baseUrl: 'https://example.test', authTokenProvider: () async => 'test-token'),
        dio: dio,
      );

      await client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever');

      final formData = captured!.data as FormData;
      expect(formData.fields.where((f) => f.key == 'clinical_data'), isEmpty);
    });

    test('sends versionId/lng/itemsChecked as form fields when provided', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _ScriptedAdapter([
          (options) async {
            captured = options;
            return _jsonResponse(200, {
              'message': {
                'call_log': 'CL-1',
                'call_url': 'https://call.example/join',
                'status': 'confirmed',
              },
            });
          },
        ]);
      final client = ShukheeClient(
        ShukheeConfig(baseUrl: 'https://example.test', authTokenProvider: () async => 'test-token'),
        dio: dio,
      );

      await client.startConsultation(
        contactNumber: '+8801000000000',
        reason: 'Fever',
        versionId: 'VER-1',
        lng: 'en',
        itemsChecked: [true, false],
      );

      final formData = captured!.data as FormData;
      expect(formData.fields.singleWhere((f) => f.key == 'version_id').value, 'VER-1');
      expect(formData.fields.singleWhere((f) => f.key == 'lng').value, 'en');
      expect(
        jsonDecode(formData.fields.singleWhere((f) => f.key == 'items_checked').value),
        [true, false],
      );
    });

    test('no consent fields sent when versionId/lng/itemsChecked are omitted', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _ScriptedAdapter([
          (options) async {
            captured = options;
            return _jsonResponse(200, {
              'message': {
                'call_log': 'CL-1',
                'call_url': 'https://call.example/join',
                'status': 'confirmed',
              },
            });
          },
        ]);
      final client = ShukheeClient(
        ShukheeConfig(baseUrl: 'https://example.test', authTokenProvider: () async => 'test-token'),
        dio: dio,
      );

      await client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever');

      final formData = captured!.data as FormData;
      expect(formData.fields.where((f) => f.key == 'version_id'), isEmpty);
      expect(formData.fields.where((f) => f.key == 'lng'), isEmpty);
      expect(formData.fields.where((f) => f.key == 'items_checked'), isEmpty);
    });

    test('no media fields sent when mediaGroups is omitted', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _ScriptedAdapter([
          (options) async {
            captured = options;
            return _jsonResponse(200, {
              'message': {
                'call_log': 'CL-1',
                'call_url': 'https://call.example/join',
                'status': 'confirmed',
              },
            });
          },
        ]);
      final client = ShukheeClient(
        ShukheeConfig(baseUrl: 'https://example.test', authTokenProvider: () async => 'test-token'),
        dio: dio,
      );

      await client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever');

      final formData = captured!.data as FormData;
      expect(formData.files, isEmpty);
    });

    test('throws ShukheeBookingException when call_url is missing', () async {
      final client = _clientWith([
        _ok({'call_log': 'CL-1', 'status': 'confirmed'}),
      ]);

      await expectLater(
        client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever'),
        throwsA(isA<ShukheeBookingException>()),
      );
    });

    test('maps a missing-provider error to ShukheeNotProvisionedException', () async {
      final client = _clientWith([
        _error(404, serverMessage: 'No Provider record found for the calling user.'),
      ]);

      await expectLater(
        client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever'),
        throwsA(isA<ShukheeNotProvisionedException>()),
      );
    });

    test('maps a missing-Shukhee-credentials error to ShukheeNotProvisionedException', () async {
      final client = _clientWith([
        _error(404, serverMessage: 'No Shukhee credentials configured for this Provider.'),
      ]);

      await expectLater(
        client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever'),
        throwsA(isA<ShukheeNotProvisionedException>()),
      );
    });

    test('maps a generic validation error to ShukheeBookingException', () async {
      final client = _clientWith([
        _error(417, serverMessage: 'contact_number, reason, and requested_speciality are required.'),
      ]);

      await expectLater(
        client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever'),
        throwsA(isA<ShukheeBookingException>()),
      );
    });

    test('throws ShukheeUnauthorizedException without a network call when no token is available', () async {
      final adapter = _ScriptedAdapter([
        (_) async => throw StateError('should not be called'),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
      final config = ShukheeConfig(
        baseUrl: 'https://example.test',
        authTokenProvider: () async => null,
      );
      final client = ShukheeClient(config, dio: dio);

      await expectLater(
        client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever'),
        throwsA(isA<ShukheeUnauthorizedException>()),
      );
      expect(adapter.callCount, 0);
    });
  });

  group('pollStatus', () {
    test('returns immediately on a terminal first attempt', () async {
      final client = _clientWith([
        _ok({'status': 'completed', 'prescription_link': 'https://rx', 'invoice_link': 'https://inv'}),
      ]);

      final status = await client.pollStatus(callLog: 'CL-1', delayBetween: Duration.zero);

      expect(status.status, 'completed');
      expect(status.isTerminal, isTrue);
      expect(status.isCompleted, isTrue);
      expect(status.prescriptionLink, 'https://rx');
      expect(status.invoiceLink, 'https://inv');
    });

    test('parses doctor fields once Shukhee assigns a doctor, even on a non-terminal poll', () async {
      final client = _clientWith([
        _ok({
          'status': 'accepted',
          'doctor_name': 'Dr. Farzana Haque',
          'doctor_speciality': 'Ob-Gyn',
          'doctor_facility': 'DMC',
        }),
      ]);

      final status = await client.pollStatus(callLog: 'CL-1', maxAttempts: 1, delayBetween: Duration.zero);

      expect(status.doctorName, 'Dr. Farzana Haque');
      expect(status.doctorSpeciality, 'Ob-Gyn');
      expect(status.doctorFacility, 'DMC');
    });

    test('keeps polling through non-terminal statuses until terminal', () async {
      final client = _clientWith([
        _ok({'status': 'confirmed'}),
        _ok({'status': 'accepted'}),
        _ok({'status': 'completed', 'prescription_link': 'https://rx'}),
      ]);

      final status = await client.pollStatus(
        callLog: 'CL-1',
        maxAttempts: 5,
        delayBetween: Duration.zero,
      );

      expect(status.status, 'completed');
      expect(status.prescriptionLink, 'https://rx');
    });

    test('onUpdate fires on every attempt, terminal or not', () async {
      final client = _clientWith([
        _ok({'status': 'confirmed'}),
        _ok({'status': 'accepted', 'doctor_name': 'Dr. Farzana Haque'}),
        _ok({'status': 'completed'}),
      ]);
      final seen = <String>[];

      await client.pollStatus(
        callLog: 'CL-1',
        maxAttempts: 5,
        delayBetween: Duration.zero,
        onUpdate: (status) => seen.add(status.status),
      );

      expect(seen, ['confirmed', 'accepted', 'completed']);
    });

    test('a transient failure mid-poll does not abort the loop', () async {
      final client = _clientWith([
        _ok({'status': 'confirmed'}),
        _error(500),
        _ok({'status': 'completed'}),
      ]);

      final status = await client.pollStatus(
        callLog: 'CL-1',
        maxAttempts: 5,
        delayBetween: Duration.zero,
      );

      expect(status.status, 'completed');
    });

    test('returns the last-seen non-terminal status after exhausting attempts, without throwing', () async {
      final client = _clientWith([
        _ok({'status': 'confirmed'}),
        _ok({'status': 'accepted'}),
        _ok({'status': 'accepted'}),
      ]);

      final status = await client.pollStatus(
        callLog: 'CL-1',
        maxAttempts: 3,
        delayBetween: Duration.zero,
      );

      expect(status.status, 'accepted');
      expect(status.isTerminal, isFalse);
    });

    test('parses appointmentStatus and derives isConsultationStarted/isConsultationEnded '
        'across all four vendor values', () async {
      final cases = {
        'Scheduled': (started: false, ended: false),
        'ConsultationStarted': (started: true, ended: false),
        'ConsultationEnd': (started: true, ended: true),
        'Completed': (started: true, ended: true),
      };
      for (final entry in cases.entries) {
        final client = _clientWith([
          _ok({'status': 'accepted', 'appointment_status': entry.key}),
        ]);
        final status = await client.pollStatus(callLog: 'CL-1', maxAttempts: 1, delayBetween: Duration.zero);

        expect(status.appointmentStatus, entry.key, reason: entry.key);
        expect(status.isConsultationStarted, entry.value.started, reason: entry.key);
        expect(status.isConsultationEnded, entry.value.ended, reason: entry.key);
      }
    });

    test('appointmentStatus/clinicalData null before either is present', () async {
      final client = _clientWith([
        _ok({'status': 'accepted'}),
      ]);
      final status = await client.pollStatus(callLog: 'CL-1', maxAttempts: 1, delayBetween: Duration.zero);

      expect(status.appointmentStatus, isNull);
      expect(status.clinicalData, isNull);
      expect(status.isConsultationStarted, isFalse);
      expect(status.isConsultationEnded, isFalse);
    });

    test('parses a full clinicalData block on a completed poll', () async {
      final client = _clientWith([
        _ok({
          'status': 'completed',
          'appointment_status': 'Completed',
          'clinical_data': {
            'chiefComplaints': ['fever'],
            'diagnosis': ['Common cold'],
            'medicine': [
              {'brandName': 'Napa', 'dosage': '500 mg', 'frequency': '1+1+1'},
            ],
            'mealInstruction': [
              {'mealType': 'Breakfast', 'instruction': '1 boiled egg'},
            ],
            'lastVital': {'temperature': '99', 'bloodPressure': '110/70'},
            'followUpComment': 'review after one week',
            // A raw JSON number, matching the real sandbox -- NOT a string.
            // This exact shape once threw an uncaught TypeError deep inside
            // pollStatus (not a DioException, so its own catch clause never
            // saw it), silently killing the whole poll loop after a
            // consultation completed. Keep this as a number here, not '7'.
            'followUpDay': 7,
          },
        }),
      ]);

      final status = await client.pollStatus(callLog: 'CL-1', delayBetween: Duration.zero);
      final data = status.clinicalData!;

      expect(data.chiefComplaints, ['fever']);
      expect(data.diagnosis, ['Common cold']);
      expect(data.medicine, hasLength(1));
      expect(data.medicine.single.brandName, 'Napa');
      expect(data.mealInstruction.single.mealType, 'Breakfast');
      expect(data.lastVital?.temperature, '99');
      expect(data.lastVital?.bloodPressure, '110/70');
      expect(data.followUpDay, '7');
      expect(data.followUpComment, 'review after one week');
      expect(data.followUpDay, '7');
    });
  });

  group('downloadDocument', () {
    test('decodes filename and base64 bytes', () async {
      final content = utf8.encode('%PDF-1.4 fake pdf bytes');
      final client = _clientWith([
        _ok({
          'filename': 'CL-1-prescription.pdf',
          'content_base64': base64Encode(content),
        }),
      ]);

      final document = await client.downloadDocument(callLog: 'CL-1', docType: 'prescription');

      expect(document.filename, 'CL-1-prescription.pdf');
      expect(document.bytes, content);
    });

    test('throws ShukheeBookingException when content_base64 is missing', () async {
      final client = _clientWith([
        _ok({'filename': 'CL-1-invoice.pdf'}),
      ]);

      await expectLater(
        client.downloadDocument(callLog: 'CL-1', docType: 'invoice'),
        throwsA(isA<ShukheeBookingException>()),
      );
    });

    test('maps a permission error to ShukheeBookingException', () async {
      final client = _clientWith([
        _error(403, serverMessage: "Not permitted to access this consultation's documents."),
      ]);

      await expectLater(
        client.downloadDocument(callLog: 'CL-1', docType: 'prescription'),
        throwsA(isA<ShukheeBookingException>()),
      );
    });
  });

  group('getPrescription', () {
    test('parses prescription and invoice links', () async {
      final client = _clientWith([
        _ok({'prescription_link': 'https://rx', 'invoice_link': 'https://inv'}),
      ]);

      final prescription = await client.getPrescription(callLog: 'CL-1');

      expect(prescription.prescriptionLink, 'https://rx');
      expect(prescription.invoiceLink, 'https://inv');
    });

    test('parses doctor fields', () async {
      final client = _clientWith([
        _ok({
          'prescription_link': 'https://rx',
          'doctor_name': 'Dr. Farzana Haque',
          'doctor_speciality': 'Ob-Gyn',
          'doctor_facility': 'DMC',
        }),
      ]);

      final prescription = await client.getPrescription(callLog: 'CL-1');

      expect(prescription.doctorName, 'Dr. Farzana Haque');
      expect(prescription.doctorSpeciality, 'Ob-Gyn');
      expect(prescription.doctorFacility, 'DMC');
    });

    test('maps a not-completed error to ShukheeBookingException', () async {
      final client = _clientWith([
        _error(422, serverMessage: 'This consultation has not completed yet.'),
      ]);

      await expectLater(
        client.getPrescription(callLog: 'CL-1'),
        throwsA(isA<ShukheeBookingException>()),
      );
    });
  });

  group('languageCodeProvider', () {
    test('sends _lang as a query param when provided', () async {
      String? capturedLang;
      final client = _clientWith(
        [
          (options) async {
            capturedLang = options.queryParameters['_lang'] as String?;
            return _jsonResponse(200, {'specialities': []});
          },
        ],
        languageCodeProvider: () async => 'bn',
      );

      await client.getSpecialities();

      expect(capturedLang, 'bn');
    });

    test('omits _lang entirely when no languageCodeProvider is given', () async {
      Map<String, dynamic>? capturedQuery;
      final client = _clientWith([
        (options) async {
          capturedQuery = options.queryParameters;
          return _jsonResponse(200, {'specialities': []});
        },
      ]);

      await client.getSpecialities();

      expect(capturedQuery, isNot(contains('_lang')));
    });

    test('sent on startConsultation too, not just getSpecialities', () async {
      String? capturedLang;
      final client = _clientWith(
        [
          (options) async {
            capturedLang = options.queryParameters['_lang'] as String?;
            return _ok({
              'call_log': 'CL-1',
              'call_url': 'https://call.example/1',
              'status': 'pending',
            })(options);
          },
        ],
        languageCodeProvider: () async => 'en',
      );

      await client.startConsultation(contactNumber: '+8801000000000', reason: 'Fever');

      expect(capturedLang, 'en');
    });
  });
}

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
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _ScriptedAdapter(responses);
  final config = ShukheeConfig(
    baseUrl: 'https://example.test',
    authTokenProvider: authTokenProvider ?? () async => 'test-token',
  );
  return ShukheeClient(config, dio: dio);
}

void main() {
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
}

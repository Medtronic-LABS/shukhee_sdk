import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import 'shukhee_config.dart';
import 'shukhee_exceptions.dart';
import 'shukhee_models.dart';

/// HTTP client for the Shukhee teleconsultation backend. Deliberately scoped
/// to exactly the endpoints the backend exposes today (`get_specialities`,
/// `start_consultation`, `get_consultation_status`, `get_prescription`,
/// `download_document`) — this is not a general-purpose API client. Adding
/// another Shukhee endpoint later is a method addition here, not a
/// rearchitecture.
///
/// Builds its own internal [Dio] instance from [ShukheeConfig.baseUrl] —
/// never shares a host app's own HTTP client, so this package has zero
/// dependency on how any particular app is built.
class ShukheeClient {
  /// [dio] is exposed only so tests can inject a fake transport — real
  /// callers should never pass it; the client builds its own from [config].
  ShukheeClient(this._config, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: _config.baseUrl,
                connectTimeout: _config.connectTimeout,
                receiveTimeout: _config.receiveTimeout,
              ),
            );

  final ShukheeConfig _config;
  final Dio _dio;

  /// Live, selectable specialities for a booking form's speciality picker.
  /// Each [ShukheeSpeciality.title] is safe to send back verbatim as
  /// [startConsultation]'s `requestedSpeciality` -- it's the exact string
  /// Shukhee's own speciality-matching logic expects, sourced from Shukhee
  /// itself rather than a hardcoded guess that could drift out of sync.
  Future<List<ShukheeSpeciality>> getSpecialities() async {
    final headers = await _authHeaders();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _config.getSpecialitiesPath,
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      final list = data['specialities'] as List<dynamic>? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(
            (s) => ShukheeSpeciality(
              specialityId: s['specialityId']?.toString() ?? '',
              title: s['title'] as String? ?? '',
            ),
          )
          .where((s) => s.title.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Books an instant Shukhee video consultation and returns the join URL.
  ///
  /// [contactNumber], [reason], and [requestedSpeciality] are required by the
  /// backend. [requestedSpeciality] must match a title from Shukhee's own
  /// speciality list (case-insensitive) — an unmatched value silently falls
  /// back to whichever speciality Shukhee's list returns first, so pass a
  /// confirmed-valid value rather than guessing.
  ///
  /// [patientName]/[patientDob]/[patientGender] are only required by the
  /// backend when [contactNumber] isn't already a known patient (on this
  /// platform or on Shukhee's side already) — omitting them in that case
  /// throws a [ShukheeBookingException]. Supplying them whenever available
  /// avoids that failure mode entirely.
  ///
  /// [mediaGroups] attaches documents to the request (e.g. photographed
  /// prescriptions and/or lab reports in the *same* booking), keyed by
  /// document type -- each key must be one of `'prescription' | 'lab_report'
  /// | 'other'`, matching the literal `type` values Shukhee's own upload API
  /// accepts. Each group is sent as its own repeated multipart field
  /// (`medias_<type>`) since Shukhee's `/ssk/medical-document/upload` only
  /// accepts one `type` per call -- the backend makes one upload call per
  /// non-empty group here, tagging every file in it with that group's type.
  Future<ShukheeBooking> startConsultation({
    required String contactNumber,
    required String reason,
    String requestedSpeciality = 'General Physician',
    String? encounterId,
    String? patientName,
    String? patientDob,
    String? patientGender,
    Map<String, List<ShukheeMediaFile>> mediaGroups = const {},
  }) async {
    assert(
      mediaGroups.keys.every(
        (t) => t == 'prescription' || t == 'lab_report' || t == 'other',
      ),
    );
    final headers = await _authHeaders();
    final formData = FormData.fromMap({
      'contact_number': contactNumber,
      'reason': reason,
      'requested_speciality': requestedSpeciality,
      'encounter_id': ?encounterId,
      'patient_name': ?patientName,
      'patient_dob': ?patientDob,
      'patient_gender': ?patientGender,
    });
    for (final entry in mediaGroups.entries) {
      for (final media in entry.value) {
        formData.files.add(
          MapEntry(
            'medias_${entry.key}',
            MultipartFile.fromBytes(
              media.bytes,
              filename: media.filename,
              contentType:
                  media.mimeType != null ? MediaType.parse(media.mimeType!) : null,
            ),
          ),
        );
      }
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _config.startConsultationPath,
        data: formData,
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      // call_log is a Call Logs doctype name -- that doctype uses
      // autoname: "autoincrement", so its `name` is a real database integer
      // and comes back as a JSON number, not a string. toString() coerces
      // either shape (and any other doctype's string-series name) uniformly.
      final callLog = data['call_log']?.toString();
      final callUrl = data['call_url'] as String?;
      final status = data['status'] as String?;
      if (callLog == null || callUrl == null || status == null) {
        throw const ShukheeBookingException(
          'Malformed start_consultation response: missing call_log/call_url/status.',
        );
      }
      return ShukheeBooking(callLog: callLog, callUrl: callUrl, status: status);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Polls `get_consultation_status` for [callLog] until it reaches a
  /// terminal status (see [shukheeTerminalStatuses]) or [maxAttempts] is
  /// exhausted.
  ///
  /// Mirrors the bounded-poll shape already proven in this ecosystem (the
  /// desk-side admin UI polls the same endpoint every 4s): delay, request,
  /// check terminal set, and — critically — a transient failure mid-poll
  /// does not abort the loop, it just tries again next attempt. Returns the
  /// last-seen status (terminal or not) after exhausting attempts rather
  /// than throwing, so the caller can decide how to present "still not
  /// resolved" without treating it as a hard error.
  ///
  /// [onUpdate], when given, is called after every successful attempt
  /// (terminal or not) with the latest snapshot — lets a caller react to a
  /// mid-call change (e.g. a doctor being assigned) without waiting for the
  /// whole poll loop to finish.
  Future<ShukheeStatus> pollStatus({
    required String callLog,
    int maxAttempts = 30,
    Duration delayBetween = const Duration(seconds: 4),
    void Function(ShukheeStatus status)? onUpdate,
  }) async {
    final headers = await _authHeaders();
    var last = const ShukheeStatus(status: 'pending');

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) await Future<void>.delayed(delayBetween);

      try {
        final response = await _dio.post<Map<String, dynamic>>(
          _config.getStatusPath,
          data: FormData.fromMap({'call_log': callLog}),
          options: Options(headers: headers),
        );
        final data = _unwrapMessage(response.data);
        last = ShukheeStatus(
          status: data['status'] as String? ?? last.status,
          prescriptionLink: data['prescription_link'] as String?,
          invoiceLink: data['invoice_link'] as String?,
          doctorName: data['doctor_name'] as String?,
          doctorSpeciality: data['doctor_speciality'] as String?,
          doctorFacility: data['doctor_facility'] as String?,
        );
        onUpdate?.call(last);
        if (last.isTerminal) return last;
      } on DioException {
        // Transient failure — keep polling rather than aborting the whole
        // wait just because one attempt hiccuped.
      }
    }

    return last;
  }

  /// Returns the prescription/invoice links for a completed consultation.
  /// Rarely needed directly — [pollStatus]'s terminal `completed` response
  /// already carries both fields inline; this exists mainly for re-opening
  /// a call log later without re-polling.
  Future<ShukheePrescription> getPrescription({required String callLog}) async {
    final headers = await _authHeaders();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _config.getPrescriptionPath,
        data: FormData.fromMap({'call_log': callLog}),
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      return ShukheePrescription(
        prescriptionLink: data['prescription_link'] as String?,
        invoiceLink: data['invoice_link'] as String?,
        doctorName: data['doctor_name'] as String?,
        doctorSpeciality: data['doctor_speciality'] as String?,
        doctorFacility: data['doctor_facility'] as String?,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Fetches a completed consultation's prescription/invoice as raw bytes.
  ///
  /// The backend stores these as private files with no unauthenticated web
  /// access, so [ShukheeStatus.prescriptionLink]/[invoiceLink] are not
  /// directly openable URLs — they only indicate a document exists. Use
  /// this method (authenticated the same way as every other call here) to
  /// get the actual bytes, then write them to local storage and open with
  /// a platform file viewer.
  Future<ShukheeDocument> downloadDocument({
    required String callLog,
    required String docType,
  }) async {
    assert(docType == 'prescription' || docType == 'invoice');
    final headers = await _authHeaders();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _config.downloadDocumentPath,
        data: FormData.fromMap({'call_log': callLog, 'doc_type': docType}),
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      final filename = data['filename'] as String?;
      final contentBase64 = data['content_base64'] as String?;
      if (filename == null || contentBase64 == null) {
        throw const ShukheeBookingException(
          'Malformed download_document response: missing filename/content_base64.',
        );
      }
      return ShukheeDocument(filename: filename, bytes: base64Decode(contentBase64));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _config.authTokenProvider();
    if (token == null || token.isEmpty) {
      throw const ShukheeUnauthorizedException(
        'No auth token available to call the Shukhee backend.',
      );
    }
    final headers = {'X-Auth-Token': 'Bearer $token'};
    final tenantId = await _config.tenantIdProvider?.call();
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['tenantId'] = tenantId;
    }
    return headers;
  }

  /// Frappe whitelisted methods wrap a returned dict as `{"message": {...}}`.
  /// Unwraps that; falls back to the raw body if it's already unwrapped
  /// (defensive — matches the desk-side client's own `body.message || body`
  /// pattern).
  Map<String, dynamic> _unwrapMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is Map<String, dynamic>) return message;
      return body;
    }
    throw const ShukheeBookingException(
      'Unexpected response shape from the Shukhee backend.',
    );
  }

  ShukheeException _mapError(DioException e) {
    final response = e.response;
    if (response == null) {
      return ShukheeBookingException(
        e.message ?? 'Network error contacting the Shukhee backend.',
      );
    }

    final serverMessage = _extractServerMessage(response.data) ??
        e.message ??
        'Shukhee request failed (${response.statusCode}).';

    if (response.statusCode == 401 ||
        serverMessage.toLowerCase().contains('bearer token')) {
      return ShukheeUnauthorizedException(serverMessage);
    }

    final lower = serverMessage.toLowerCase();
    if (lower.contains('provider') ||
        lower.contains('shukhee credentials') ||
        lower.contains('shukhee account')) {
      return ShukheeNotProvisionedException(serverMessage);
    }

    return ShukheeBookingException(serverMessage);
  }

  /// Extracts a human-readable message from a Frappe error response —
  /// mirrors the desk-side client's own `_extract_error` (parses
  /// `_server_messages`, a JSON-encoded list of JSON-encoded
  /// `{message, title, indicator}` objects; falls back to `exception`).
  String? _extractServerMessage(dynamic body) {
    if (body is! Map) return null;

    final raw = body['_server_messages'];
    if (raw is String) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        if (list.isNotEmpty) {
          final first = jsonDecode(list.first as String) as Map<String, dynamic>;
          final message = first['message'];
          if (message is String && message.isNotEmpty) return message;
        }
      } catch (_) {
        // Fall through to the exception field below.
      }
    }

    final exception = body['exception'];
    if (exception is String && exception.isNotEmpty) return exception;
    return null;
  }
}

import 'dart:convert';

import 'package:dio/dio.dart';

import 'shukhee_config.dart';
import 'shukhee_exceptions.dart';
import 'shukhee_models.dart';

/// HTTP client for the Shukhee teleconsultation backend. Deliberately scoped
/// to exactly the 3 endpoints the backend exposes today
/// (`start_consultation`, `get_consultation_status`, `get_prescription`) —
/// this is not a general-purpose API client. Adding a 4th Shukhee endpoint
/// later is a method addition here, not a rearchitecture.
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
  Future<ShukheeBooking> startConsultation({
    required String contactNumber,
    required String reason,
    String requestedSpeciality = 'General Physician',
    String? encounterId,
    String? patientName,
    String? patientDob,
    String? patientGender,
  }) async {
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

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _config.startConsultationPath,
        data: formData,
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      final callLog = data['call_log'] as String?;
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
  Future<ShukheeStatus> pollStatus({
    required String callLog,
    int maxAttempts = 30,
    Duration delayBetween = const Duration(seconds: 4),
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
        );
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
      );
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
    return {'X-Auth-Token': 'Bearer $token'};
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

/// Injectable configuration for [ShukheeClient]. Deliberately has no
/// defaults for [baseUrl] or [authTokenProvider] — every host app must
/// supply its own, since this SDK has no idea which backend (or which auth
/// scheme) it's being pointed at.
///
/// The three endpoint paths default to the current `frappe-uhis-next`
/// `shukhee_integration` app's routes, but are overridable per-field: if a
/// future deployment moves this behind a dedicated microservice gateway
/// with a different path convention, only the config construction at the
/// call site changes — this class and [ShukheeClient] do not.
library;

class ShukheeConfig {
  const ShukheeConfig({
    required this.baseUrl,
    required this.authTokenProvider,
    this.startConsultationPath =
        '/api/method/shukhee_integration.api.consultation.start_consultation',
    this.getStatusPath =
        '/api/method/shukhee_integration.api.consultation.get_consultation_status',
    this.getPrescriptionPath =
        '/api/method/shukhee_integration.api.consultation.get_prescription',
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 15),
  });

  /// Base URL of the backend exposing the Shukhee consultation endpoints.
  /// Local dev: a `frappe-uhis-next` instance directly. Remote: whatever
  /// dedicated microservice/gateway eventually fronts it.
  final String baseUrl;

  /// Returns the bearer token to send as `X-Auth-Token: Bearer <token>` on
  /// every call. The host app supplies this — typically wrapping its own
  /// already-authenticated session's token — so this SDK never needs to
  /// know how the host app logs in.
  final Future<String?> Function() authTokenProvider;

  final String startConsultationPath;
  final String getStatusPath;
  final String getPrescriptionPath;

  final Duration connectTimeout;
  final Duration receiveTimeout;
}

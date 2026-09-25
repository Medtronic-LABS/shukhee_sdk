/// Injectable configuration for [ShukheeClient]. Deliberately has no
/// defaults for [baseUrl] or [authTokenProvider] — every host app must
/// supply its own, since this SDK has no idea which backend (or which auth
/// scheme) it's being pointed at.
///
/// The endpoint paths default to the current `frappe-uhis-next`
/// `shukhee_integration` app's routes, but are overridable per-field: if a
/// future deployment moves this behind a dedicated microservice gateway
/// with a different path convention, only the config construction at the
/// call site changes — this class and [ShukheeClient] do not.
library;

class ShukheeConfig {
  const ShukheeConfig({
    required this.baseUrl,
    required this.authTokenProvider,
    this.getSpecialitiesPath =
        '/api/method/shukhee_integration.api.consultation.get_specialities',
    this.startConsultationPath =
        '/api/method/shukhee_integration.api.consultation.start_consultation',
    this.getStatusPath =
        '/api/method/shukhee_integration.api.consultation.get_consultation_status',
    this.getPrescriptionPath =
        '/api/method/shukhee_integration.api.consultation.get_prescription',
    this.downloadDocumentPath =
        '/api/method/shukhee_integration.api.consultation.download_document',
    this.tenantIdProvider,
    this.languageCodeProvider,
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

  /// Returns the tenant id to send as a `tenantId` header, if the backend's
  /// auth validation needs one (it does, once the backend's Phase-2 remote
  /// token validation against the legacy auth-service is active — that
  /// endpoint's own contract requires tenantId). Optional: omitted entirely
  /// when null, so a backend that doesn't need it is unaffected.
  final Future<String?> Function()? tenantIdProvider;

  /// Returns the app's current UI language code (e.g. `"en"`/`"bn"`), sent as
  /// the `_lang` query param on every call. Frappe's own request bootstrap
  /// (`HTTPRequest.set_lang` → `translate.get_language()`) reads
  /// `form_dict._lang` with top priority -- ahead of any logged-in user's own
  /// language preference -- so every `frappe.throw(_("..."))` message this
  /// SDK's caller (`shukhee_integration`) raises comes back already
  /// translated into whatever language the app is currently showing, with
  /// zero backend-side plumbing beyond that existing core mechanism. Vendor
  /// (Shukhee)-authored error text is unaffected either way -- it's raw
  /// third-party content, not one of our own `_()`-wrapped strings. Optional:
  /// omitted entirely when null, so a caller that doesn't supply one is
  /// unaffected (falls back to Frappe's own user/System Settings default).
  final Future<String?> Function()? languageCodeProvider;

  final String getSpecialitiesPath;
  final String startConsultationPath;
  final String getStatusPath;
  final String getPrescriptionPath;
  final String downloadDocumentPath;

  final Duration connectTimeout;
  final Duration receiveTimeout;
}

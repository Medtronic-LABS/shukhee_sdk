/// Flutter SDK for the Shukhee (SSK) teleconsultation integration.
///
/// Scoped to exactly 3 backend endpoints (booking, status polling,
/// prescription retrieval) plus an embeddable top-level video-call WebView.
/// Has no dependency on any host app — every host-specific concern (backend
/// base URL, auth token, error-handling conventions) is injected via
/// [ShukheeConfig] or handled by the host app catching [ShukheeException]s
/// at its own integration boundary.
library;

export 'src/shukhee_call_view.dart';
export 'src/shukhee_client.dart';
export 'src/shukhee_config.dart';
export 'src/shukhee_exceptions.dart';
export 'src/shukhee_models.dart';

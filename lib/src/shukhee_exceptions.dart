/// Exceptions thrown by [ShukheeClient]. Self-contained — this package has no
/// dependency on any host app's error hierarchy (e.g. Leapwell's
/// `DomainException`). A host app should catch these at its own integration
/// boundary and map them into its own conventions.
library;

/// Base type for every exception this SDK throws.
sealed class ShukheeException implements Exception {
  const ShukheeException(this.message);

  final String message;

  @override
  String toString() => 'ShukheeException: $message';
}

/// The Shukhee booking/status/prescription call failed for a reason other
/// than the two more specific cases below — network failure, malformed
/// response, or a backend validation error not recognized as one of those.
final class ShukheeBookingException extends ShukheeException {
  const ShukheeBookingException(super.message);
}

/// The calling user's account has no active Provider + Shukhee credential
/// record configured server-side (see `_current_provider`/
/// `_current_shukhee_user` in the backend's `consultation.py`). This is a
/// provisioning gap, not a transient failure — callers should not offer an
/// automatic retry for this one.
final class ShukheeNotProvisionedException extends ShukheeException {
  const ShukheeNotProvisionedException(super.message);
}

/// No auth token was available to attach as `X-Auth-Token` — the configured
/// `authTokenProvider` returned null/empty. No network call is made in this
/// case.
final class ShukheeUnauthorizedException extends ShukheeException {
  const ShukheeUnauthorizedException(super.message);
}

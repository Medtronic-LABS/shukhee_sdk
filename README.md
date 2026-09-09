# shukhee_sdk

Flutter SDK for the [Shukhee](https://shukhee.com) (SSK) teleconsultation integration — a Bangladesh-specific
third-party video-call vendor. Scoped to exactly the 3 endpoints a host backend exposes for booking and
tracking a Shukhee instant video consultation, plus a widget that embeds the call itself as a genuine
top-level `WebView` navigation.

This package has **no dependency on any host app** — no particular HTTP client, error hierarchy, or config
system. A host app injects its own backend base URL and auth-token callback via [`ShukheeConfig`], and
catches this package's own exception types at its integration boundary.

## Why the call view must be a top-level navigation, never an iframe

Shukhee's video-call web app resolves the call session via a cookie set on first load. Inside a
cross-origin `<iframe>`, that cookie is third-party, and browsers refuse to set/send it — the join then
fails (`SESSION_NOT_FOUND` / `INSTANT_CALL_NOT_JOINABLE`) even though the link is perfectly valid. The
identical link loaded as a real top-level page works every time. [`ShukheeCallView`] loads `callUrl`
directly as the sole content of a native `WebView` — from the browser engine's perspective this **is** a
top-level navigation, so it is not subject to that restriction.

## Usage

```dart
import 'package:shukhee_sdk/shukhee_sdk.dart';

final client = ShukheeClient(
  ShukheeConfig(
    baseUrl: 'https://your-backend.example.com',
    authTokenProvider: () async => myApp.currentAuthToken,
  ),
);

final booking = await client.startConsultation(
  contactNumber: '+8801XXXXXXXXX',
  reason: 'Fever, 3 days',
  requestedSpeciality: 'General Physician',
);

// Embed the call inline within your own page:
ShukheeCallView(callUrl: booking.callUrl);

// Poll for completion in the background:
final status = await client.pollStatus(callLog: booking.callLog);
if (status.isCompleted) {
  // status.prescriptionLink / status.invoiceLink
}
```

## Configuration

[`ShukheeConfig`] takes a `baseUrl` and per-endpoint path overrides (defaulting to the current
`frappe-uhis-next` `shukhee_integration` app's routes). If a future deployment fronts this backend with a
dedicated microservice using a different path convention, only the config construction at the call site
changes — this package's client code does not.

## Error handling

All three [`ShukheeClient`] methods throw one of:

- `ShukheeBookingException` — network failure, malformed response, or an unrecognized backend validation
  error.
- `ShukheeNotProvisionedException` — the calling user has no active Provider + Shukhee-credential record
  configured server-side. Not transient — don't offer an automatic retry for this one.
- `ShukheeUnauthorizedException` — no auth token was available; no network call is made in this case.

## Development

```sh
flutter pub get
flutter analyze
flutter test
```

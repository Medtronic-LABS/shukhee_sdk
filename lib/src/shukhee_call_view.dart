import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Embeds a Shukhee video call as a genuine top-level WebView navigation.
///
/// This MUST be the sole content of the WebView — never nested inside
/// another HTML page via an `<iframe>` — since Shukhee's video-call app
/// relies on a first-party session cookie that a cross-origin iframe cannot
/// carry (confirmed live against the sandbox this SDK targets: identical
/// links fail with `SESSION_NOT_FOUND`/`INSTANT_CALL_NOT_JOINABLE` embedded
/// in an iframe, and succeed every time loaded as a real top-level page). A
/// native `WebView` loading [callUrl] directly, as done here, IS a
/// top-level navigation from the browser engine's perspective — it is not
/// subject to that restriction, because the restriction is specifically
/// about content nested inside a *different* origin's page.
///
/// OS-level camera/microphone permission is expected to already be granted
/// before this widget is shown (a host app's own `permission_handler` flow
/// should request it first) — this widget only grants the WebView's own
/// delegated permission request once the page asks for it.
class ShukheeCallView extends StatefulWidget {
  const ShukheeCallView({super.key, required this.callUrl, this.onPageFinished});

  /// The Shukhee join URL from [ShukheeBooking.callUrl].
  final String callUrl;

  /// Called once the page has finished its initial load.
  final VoidCallback? onPageFinished;

  @override
  State<ShukheeCallView> createState() => _ShukheeCallViewState();
}

class _ShukheeCallViewState extends State<ShukheeCallView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  WebViewController _buildController() {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (request) => request.grant(),
    );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => widget.onPageFinished?.call()),
      )
      ..loadRequest(Uri.parse(widget.callUrl));

    return controller;
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

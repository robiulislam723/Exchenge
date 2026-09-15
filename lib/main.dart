import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'services/update_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExchangeApp());
}

class ExchangeApp extends StatelessWidget {
  const ExchangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exchange',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2563EB)),
      home: const WebAppScreen(),
    );
  }
}

class WebAppScreen extends StatefulWidget {
  const WebAppScreen({super.key});

  static const String appUrl = String.fromEnvironment(
    'APP_URL',
    defaultValue: 'https://exchenge.narailexpress.net',
  );

  @override
  State<WebAppScreen> createState() => _WebAppScreenState();
}

class _WebAppScreenState extends State<WebAppScreen> with WidgetsBindingObserver {
  static const MethodChannel _cookieChannel = MethodChannel('app/cookies');

  late final WebViewController _controller;

  bool _loading = true;
  bool _hasError = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _buildController();
    _watchConnectivity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Persist WebView cookies to disk before the OS kills the app, so the
    // Laravel session survives and the user stays logged in.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _flushCookies();
    }
  }

  Future<void> _flushCookies() async {
    try {
      await _cookieChannel.invokeMethod('flush');
    } catch (_) {}
  }

  // Expose the running app version to the page so it can tell whether the
  // installed build supports the native clipboard bridge.
  Future<void> _injectAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      await _controller.runJavaScript(
        "window.__appVersion='${info.version}+${info.buildNumber}';",
      );
    } catch (_) {}
  }

  void _buildController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'NativeClipboard',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (_) => setState(() { _loading = true; _hasError = false; }),
          onPageFinished: (_) {
            setState(() => _loading = false);
            _injectAppVersion();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              setState(() { _hasError = true; _loading = false; });
            }
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith(WebAppScreen.appUrl)) {
              return NavigationDecision.navigate;
            }
            launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(WebAppScreen.appUrl));

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
        ..setMediaPlaybackRequiresUserGesture(false)
        ..enableZoom(true);
    }

    _controller = controller;
  }

  // Reassembly buffers for the chunked base64 image transfer.
  final Map<int, String> _chunks = {};
  int _chunkTotal = 0;
  String _chunkId = '';
  String _chunkMode = 'C';

  // Chunk headers look like: "S<id>-<index>/<total>:<base64>".
  static final RegExp _chunkHeader = RegExp(r'^([CS])([0-9a-z]+)-(\d+)/(\d+):');

  Future<void> _handleBridgeMessage(JavaScriptMessage message) async {
    final raw = message.message;

    final match = _chunkHeader.firstMatch(raw);
    if (match != null) {
      final mode = match.group(1)!;
      final id = match.group(2)!;
      final index = int.tryParse(match.group(3)!) ?? -1;
      final total = int.tryParse(match.group(4)!) ?? -1;
      if (index < 0 || total <= 0) return;

      if (id != _chunkId || total != _chunkTotal || mode != _chunkMode) {
        _chunkId = id;
        _chunkTotal = total;
        _chunkMode = mode;
        _chunks.clear();
      }
      // Everything after the first ':' is the base64 payload.
      _chunks[index] = raw.substring(raw.indexOf(':') + 1);

      if (_chunks.length < _chunkTotal) {
        return; // wait for the remaining parts
      }

      final encoded = List.generate(_chunkTotal, (i) => _chunks[i] ?? '').join();
      final doneMode = _chunkMode;
      _chunks.clear();
      _chunkTotal = 0;
      _chunkId = '';
      await _deliverImage(doneMode, encoded);
      return;
    }

    // Legacy single-message protocol: a data URL / raw base64 string.
    final comma = raw.indexOf(',');
    await _deliverImage('C', comma >= 0 ? raw.substring(comma + 1) : raw);
  }

  Future<void> _deliverImage(String mode, String encoded) async {
    final ok = mode == 'S'
        ? await _shareImage(encoded)
        : await _clipboardImage(encoded);
    try {
      await _controller.runJavaScript(
        'window.__shareResult && window.__shareResult(${ok ? 'true' : 'false'});'
        'window.__clipResult && window.__clipResult(${ok ? 'true' : 'false'});',
      );
    } catch (_) {}
  }

  Future<bool> _clipboardImage(String encoded) async {
    try {
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) return false;
      await Pasteboard.writeImage(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _shareImage(String encoded) async {
    try {
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) return false;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/user-summary-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/jpeg')],
        text: 'User Summary',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _watchConnectivity() async {
    Connectivity().onConnectivityChanged.listen((result) {
      final offline = result is List
          ? result.every((r) => r == ConnectivityResult.none)
          : result == ConnectivityResult.none;
      if (!offline && _hasError) _controller.reload();
    });
  }

  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (_loading && _progress < 100)
                LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
              Expanded(
                child: _hasError
                    ? _ErrorView(onRetry: () {
                        setState(() { _hasError = false; _loading = true; });
                        _controller.reload();
                      })
                    : WebViewWidget(controller: _controller),
              ),
            ],
          ),
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'refresh',
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              tooltip: 'Refresh',
              onPressed: () {
                setState(() => _loading = true);
                _controller.reload();
              },
              child: const Icon(Icons.refresh),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'top',
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2563EB),
              tooltip: 'Back to top',
              onPressed: () => _controller.runJavaScript('window.scrollTo({top:0,behavior:"smooth"});'),
              child: const Icon(Icons.vertical_align_top),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No internet connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Please check your network and try again.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
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
      title: 'Narail Express Exchange',
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

class _WebAppScreenState extends State<WebAppScreen> {
  late final WebViewController _controller;

  bool _loading = true;
  bool _hasError = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _buildController();
    _watchConnectivity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  void _buildController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (_) => setState(() { _loading = true; _hasError = false; }),
          onPageFinished: (_) => setState(() => _loading = false),
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

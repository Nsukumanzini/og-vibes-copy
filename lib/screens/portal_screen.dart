import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:og_vibes_student/widgets/portal_web_frame.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PortalScreen extends StatefulWidget {
  const PortalScreen({super.key});

  @override
  State<PortalScreen> createState() => _PortalScreenState();
}

class _PortalScreenState extends State<PortalScreen> {
  static final _portalUri = Uri.parse(
    'https://ienabler.gscollege.edu.za/pls/prodi41/w99pkg.mi_login',
  );
  WebViewController? _controller;
  Key _webKey = UniqueKey();
  double _progress = 0;
  bool _canGoBack = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setBackgroundColor(Colors.white)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value / 100);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _failed = false);
          },
          onPageFinished: (_) async {
            final back = await _controller?.canGoBack() ?? false;
            if (mounted) setState(() { _progress = 1; _canGoBack = back; });
          },
          onNavigationRequest: (request) {
            return Uri.tryParse(request.url)?.scheme == 'https'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) setState(() => _failed = true);
          },
        ))
        ..loadRequest(_portalUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return VibeScaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/logo.jpeg', width: 36, height: 36, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.school_rounded),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Student Portal', overflow: TextOverflow.ellipsis),
              Text('Powered by OG Vibes', style: TextStyle(fontSize: 11)),
            ],
          )),
        ]),
        actions: [
          IconButton(tooltip: 'Refresh portal', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: 'Open in browser', onPressed: _openExternal, icon: const Icon(Icons.open_in_new_rounded)),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 24 : 10, 8, wide ? 24 : 10, 12),
        child: Semantics(
          label: 'Gert Sibande TVET College student portal',
          container: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
                  border: Border.all(color: Colors.white.withValues(alpha: .2)),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: .16),
                    blurRadius: 28, offset: const Offset(0, 14),
                  )],
                ),
                child: Column(children: [
                  _brandBar(),
                  if (!kIsWeb && _progress < 1)
                    LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 3, color: const Color(0xFF50E3C2),
                    ),
                  Expanded(child: _failed ? _errorView() : _portalView()),
                  _controls(),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandBar() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: const BoxDecoration(gradient: LinearGradient(
      colors: [Color(0xFF071323), Color(0xFF123965), Color(0xFF075E63)],
    )),
    child: const Row(children: [
      Icon(Icons.verified_user_rounded, color: Color(0xFF50E3C2), size: 19),
      SizedBox(width: 8),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gert Sibande TVET College', overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          Text('Secure iEnabler • ienabler.gscollege.edu.za', overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(0xFFB6D5E9), fontSize: 11)),
        ],
      )),
    ]),
  );

  Widget _portalView() {
    if (kIsWeb) {
      return PortalWebFrame(key: _webKey, url: _portalUri.toString());
    }
    return ColoredBox(
      color: Colors.white,
      child: WebViewWidget(controller: _controller!),
    );
  }

  Widget _controls() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (!kIsWeb)
          IconButton(
            tooltip: 'Portal back', onPressed: _canGoBack ? _goBack : null,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        IconButton(tooltip: 'Portal login page', onPressed: _home, icon: const Icon(Icons.home_rounded)),
        IconButton(tooltip: 'Refresh portal', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        FilledButton.tonalIcon(
          onPressed: _openExternal,
          icon: const Icon(Icons.open_in_new_rounded, size: 17),
          label: const Text('Open in browser'),
        ),
      ]),
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 48),
        const SizedBox(height: 12),
        Text('The college portal could not be loaded', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Try again or continue securely in your browser.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
          FilledButton.icon(onPressed: _openExternal, icon: const Icon(Icons.open_in_new_rounded), label: const Text('Open in browser')),
        ]),
      ]),
    ),
  );

  Future<void> _refresh() async {
    setState(() => _failed = false);
    if (kIsWeb) {
      setState(() => _webKey = UniqueKey());
    } else {
      await _controller?.reload();
    }
  }

  Future<void> _home() async {
    if (kIsWeb) {
      setState(() => _webKey = UniqueKey());
    } else {
      await _controller?.loadRequest(_portalUri);
    }
  }

  Future<void> _goBack() async {
    if (await _controller?.canGoBack() ?? false) await _controller?.goBack();
  }

  Future<void> _openExternal() async {
    final opened = await launchUrl(
      _portalUri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the college portal.')),
      );
    }
  }
}

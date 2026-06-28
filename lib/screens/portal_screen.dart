import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class PortalScreen extends StatefulWidget {
  const PortalScreen({super.key});

  @override
  State<PortalScreen> createState() => _PortalScreenState();
}

class _PortalScreenState extends State<PortalScreen> {
  static const String _initialUrl =
      'https://ienabler.gscollege.edu.za/pls/prodi41/w99pkg.mi_login';

  late final WebViewController _controller;
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  final List<String> _historyLog = <String>[];

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setBackgroundColor(Colors.white)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            setState(() => _progress = (value.clamp(0, 100) / 100));
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            await _updateNavigationState();
            setState(() {
              _progress = 1;
              _historyLog.add(url);
            });
            _applyPortalReadabilityStyles();
          },
          onNavigationRequest: (request) {
            if (!request.url.startsWith('https://')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Portal load failed: ${error.errorCode}')),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(_initialUrl));
  }

  Future<void> _updateNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  void _applyPortalReadabilityStyles() {
    const script = '''
      const body = document.body;
      if (body) {
        body.style.backgroundColor = '#ffffff';
        body.style.color = '#111111';
        body.style.fontSize = '16px';
        body.style.lineHeight = '1.6';
      }
      const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
      headings.forEach(h => {
        h.style.color = '#0b2545';
        h.style.fontWeight = '700';
      });
      const links = document.querySelectorAll('a');
      links.forEach(a => {
        a.style.color = '#1a73e8';
      });
      const inputs = document.querySelectorAll('input, textarea, select');
      inputs.forEach(i => {
        i.style.color = '#111111';
        i.style.fontSize = '16px';
      });
    ''';
    _controller.runJavaScript(script);
  }

  @override
  Widget build(BuildContext context) {
    final child = kIsWeb
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The portal experience is best on mobile. Please use the OG Vibes app on your phone for the full portal webview.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              _buildSecureHeader(),
              _buildWatermark(),
              _buildBottomNavigation(),
              _buildSmartTools(),
            ],
          );

    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Student Portal'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        clipBehavior: Clip.hardEdge,
        child: ClipRRect(borderRadius: BorderRadius.circular(24), child: child),
      ),
    );
  }

  Widget _buildSecureHeader() {
    final headerColor = Colors.green.shade800;
    final isLoading = _progress < 1;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 56,
        color: headerColor,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock, color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text(
                  'Encrypted Connection to GS College',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: isLoading
                  ? LinearProgressIndicator(
                      value: _progress,
                      minHeight: 3,
                      color: Colors.amber,
                      backgroundColor: Colors.transparent,
                    )
                  : const SizedBox(height: 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatermark() {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Text(
        'Powered by OG Vibes',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _portalButton(
              icon: Icons.arrow_back,
              label: 'Back',
              enabled: _canGoBack,
              onPressed: _goBack,
            ),
            const SizedBox(width: 8),
            _portalButton(
              icon: Icons.refresh,
              label: 'Refresh',
              enabled: true,
              onPressed: _controller.reload,
            ),
            const SizedBox(width: 8),
            _portalButton(
              icon: Icons.arrow_forward,
              label: 'Forward',
              enabled: _canGoForward,
              onPressed: _goForward,
            ),
            const Spacer(),
            _portalButton(
              icon: Icons.home_filled,
              label: 'Portal',
              enabled: true,
              onPressed: () => _controller.loadRequest(Uri.parse(_initialUrl)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _portalButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          backgroundColor: enabled ? Colors.white.withValues(alpha: 0.2) : Colors.white10,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: enabled ? onPressed : null,
      ),
    );
  }

  Widget _buildSmartTools() {
    return Positioned(
      right: 16,
      bottom: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'zoomInFab',
            backgroundColor: Colors.black.withValues(alpha: 0.7),
            onPressed: () => _runZoom('1.1'),
            child: const Icon(Icons.add, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'zoomOutFab',
            backgroundColor: Colors.black.withValues(alpha: 0.7),
            onPressed: () => _runZoom('1.0'),
            child: const Icon(Icons.remove, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'keyFab',
            backgroundColor: const Color(0xFFFFC857),
            onPressed: _copyStudentNumber,
            child: const Icon(Icons.vpn_key_rounded, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  Future<void> _goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  Future<void> _runZoom(String level) async {
    await _controller.runJavaScript("document.body.style.zoom = '$level';");
  }

  Future<void> _copyStudentNumber() async {
    await Clipboard.setData(const ClipboardData(text: '12345678'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Student Number Copied! Long press input to paste.'),
      ),
    );
  }
}

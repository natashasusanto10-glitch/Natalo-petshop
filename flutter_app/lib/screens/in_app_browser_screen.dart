import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// In-app browser untuk halaman static Natalo (Blog, Help, Kebijakan, dll).
/// Match feel native: header dengan title + URL bar mini, loading bar
/// progress di atas, controls back/forward/refresh/share/open-external.
///
/// Beda dari url_launcher external: tidak keluar app, session cookies
/// tetap (mis. user yang sudah login bisa lihat halaman member-only).
///
/// Beda dari Capacitor WebView (yang notabene HostNgame yang seluruh
/// app-nya): di sini browser cuma untuk konten static, app utama tetap
/// Flutter native.
class InAppBrowserScreen extends StatefulWidget {
  final String url;
  final String? title;

  const InAppBrowserScreen({
    super.key,
    required this.url,
    this.title,
  });

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String? _currentUrl;
  String? _currentTitle;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _currentTitle = widget.title;
  }

  Future<bool> _onWillPop() async {
    if (await _controller?.canGoBack() ?? false) {
      _controller?.goBack();
      return false;
    }
    return true;
  }

  Future<void> _onShare() async {
    AppHaptics.tap();
    final url = _currentUrl ?? widget.url;
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        url,
        subject: _currentTitle,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (_) {}
  }

  Future<void> _onOpenExternal() async {
    AppHaptics.tap();
    final url = _currentUrl ?? widget.url;
    try {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  void _onRefresh() {
    AppHaptics.tap();
    _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = _currentTitle?.trim().isNotEmpty == true
        ? _currentTitle!
        : (widget.title ?? 'Natalo Petshop');
    final urlHost = _currentUrl != null
        ? Uri.tryParse(_currentUrl!)?.host ?? ''
        : '';
    final isSecure = (_currentUrl ?? '').startsWith('https://');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.white,
          toolbarHeight: 60,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF17202A)),
            onPressed: () {
              AppHaptics.tap();
              Navigator.pop(context);
            },
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    isSecure ? Icons.lock_outline_rounded : Icons.public_rounded,
                    size: 11,
                    color: isSecure
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      urlHost,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _brandBlue),
              onPressed: _onRefresh,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share_rounded, color: _brandBlue),
              onPressed: _onShare,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: SizedBox(
              height: 3,
              child: _progress < 1
                  ? LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation(_brandBlue),
                      minHeight: 3,
                    )
                  : null,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              transparentBackground: false,
              javaScriptEnabled: true,
              supportZoom: true,
              builtInZoomControls: false,
              useShouldOverrideUrlLoading: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            onProgressChanged: (controller, progress) {
              setState(() => _progress = progress / 100);
            },
            onLoadStart: (controller, url) {
              setState(() {
                _currentUrl = url?.toString();
                _progress = 0;
              });
            },
            onLoadStop: (controller, url) async {
              final title = await controller.getTitle();
              final canBack = await controller.canGoBack();
              final canForward = await controller.canGoForward();
              if (!mounted) return;
              setState(() {
                _currentUrl = url?.toString();
                _currentTitle = title?.isNotEmpty == true ? title : displayTitle;
                _canGoBack = canBack;
                _canGoForward = canForward;
                _progress = 1;
              });
            },
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url?.toString() ?? '';
              // External / non-http: open di browser system.
              if (!url.startsWith('http')) {
                try {
                  await launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {}
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
        ),
        bottomNavigationBar: _BrowserBottomBar(
          canGoBack: _canGoBack,
          canGoForward: _canGoForward,
          onBack: () {
            AppHaptics.tap();
            _controller?.goBack();
          },
          onForward: () {
            AppHaptics.tap();
            _controller?.goForward();
          },
          onOpenExternal: _onOpenExternal,
        ),
      ),
    );
  }
}

class _BrowserBottomBar extends StatelessWidget {
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onOpenExternal;

  const _BrowserBottomBar({
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 54,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ToolbarButton(
              icon: Icons.arrow_back_ios_new_rounded,
              enabled: canGoBack,
              onTap: onBack,
            ),
            _ToolbarButton(
              icon: Icons.arrow_forward_ios_rounded,
              enabled: canGoForward,
              onTap: onForward,
            ),
            _ToolbarButton(
              icon: Icons.open_in_new_rounded,
              enabled: true,
              onTap: onOpenExternal,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: 20,
        color: enabled ? _brandBlue : const Color(0xFFE5E7EB),
      ),
    );
  }
}

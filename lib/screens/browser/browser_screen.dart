import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/lens_state.dart';
import '../../models/book.dart';
import '../reading/reading_screen.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController _controller;
  bool _busy = false;
  String? _busyText;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _onNavigationRequest),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<NavigationDecision> _onNavigationRequest(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    final ext = _downloadableExtensionFromUri(uri);
    if (ext == null) return NavigationDecision.navigate;

    if (_busy) return NavigationDecision.prevent;
    setState(() {
      _busy = true;
      _busyText = '正在下载$ext...';
    });

    try {
      final localPath = await _downloadToTemp(uri, ext);
      if (!mounted) return NavigationDecision.prevent;

      final level = LensScope.of(context).selectedLevel;
      final book = Book.fromLocalPath(localPath, defaultLevel: level);
      // Immersive reading: push onto the root Navigator to fully cover the
      // CupertinoTabScaffold (avoid the "ghost bottom bar" reserved space).
      await Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(
          builder: (_) => ReadingScreen(book: book),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('[browser] download error=$error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }

    return NavigationDecision.prevent;
  }

  bool _isAllowlistedHost(Uri uri) {
    final host = uri.host.toLowerCase();
    const allow = <String>{
      'www.gutenberg.org',
      'gutenberg.org',
      'standardebooks.org',
      'www.standardebooks.org',
      'archive.org',
      'www.archive.org',
      'openlibrary.org',
      'www.openlibrary.org',
    };
    return allow.contains(host);
  }

  String? _downloadableExtensionFromUri(Uri uri) {
    if (!_isAllowlistedHost(uri)) return null;
    final path = uri.path.toLowerCase();
    if (path.endsWith('.txt')) return '.txt';
    if (path.endsWith('.epub')) return '.epub';
    return null;
  }

  Future<String> _downloadToTemp(Uri uri, String ext) async {
    final dir = await getTemporaryDirectory();

    var name = (uri.pathSegments.isEmpty ? '' : uri.pathSegments.last).trim();
    name = Uri.decodeComponent(name);
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) {
      name = 'download_${DateTime.now().millisecondsSinceEpoch}$ext';
    } else if (!name.toLowerCase().endsWith(ext)) {
      name = '$name$ext';
    }

    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5;
      final response = await client.send(request).timeout(
            const Duration(seconds: 40),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final sink = file.openWrite();
      try {
        await response.stream.pipe(sink);
      } finally {
        await sink.flush();
        await sink.close();
      }
      return file.path;
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('书城'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('返回'),
        ),
      ),
      child: Stack(
        children: [
          SafeArea(child: WebViewWidget(controller: _controller)),
          if (_busy)
            Container(
              color: const Color(0x66FFFFFF),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CupertinoActivityIndicator(),
                    const SizedBox(height: 12),
                    Text(_busyText ?? '处理中...'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

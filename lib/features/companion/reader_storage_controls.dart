import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../models/book.dart';
import '../../services/reader_cache_storage.dart';
import 'lingfer_theme.dart';

class ReaderStorageControls extends StatefulWidget {
  const ReaderStorageControls({
    super.key,
    required this.appState,
    this.storage,
  });

  final AppState appState;
  final ReaderCacheStorage? storage;

  @override
  State<ReaderStorageControls> createState() => _ReaderStorageControlsState();
}

class _ReaderStorageControlsState extends State<ReaderStorageControls> {
  late final ReaderCacheStorage _storage;
  ReaderCacheUsage? _usage;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? ReaderCacheStorage();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final usage = await _storage.inspect();
      if (!mounted) return;
      setState(() {
        _usage = usage;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '暂时无法统计阅读缓存。';
      });
    }
  }

  Future<void> _clear() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final removed = await _storage.clear();
      final remaining = await _storage.inspect();
      if (!mounted) return;
      setState(() => _usage = remaining);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理 ${_bytesLabel(removed.bytes)} 阅读缓存')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = '缓存未清理完成，请重试。');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _archiveExamples() async {
    if (_working) return;
    setState(() => _working = true);
    final state = widget.appState;
    try {
      final removed = await state.archiveEmptyExamples();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed.isEmpty ? '未移除记录，请重试。' : '已移除 ${removed.length} 本旧版空示例',
          ),
          action: removed.isEmpty
              ? null
              : SnackBarAction(
                  label: '撤销',
                  onPressed: () async {
                    try {
                      for (final book in removed.reversed) {
                        await state.addToShelf(book);
                      }
                      if (messenger.mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('旧版示例已恢复')),
                        );
                      }
                    } catch (_) {
                      if (messenger.mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('暂时无法恢复示例，请重试。')),
                        );
                      }
                    }
                  },
                ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法移除示例，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  static String _bytesLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.appState,
    builder: (context, _) {
      final hasExamples = widget.appState.shelf.any(
        (book) => book.source == BookSource.mock,
      );
      return Material(
        color: LingferColors.paper,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本地存储', style: LingferType.interfaceHeading),
              const SizedBox(height: 12),
              Text(
                _loading
                    ? '正在统计阅读缓存…'
                    : _usage == null
                    ? '阅读缓存大小暂不可用'
                    : '阅读缓存 ${_bytesLabel(_usage!.bytes)}',
                key: const ValueKey('reader-cache-usage'),
                style: LingferType.interfaceText.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '只清理可重新生成的书内翻译。资料、阅读进度和生词会保留。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: LingferColors.muted,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: LingferColors.warning,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    key: const ValueKey('reader-cache-clear'),
                    onPressed: _working || _loading || (_usage?.files ?? 0) == 0
                        ? null
                        : _clear,
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                    ),
                    label: Text(_working ? '正在处理…' : '清理阅读缓存'),
                  ),
                  if (_error != null)
                    TextButton(
                      onPressed: _working || _loading ? null : _refresh,
                      child: const Text('重新统计'),
                    ),
                  if (hasExamples)
                    TextButton.icon(
                      key: const ValueKey('reader-empty-examples-remove'),
                      onPressed: _working ? null : _archiveExamples,
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('移除旧版空示例'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

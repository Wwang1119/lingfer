import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;

class ScanImportSortPage extends StatefulWidget {
  const ScanImportSortPage({
    super.key,
    required this.paths,
    this.title = '调整导入顺序',
  });

  final List<String> paths;
  final String title;

  @override
  State<ScanImportSortPage> createState() => _ScanImportSortPageState();
}

class _ScanImportSortPageState extends State<ScanImportSortPage> {
  final List<String> _paths = <String>[];

  @override
  void initState() {
    super.initState();
    _paths.addAll(widget.paths);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6F4EE);
    return material.Scaffold(
      backgroundColor: bg,
      body: material.Material(
        color: bg,
        child: CupertinoPageScaffold(
          backgroundColor: bg,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: bg.withValues(alpha: 0.94),
            border: null,
            middle: Text(widget.title),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(
                CupertinoIcons.xmark,
                size: 18,
                color: Color(0xFF3D3A34),
              ),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () => Navigator.of(context).pop(_paths),
              child: const Icon(
                CupertinoIcons.check_mark,
                size: 18,
                color: Color(0xFF3D3A34),
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: CupertinoColors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0x10000000)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 28,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: const Text(
                      '拖动缩略图调整页序。完成后会按这里的顺序写入扫描册，适合一次导入多页再继续精读。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF6E6E73),
                        decoration: TextDecoration.none,
                        fontFamily: '.SF UI Text',
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: material.ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                    itemCount: _paths.length,
                    proxyDecorator: (child, index, animation) => material.Material(
                      color: material.Colors.transparent,
                      child: child,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _paths.removeAt(oldIndex);
                        _paths.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final path = _paths[index];
                      return Container(
                        key: ValueKey(path),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: CupertinoColors.white.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0x10000000)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 24,
                              offset: Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 64,
                                  height: 84,
                                  child: material.Image.file(
                                    File(path),
                                    fit: material.BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const ColoredBox(
                                      color: Color(0xFFF1EEE6),
                                      child: Icon(
                                        CupertinoIcons.photo,
                                        color: Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '第 ${index + 1} 页',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1C1C1E),
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      path.split(Platform.pathSeparator).last,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: Color(0xFF8E8E93),
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              material.ReorderableDragStartListener(
                                index: index,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2EEE3),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.line_horizontal_3,
                                    color: Color(0xFF6E6E73),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

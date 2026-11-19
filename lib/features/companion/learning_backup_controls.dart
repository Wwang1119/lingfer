import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'companion_controller.dart';

class LearningBackupControls extends StatefulWidget {
  const LearningBackupControls({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<LearningBackupControls> createState() => _LearningBackupControlsState();
}

class _LearningBackupControlsState extends State<LearningBackupControls> {
  bool busy = false;
  Future<void> perform(bool restore) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      String? message;
      if (restore) {
        final files = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          withData: true,
        );
        if (files == null) return;
        final file = files.files.single;
        if (file.size > 5 * 1024 * 1024) {
          throw const FormatException('备份文件不能超过 5 MB');
        }
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        if (!mounted) return;
        final merge = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('合并学习备份'),
            content: const Text('将备份中的词条、熟词和复习进度加入当前生词本，不清空现有内容。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('合并'),
              ),
            ],
          ),
        );
        if (merge != true) return;
        final count = await widget.controller.importLearningBackup(
          utf8.decode(bytes),
        );
        message = '已合并备份，新增 $count 个词';
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '导出语渡学习备份',
          fileName:
              '语渡学习备份-${DateTime.now().toIso8601String().substring(0, 10)}.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(
            utf8.encode(widget.controller.exportLearningBackup()),
          ),
        );
        if (result != null) message = '学习备份已导出';
      }
      if (mounted && message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message.toString()
                  : '备份未完成，请重试。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      TextButton.icon(
        onPressed: busy ? null : () => perform(false),
        icon: const Icon(Icons.ios_share, size: 18),
        label: const Text('导出学习备份'),
      ),
      TextButton.icon(
        onPressed: busy ? null : () => perform(true),
        icon: const Icon(Icons.file_open_outlined, size: 18),
        label: const Text('导入备份'),
      ),
    ],
  );
}

import 'package:flutter/cupertino.dart';

import '../models/vocabulary_level.dart';
import '../utils/level_color.dart';

Future<VocabularyLevel?> showVocabularyLevelActionSheet(
  BuildContext context, {
  String title = '选择难度',
  String message = '该难度将绑定到这本书，并作为书架唯一标识的一部分。',
  VocabularyLevel? selected,
}) async {
  VocabularyLevel? result;
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (context) {
      return CupertinoActionSheet(
        title: Text(title),
        message: Text(message),
        actions: [
          for (final level in VocabularyLevel.values)
            CupertinoActionSheetAction(
              isDefaultAction: level == selected,
              onPressed: () {
                result = level;
                Navigator.of(context).pop();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: getLevelColor(level.label),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(level.label),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      );
    },
  );
  return result;
}


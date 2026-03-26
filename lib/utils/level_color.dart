import 'package:flutter/cupertino.dart';

Color getLevelColor(String levelLabel) {
  final s = levelLabel;
  if (s.contains('四级')) return const Color(0xFF4CAF50);
  if (s.contains('六级')) return const Color(0xFF2196F3);
  if (s.contains('考研')) return const Color(0xFF9C27B0);
  if (s.contains('雅思') || s.contains('托福')) return const Color(0xFFFF9800);
  return const Color(0xFF999999);
}


import 'package:flutter/cupertino.dart';

enum ReaderThemeKind { original, quiet, paper, bold, calm, focus }

class ReaderTheme {
  const ReaderTheme._({
    required this.kind,
    required this.label,
    required this.background,
    required this.textColor,
  });

  final ReaderThemeKind kind;
  final String label;
  final Color background;
  final Color textColor;

  static const original = ReaderTheme._(
    kind: ReaderThemeKind.original,
    label: '原始',
    background: Color(0xFFFFFFFF),
    textColor: Color(0xFF2B2B2B),
  );

  static const quiet = ReaderTheme._(
    kind: ReaderThemeKind.quiet,
    label: '安静',
    background: Color(0xFF1A1A1A),
    textColor: Color(0xFFE2E2E2),
  );

  static const paper = ReaderTheme._(
    kind: ReaderThemeKind.paper,
    label: '纸张',
    background: Color(0xFFFBF0D9),
    textColor: Color(0xFF2B2B2B),
  );

  static const bold = ReaderTheme._(
    kind: ReaderThemeKind.bold,
    label: '粗体',
    background: Color(0xFF0B0B0C),
    textColor: Color(0xFFEFEFF4),
  );

  static const calm = ReaderTheme._(
    kind: ReaderThemeKind.calm,
    label: '平静',
    background: Color(0xFF3A352D),
    textColor: Color(0xFFF2F0EA),
  );

  static const focus = ReaderTheme._(
    kind: ReaderThemeKind.focus,
    label: '专注',
    background: Color(0xFF2B2F24),
    textColor: Color(0xFFF2F2E6),
  );

  static List<ReaderTheme> get all =>
      const [original, quiet, paper, bold, calm, focus];

  static ReaderTheme fromPrefs(String? value) {
    switch (value) {
      // Legacy values (<=1.1.10)
      case 'dayWhite':
        return original;
      case 'parchment':
        return paper;
      case 'night':
        return quiet;
      // New values
      case 'original':
        return original;
      case 'quiet':
        return quiet;
      case 'paper':
        return paper;
      case 'bold':
        return bold;
      case 'calm':
        return calm;
      case 'focus':
        return focus;
      default:
        return original;
    }
  }

  String toPrefs() => kind.name;
}

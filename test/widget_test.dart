import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lingfer/main.dart';
import 'package:lingfer/features/companion/vocabulary_engine.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Reading works without a configured cloud service', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(VocabularyEngine.load);
    await tester.pumpWidget(const LingferRoot());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('语渡'), findsOneWidget);
    expect(find.text('生词本'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('试读一段'),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reading-home-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('试读一段')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('试读一段'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Learning a language'), findsOneWidget);
    await tester.tap(find.text('词卡'));
    await tester.pumpAndSettle();
    expect(find.textContaining('找到 '), findsOneWidget);
    await tester.tap(find.byTooltip('收藏生词').first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('生词本'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已收藏 1 个'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

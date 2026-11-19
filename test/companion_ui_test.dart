import 'package:lingfer/services/ai_consent_store.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lingfer/main.dart';
import 'package:lingfer/models/book.dart';
import 'package:lingfer/widgets/book_display_title.dart';
import 'package:lingfer/models/vocabulary_level.dart';
import 'package:lingfer/features/companion/companion_controller.dart';
import 'package:lingfer/features/companion/companion_shell.dart';
import 'package:lingfer/features/companion/lingfer_theme.dart';
import 'package:lingfer/features/companion/reading_assistant.dart';
import 'package:lingfer/features/companion/reading_preferences.dart';
import 'package:lingfer/features/companion/vocabulary_engine.dart';

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> settleResources(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pumpAndSettle();
}

Future<void> openLanguageSettings(WidgetTester tester, String direction) async {
  final home = find.byKey(const ValueKey('reading-home-scroll'));
  final entry = find.descendant(of: home, matching: find.text(direction));
  await tester.scrollUntilVisible(
    entry,
    200,
    scrollable: find
        .descendant(of: home, matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

Future<void> tapLanguageControl(WidgetTester tester, Finder control) async {
  if (control.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      control,
      160,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> openReader(
  WidgetTester tester,
  CompanionController controller,
  String content, {
  double scale = 1,
}) async {
  await tester.runAsync(controller.initialize);
  await tester.pumpWidget(
    MaterialApp(
      theme: lingferTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: CompanionTextReader(
        controller: controller,
        title: '阅读测试',
        text: content,
      ),
    ),
  );
  await settleResources(tester);
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      AiConsentStore.versionKey: AiConsentStore.currentVersion,
      AiConsentStore.allowedKey: true,
    }),
  );

  testWidgets(
    'Import tools keep two columns and the glass file menu preserves pin, remove and undo',
    (tester) async {
      viewport(tester, const Size(344, 842));
      const book = Book(
        title: '0123abcd_资料菜单测试',
        author: '',
        defaultLevel: VocabularyLevel.cet4,
        source: BookSource.localFile,
        locator: '/data/test/Lingfer/ImportedBooks/0123abcd_资料菜单测试.txt',
      );
      SharedPreferences.setMockInitialValues({
        AiConsentStore.versionKey: AiConsentStore.currentVersion,
        AiConsentStore.allowedKey: true,
        'lens_shelf_v2': jsonEncode([book.toJson()]),
      });
      expect(book.displayTitle, '资料菜单测试');
      final identity = book.stableKey;
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await settleResources(tester);
      expect(book.stableKey, identity);
      final paste = tester.getRect(find.byKey(const ValueKey('entry-粘贴文字')));
      final camera = tester.getRect(find.byKey(const ValueKey('entry-拍照识别')));
      expect(paste.top, camera.top);
      expect((paste.width - camera.width).abs(), lessThan(1));
      await tester.scrollUntilVisible(
        find.byTooltip('资料操作'),
        280,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('reading-home-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byTooltip('资料操作'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();
      expect(find.textContaining('置顶 · '), findsOneWidget);
      final persisted =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'lens_shelf_v2',
                )!,
              )
              as List;
      expect(persisted.single['title'], book.title);
      expect(persisted.single['locator'], book.locator);
      await tester.tap(find.byTooltip('资料操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从资料列表移除'));
      await tester.pumpAndSettle();
      expect(find.text('资料菜单测试'), findsNothing);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(find.text('资料菜单测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A transient zero-width fold viewport recovers to a readable home',
    (tester) async {
      await tester.runAsync(VocabularyEngine.load);
      viewport(tester, Size.zero);
      await tester.pumpWidget(const LingferRoot());
      await settleResources(tester);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(344, 842);
      await tester.pumpAndSettle();
      expect(find.text('语渡'), findsWidgets);
      expect(
        find.byKey(const ValueKey('primary-reading-action')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android language lists return to their settings and preserve the selected direction on restart',
    (tester) async {
      viewport(tester, const Size(390, 844));
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await settleResources(tester);
      await openLanguageSettings(tester, '自动识别 → 中文');

      final source = find.byKey(const ValueKey('reading-source-language'));
      final target = find.byKey(const ValueKey('reading-target-language'));
      Finder language(String code) =>
          find.byKey(ValueKey('reading-language-$code'));
      await tapLanguageControl(tester, source);
      expect(language('auto'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: source, matching: find.text('自动识别')),
        findsOneWidget,
      );

      await tapLanguageControl(tester, source);
      await tapLanguageControl(tester, language('fr'));
      expect(
        find.descendant(of: source, matching: find.text('法语')),
        findsOneWidget,
      );
      await tapLanguageControl(tester, target);
      expect(language('auto'), findsNothing);
      await tapLanguageControl(tester, language('ko'));
      expect(
        find.descendant(of: target, matching: find.text('韩语')),
        findsOneWidget,
      );
      await tapLanguageControl(tester, find.byTooltip('关闭语言设置'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const LingferRoot());
      await settleResources(tester);
      await openLanguageSettings(tester, '法语 → 韩语');
      expect(
        find.descendant(of: source, matching: find.text('法语')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: target, matching: find.text('韩语')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Android language selection and back stay reachable on a narrow screen with large type',
    (tester) async {
      viewport(tester, const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await settleResources(tester);
      await openLanguageSettings(tester, '自动识别 → 中文');

      final target = find.byKey(const ValueKey('reading-target-language'));
      await tapLanguageControl(tester, target);
      await tapLanguageControl(
        tester,
        find.byKey(const ValueKey('reading-language-hi')),
      );
      expect(
        find.descendant(of: target, matching: find.text('印地语')),
        findsOneWidget,
      );
      await tapLanguageControl(tester, target);
      expect(find.byKey(const ValueKey('reading-language-auto')), findsNothing);
      await tapLanguageControl(tester, find.byTooltip('返回语言设置'));
      await tapLanguageControl(tester, find.byTooltip('关闭语言设置'));
      expect(find.text('自动识别 → 印地语'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'iOS language settings still select the target through the original field',
    (tester) async {
      viewport(tester, const Size(390, 844));
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await settleResources(tester);
      await openLanguageSettings(tester, '自动识别 → 中文');

      expect(
        find.byType(DropdownButtonFormField<ReadingLanguage>),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const ValueKey('reading-target-language')),
        findsNothing,
      );
      await tapLanguageControl(tester, find.byKey(const ValueKey('target-zh')));
      await tapLanguageControl(tester, find.text('日语').last);
      expect(find.byKey(const ValueKey('target-ja')), findsOneWidget);
      await tapLanguageControl(tester, find.byTooltip('关闭语言设置'));
      expect(find.text('自动识别 → 日语'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Compact phone keeps entry, level sheet and keyboard usable', (
    tester,
  ) async {
    viewport(tester, const Size(320, 568));
    await tester.runAsync(VocabularyEngine.load);
    await tester.pumpWidget(const LingferRoot());
    await settleResources(tester);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('learning-range')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reading-home-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('learning-range')).first),
      alignment: .4,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('learning-range')).first);
    await tester.pumpAndSettle();
    expect(find.text('选择学习范围'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('托福'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('托福'));
    await tester.pumpAndSettle();
    expect(find.text('托福'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('粘贴文字')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴文字'));
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, '开始阅读');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Researchers maintain that consistent practice is effective.',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
  });

  testWidgets(
    'Unfolded view shows original and vocabulary together and restores familiar word',
    (tester) async {
      viewport(tester, const Size(690, 820));
      final controller = CompanionController();
      addTearDown(controller.dispose);
      await openReader(
        tester,
        controller,
        'Researchers maintain that consistent practice is effective.',
      );
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(WordCard), findsWidgets);
      final firstWord = tester
          .widget<WordCard>(find.byType(WordCard).first)
          .hit
          .entry
          .word;
      await tester.tap(find.text('标为熟词').first);
      await tester.pumpAndSettle();
      expect(controller.known, contains(firstWord));
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(controller.known, isNot(contains(firstWord)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Long text, empty vocabulary and large type remain scrollable', (
    tester,
  ) async {
    viewport(tester, const Size(320, 640));
    final controller = CompanionController();
    addTearDown(controller.dispose);
    await openReader(
      tester,
      controller,
      List.filled(100, 'Hello world. This is a book.').join('\n\n'),
      scale: 1.8,
    );
    await tester.tap(find.text('词卡'));
    await tester.pumpAndSettle();
    expect(find.text('当前范围没有匹配词'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Explanation preserves source through loading, failure and a successful retry',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final reply = Completer<http.Response>();
      var requests = 0;
      final assistant = ReadingAssistant(
        proxyUrl: 'https://test.local',
        appSecret: 'test',
        client: MockClient(
          (_) => ++requests == 1
              ? reply.future
              : Future.value(
                  http.Response(
                    '{"choices":[{"message":{"content":"本句中的 maintain 表示认为或主张。"}}]}',
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  ),
                ),
        ),
      );
      final controller = CompanionController(assistant: assistant);
      addTearDown(controller.dispose);
      await openReader(
        tester,
        controller,
        'Researchers maintain that consistent practice is effective.',
      );
      await tester.tap(find.text('词卡'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('语境讲解').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('正在结合原文讲解…'), findsOneWidget);
      reply.complete(http.Response('', 503));
      await tester.pumpAndSettle();
      expect(find.text('AI 服务暂时没有响应，请稍后重试。'), findsOneWidget);
      expect(find.text('重新请求讲解'), findsOneWidget);
      expect(find.textContaining('基础释义 ·'), findsOneWidget);
      await tester.tap(find.text('重新请求讲解'));
      await tester.pumpAndSettle();
      expect(find.text('本句中的 maintain 表示认为或主张。'), findsOneWidget);
      expect(requests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Reading workspace opens vocabulary and settings with large text and reduced motion',
    (tester) async {
      viewport(tester, const Size(320, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            highContrast: true,
          );
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await settleResources(tester);
      expect(find.text('渡'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      final paste = tester.getRect(find.byKey(const ValueKey('entry-粘贴文字')));
      final camera = tester.getRect(find.byKey(const ValueKey('entry-拍照识别')));
      expect(paste.bottom, lessThan(camera.top));
      for (final key in ['open-vocabulary', 'open-settings']) {
        final action = find.byKey(ValueKey(key));
        expect(tester.getRect(action).right, lessThanOrEqualTo(320));
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('Empty content provides recovery actions', (tester) async {
    viewport(tester, const Size(390, 700));
    final controller = CompanionController();
    addTearDown(controller.dispose);
    await openReader(tester, controller, '   ');
    expect(find.text('这次没有读到内容'), findsOneWidget);
    expect(find.text('重新读取'), findsOneWidget);
    expect(find.text('改用粘贴文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

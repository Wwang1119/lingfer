import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lingfer/features/companion/lingfer_theme.dart';
import 'package:lingfer/services/ai_consent_store.dart';
import 'package:lingfer/widgets/ai_consent_panel.dart';

Future<void> mountEntry(
  WidgetTester tester, {
  bool firstUseOnly = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lingferTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              AiConsentEntry(firstUseOnly: firstUseOnly),
              TextButton(onPressed: () {}, child: const Text('本地阅读入口')),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai-consent-entry')));
  await tester.pumpAndSettle();
  expect(find.byType(AiConsentPanel), findsOneWidget);
}

Future<void> choose(WidgetTester tester, String key) async {
  final action = find.byKey(ValueKey(key));
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('First use offers a choice without blocking local reading', (
    tester,
  ) async {
    await mountEntry(tester, firstUseOnly: true);
    expect(find.text('联网 AI 尚未开启'), findsOneWidget);
    expect(find.text('本地阅读入口'), findsOneWidget);
    expect(find.byType(AiConsentPanel), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AiConsentStore.versionKey), isFalse);
    expect(prefs.containsKey(AiConsentStore.allowedKey), isFalse);
    expect(await AiConsentStore.isAllowed(), isFalse);
  });

  testWidgets('Opening then dismissing the explanation never grants consent', (
    tester,
  ) async {
    await mountEntry(tester);
    await openPanel(tester);
    expect(find.text(AiConsentStore.disclosure), findsOneWidget);
    expect(await AiConsentStore.isAllowed(), isFalse);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AiConsentPanel), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AiConsentStore.versionKey), isFalse);
    expect(prefs.containsKey(AiConsentStore.allowedKey), isFalse);
    expect(find.text('本地阅读入口'), findsOneWidget);
  });

  testWidgets('Only an explicit allow action enables the current version', (
    tester,
  ) async {
    await mountEntry(tester);
    await openPanel(tester);
    expect(await AiConsentStore.isAllowed(), isFalse);
    await choose(tester, 'ai-consent-allow');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(AiConsentStore.versionKey),
      AiConsentStore.currentVersion,
    );
    expect(prefs.getBool(AiConsentStore.allowedKey), isTrue);
    expect(find.text('已允许 · 可查看说明或关闭'), findsOneWidget);
    expect(find.text('本地阅读入口'), findsOneWidget);
  });

  testWidgets('Choosing local reading records refusal and keeps settings', (
    tester,
  ) async {
    await mountEntry(tester);
    await openPanel(tester);
    await choose(tester, 'ai-consent-local');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(AiConsentStore.versionKey),
      AiConsentStore.currentVersion,
    );
    expect(prefs.getBool(AiConsentStore.allowedKey), isFalse);
    expect(find.text('联网 AI 与隐私'), findsOneWidget);
    expect(find.text('仅本机阅读 · 联网 AI 已关闭，可重新选择'), findsOneWidget);
    expect(find.text('本地阅读入口'), findsOneWidget);
  });

  testWidgets('An allowed user can withdraw without losing the local entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AiConsentStore.versionKey: AiConsentStore.currentVersion,
      AiConsentStore.allowedKey: true,
      'unrelated_saved_words': 'preserved',
    });
    await mountEntry(tester);
    expect(find.text('已允许 · 可查看说明或关闭'), findsOneWidget);
    await openPanel(tester);
    await choose(tester, 'ai-consent-local');
    expect(await AiConsentStore.isAllowed(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('unrelated_saved_words'), 'preserved');
    expect(find.text('本地阅读入口'), findsOneWidget);
  });

  testWidgets(
    'Policy and full local disclosure remain reachable at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountEntry(tester, textScale: 2);
      await openPanel(tester);
      expect(find.text(AiConsentStore.disclosure), findsOneWidget);
      expect(AiConsentStore.disclosure, contains('通过腾讯云中转发送给 DeepSeek'));
      expect(AiConsentStore.disclosure, contains('内容变化时可能自动发送文字'));
      expect(AiConsentStore.disclosure, contains('实际云端留存规则尚未核实'));
      expect(find.textContaining('当前没有账号云同步'), findsOneWidget);
      final policy = find.byKey(const ValueKey('ai-consent-policy'));
      await tester.ensureVisible(policy);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(policy).onPressed, isNotNull);
      expect(
        AiConsentStore.policyUrl,
        'https://docs.qq.com/doc/DRnZUeGhsY2JraXJD',
      );
      // Leave external browser launching to the platform; this test neither
      // mocks a successful launch nor navigates the test host's browser.
      await choose(tester, 'ai-consent-local');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A settings choice updates the existing first-use entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lingferTheme(),
        home: const Scaffold(
          body: Column(
            children: [AiConsentEntry(firstUseOnly: true), AiConsentEntry()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('联网 AI 尚未开启'), findsOneWidget);
    await tester.tap(find.text('联网 AI 与隐私'));
    await tester.pumpAndSettle();
    await choose(tester, 'ai-consent-allow');
    expect(find.text('联网 AI 尚未开启'), findsNothing);
    expect(find.text('已允许 · 可查看说明或关闭'), findsOneWidget);
  });
}

import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingfer/services/ai_consent_store.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lingfer/features/companion/reading_assistant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Consent is limited to public mocked fixtures; no device preference is changed.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      AiConsentStore.versionKey: AiConsentStore.currentVersion,
      AiConsentStore.allowedKey: true,
    }),
  );
  test(
    'Offline mode fails clearly without attempting a network request',
    () async {
      final assistant = ReadingAssistant(
        proxyUrl: '',
        appSecret: '',
        client: MockClient(
          (_) async => throw StateError('Must remain offline'),
        ),
      );
      expect(assistant.isConfigured, false);
      await expectLater(
        assistant.explain(text: 'A sentence.', level: '四级'),
        throwsA(isA<AssistantUnavailable>()),
      );
      expect(await assistant.checkConnection(), contains('离线'));
      assistant.dispose();
    },
  );

  test(
    'Context explanation sends only the requested excerpt and decodes Chinese',
    () async {
      final assistant = ReadingAssistant(
        proxyUrl: 'https://example.test/proxy',
        appSecret: 'test-only',
        client: MockClient((request) async {
          expect(request.headers['X-App-Secret'], 'test-only');
          final body = jsonDecode(request.body) as Map;
          expect(
            (body['messages'] as List).last['content'],
            contains('重点单词：maintain'),
          );
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'maintain 在这里表示“保持”。'},
                  },
                ],
              }),
            ),
            200,
          );
        }),
      );
      expect(
        await assistant.explain(
          text: 'We maintain it.',
          word: 'maintain',
          level: '四级',
        ),
        contains('保持'),
      );
      assistant.dispose();
    },
  );

  test('An expired service produces a recoverable user-facing error', () async {
    final assistant = ReadingAssistant(
      proxyUrl: 'https://example.test/proxy',
      appSecret: 'test-only',
      client: MockClient((_) async => http.Response('not found', 404)),
    );
    await expectLater(
      assistant.explain(text: 'hello', level: '四级'),
      throwsA(isA<AssistantUnavailable>()),
    );
    expect(await assistant.checkConnection(), contains('暂不可用'));
    assistant.dispose();
  });
}

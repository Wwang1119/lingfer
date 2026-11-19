import 'dart:io';

import 'package:flutter/services.dart';

class ScreenReaderBridge {
  static const _channel = MethodChannel('lingfer/screen_reader');
  static const _appleChannel = MethodChannel('lingfer/share_reader');
  static EventChannel get events => EventChannel(
    Platform.isIOS
        ? 'lingfer/apple_screen_reader_events'
        : 'lingfer/screen_reader_events',
  );

  bool get supported => Platform.isAndroid;
  bool get supportsLiveCapture => supported || Platform.isIOS;
  bool get hasNativeCompanion => Platform.isAndroid || Platform.isIOS;

  Future<Map<String, dynamic>> status() async {
    if (!hasNativeCompanion) return {'supported': false, 'running': false};
    final channel = Platform.isIOS ? _appleChannel : _channel;
    final raw = await channel.invokeMapMethod<String, dynamic>('status');
    return raw ?? {'supported': true, 'running': false};
  }

  Future<void> requestOverlayPermission() async {
    if (supported) {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    }
  }

  Future<void> configure({
    required String level,
    required List<String> known,
    required String proxyUrl,
    required String appSecret,
    required String saved,
    Map<String, Object?> readingPreferences = const {},
  }) async {
    if (!hasNativeCompanion) return;
    final channel = Platform.isIOS ? _appleChannel : _channel;
    await channel.invokeMethod<void>('configure', {
      'level': level,
      'known': known,
      'proxyUrl': proxyUrl,
      'appSecret': appSecret,
      'saved': saved,
      ...readingPreferences,
    });
  }

  Future<bool> start() async =>
      supportsLiveCapture &&
      await (Platform.isIOS ? _appleChannel : _channel).invokeMethod<bool>(
            'start',
          ) ==
          true;
  Future<void> stop() async {
    if (supportsLiveCapture)
      await (Platform.isIOS ? _appleChannel : _channel).invokeMethod<void>(
        'stop',
      );
  }

  Future<void> capture() async {
    if (supportsLiveCapture)
      await (Platform.isIOS ? _appleChannel : _channel).invokeMethod<void>(
        'capture',
      );
  }
}

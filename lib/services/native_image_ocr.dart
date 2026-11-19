import 'dart:io';
import 'package:flutter/services.dart';

enum OcrScript { latin, chinese, japanese, korean, devanagari }

/// Android uses the same bundled ML Kit models as screen reading; Apple uses
/// Vision. Keeping this boundary native avoids bundling unused iOS ML models.
abstract final class NativeImageOcr {
  static MethodChannel get _channel => MethodChannel(
    Platform.isAndroid ? 'lingfer/image_ocr' : 'lingfer/vision_ocr',
  );

  static Future<String> text(
    String path, {
    OcrScript script = OcrScript.latin,
    String? language,
  }) async =>
      await _channel.invokeMethod<String>('recognizeText', {
        'path': path,
        'script': script.name,
        'language': ?language,
      }) ??
      '';

  static Future<Map> layout(
    String path, {
    OcrScript script = OcrScript.latin,
    String? language,
  }) async =>
      await _channel.invokeMapMethod('recognizeTextLayout', {
        'path': path,
        'script': script.name,
        'language': ?language,
      }) ??
      {};
}

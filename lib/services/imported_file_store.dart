import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Ensures a user-selected file becomes readable long-term in the macOS sandbox.
///
/// On macOS sandboxed apps, paths returned by pickers (or Finder open events)
/// may be security-scoped and not directly readable after lifecycle changes.
/// The simplest robust approach is to copy the file into our own container and
/// only read from there.
class ImportedFileStore {
  static const MethodChannel _securityScope =
      MethodChannel('lingfer/security_scope');

  static Future<Directory> _importDir() async {
    final support = await getApplicationSupportDirectory();
      final dir = Directory(
        '${support.path}${Platform.pathSeparator}Lingfer${Platform.pathSeparator}ImportedBooks',
      );
    await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _startSecurityScopeIfNeeded(String path) async {
    if (!Platform.isMacOS) return;
    try {
      await _securityScope.invokeMethod('startAccess', path);
    } catch (_) {
      // Best-effort: even if this fails, we may still be able to read the file
      // (e.g. already inside our container).
    }
  }

  static String _sanitizeFileName(String name) {
    // Keep Unicode (Chinese) intact; only replace illegal path characters.
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'imported_file';
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static int _fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Copies [sourcePath] into Application Support and returns the new path.
  /// If copy fails, returns [sourcePath] as a fallback.
  static Future<String> ingest(String sourcePath) async {
    await _startSecurityScopeIfNeeded(sourcePath);

    try {
      final dir = await _importDir();
      final canonicalDir = dir.absolute.path;
      final canonicalSrc = File(sourcePath).absolute.path;
      if (canonicalSrc.startsWith(canonicalDir + Platform.pathSeparator)) {
        // Already inside our container; nothing to do.
        return canonicalSrc;
      }

      final baseName = sourcePath.split(Platform.pathSeparator).last;
      final safeName = _sanitizeFileName(baseName);
      String fingerprint;
      try {
        final stat = await File(sourcePath).stat();
        fingerprint =
            '$canonicalSrc|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
      } catch (_) {
        fingerprint = canonicalSrc;
      }
      final hash = _fnv1a32(fingerprint).toRadixString(16).padLeft(8, '0');
      final destPath = '${dir.path}${Platform.pathSeparator}${hash}_$safeName';
      final destFile = File(destPath);
      if (await destFile.exists()) return destFile.path;

      final copied = await File(sourcePath).copy(destFile.path);
      return copied.path;
    } catch (_) {
      return sourcePath;
    }
  }
}

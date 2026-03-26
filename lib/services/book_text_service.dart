import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:docx_to_text/docx_to_text.dart';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

import '../models/book.dart';

class BookTextService {
  Future<String> readBookText(Book book) async {
    switch (book.source) {
      case BookSource.localFile:
        return _readFromFile(book.locator);
      case BookSource.asset:
        return _readFromAsset(book.locator);
      case BookSource.mock:
        return '（这是占位书籍：${book.title}）\n\n把真实 txt/epub 导入到书架后即可阅读。';
    }
  }

  Future<String> _readFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return _decodeByExtension(path, bytes);
  }

  Future<String> _readFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    return _decodeByExtension(assetPath, bytes);
  }

  Future<String> _decodeByExtension(String locator, List<int> bytes) async {
    final lower = locator.toLowerCase();
    if (lower.endsWith('.epub')) {
      return _readEpub(bytes);
    }
    if (lower.endsWith('.docx')) {
      return _readDocx(bytes);
    }
    return _decodeTxtBytes(bytes);
  }

  String _decodeTxtBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: false);
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return gbk.decode(bytes);
    }
  }

  Future<String> _readEpub(List<int> bytes) async {
    final book = await EpubReader.readBook(bytes);
    final buffer = StringBuffer();

    final title = (book.Title ?? '').trim();
    final author = (book.Author ?? '').trim();
    if (title.isNotEmpty) buffer.writeln(title);
    if (author.isNotEmpty) buffer.writeln(author);
    if (buffer.isNotEmpty) buffer.writeln();

    final chapters = book.Chapters ?? const <EpubChapter>[];
    for (final chapter in chapters) {
      _appendChapter(buffer, chapter);
    }

    final result = buffer.toString().trimRight();
    return result.isEmpty ? '（未能提取到文本内容）' : result;
  }

  Future<String> _readDocx(List<int> bytes) async {
    // Use a robust parser: docx_to_text can stop early on some malformed nodes.
    // We parse document.xml ourselves and keep going even if a paragraph fails.
    return await runZoned(
      () async {
        final text = _docxToTextSafely(Uint8List.fromList(bytes));
        return text.trim().isEmpty ? '（未能提取到文本内容）' : text;
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {},
      ),
    );
  }

  String _docxToTextSafely(Uint8List bytes) {
    List<int>? xmlBytes;
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        if (f.isFile && f.name == 'word/document.xml') {
          xmlBytes = f.content as List<int>;
          break;
        }
      }
    } catch (_) {
      xmlBytes = null;
    }

    final docXmlBytes = xmlBytes;
    if (docXmlBytes == null || docXmlBytes.isEmpty) {
      // Last resort fallback to the package implementation.
      try {
        return docxToText(bytes);
      } catch (_) {
        return '';
      }
    }

    final xmlText = utf8.decode(docXmlBytes, allowMalformed: true);
    try {
      final document = xml.XmlDocument.parse(xmlText);
      final lines = <String>[];
      final paragraphs = document.findAllElements('w:p');
      for (final p in paragraphs) {
        try {
          final buf = StringBuffer();
          for (final el in p.descendantElements) {
            final local = el.name.local;
            if (local == 't') {
              buf.write(el.innerText);
            } else if (local == 'tab') {
              buf.write('\t');
            } else if (local == 'br' || local == 'cr') {
              buf.write('\n');
            }
          }
          lines.add(buf.toString());
        } catch (_) {
          // Critical: never break. Continue reading remaining paragraphs.
          continue;
        }
      }
      return lines.join('\n');
    } catch (_) {
      // Fallback: regex extract w:t text when XML parsing fails.
      final matches = RegExp(r'<w:t[^>]*>([\s\S]*?)</w:t>', multiLine: true)
          .allMatches(xmlText);
      final out = StringBuffer();
      for (final m in matches) {
        final raw = m.group(1) ?? '';
        out.writeln(_xmlUnescape(raw));
      }
      return out.toString();
    }
  }

  String _xmlUnescape(String s) {
    var t = s;
    t = t.replaceAll('&lt;', '<');
    t = t.replaceAll('&gt;', '>');
    t = t.replaceAll('&quot;', '"');
    t = t.replaceAll('&apos;', "'");
    t = t.replaceAll('&amp;', '&');
    // Numeric entities.
    t = t.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      if (code == null) return m.group(0) ?? '';
      return String.fromCharCode(code);
    });
    t = t.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      if (code == null) return m.group(0) ?? '';
      return String.fromCharCode(code);
    });
    return t;
  }

  void _appendChapter(StringBuffer buffer, EpubChapter chapter) {
    final title = (chapter.Title ?? '').trim();
    if (title.isNotEmpty) {
      buffer.writeln(title);
      buffer.writeln();
    }

    final html = (chapter.HtmlContent ?? '').trim();
    if (html.isNotEmpty) {
      final text = _htmlToPlainText(html);
      if (text.isNotEmpty) {
        buffer.writeln(text);
        buffer.writeln();
        buffer.writeln();
      }
    }

    final subChapters = chapter.SubChapters ?? const <EpubChapter>[];
    for (final sub in subChapters) {
      _appendChapter(buffer, sub);
    }
  }

  String _htmlToPlainText(String html) {
    final withNewlines = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</h\d\s*>', caseSensitive: false), '\n\n');

    final document = html_parser.parse(withNewlines);
    document.querySelectorAll('script,style').forEach((e) => e.remove());

    var text = (document.body?.text ?? document.documentElement?.text ?? '');
    text = text.replaceAll('\u00A0', ' ');
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}

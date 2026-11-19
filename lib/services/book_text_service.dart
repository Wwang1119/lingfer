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
import 'imported_file_store.dart';

class BookReadException implements Exception {
  const BookReadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BookTextService {
  Future<String> readBookText(Book book) async {
    try {
      final String text;
      switch (book.source) {
        case BookSource.localFile:
          text = await _readFromFile(book.locator);
        case BookSource.asset:
          text = await _readFromAsset(book.locator);
        case BookSource.mock:
          throw const BookReadException('这条旧版示例记录没有正文，请返回主页选择内置公版书，或导入完整资料。');
      }
      if (text.trim().isEmpty) {
        throw const BookReadException('这份资料没有可读取的正文。请重新导入完整文件；图片或扫描件可用截图阅读。');
      }
      return text;
    } on BookReadException {
      rethrow;
    } on FileSystemException {
      throw const BookReadException('这份资料的文件已不可访问，请返回主页重新导入。资料记录和阅读进度会保留。');
    } on FormatException {
      throw const BookReadException(
        '这份资料未能解析，请确认文件完整，或重新导入 TXT、EPUB、PDF、DOCX。',
      );
    }
  }

  Future<String> _readFromFile(String path) async {
    final readablePath = await ImportedFileStore.resolveReadablePath(path);
    if (!await File(readablePath).exists()) {
      throw const BookReadException('找不到这份资料的原文件，请返回主页重新导入。原记录和阅读进度会保留。');
    }
    final bytes = await File(readablePath).readAsBytes();
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
    // EPUB 3 can have a valid spine without an NCX chapter map. Read the
    // package's ordered spine first, rather than treating empty Chapters as
    // proof that the book is empty or returning only its title and author.
    final spineText = _readEpubSpine(bytes);
    if (spineText.trim().isNotEmpty) return spineText;
    final EpubBook book;
    try {
      book = await EpubReader.readBook(bytes);
    } catch (_) {
      throw const BookReadException('这份 EPUB 未能读取，请确认文件完整，或重新导入文字版资料。');
    }
    final buffer = StringBuffer();

    final chapters = book.Chapters ?? const <EpubChapter>[];
    for (final chapter in chapters) {
      _appendChapter(buffer, chapter);
    }

    final result = buffer.toString().trimRight();
    if (result.isEmpty) {
      throw const BookReadException('这本 EPUB 没有可提取的正文，可能是图片书或文件不完整。请换一份文字版资料。');
    }
    return result;
  }

  String _readEpubSpine(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = {
        for (final file in archive)
          if (file.isFile) file.name: file,
      };
      String? read(String path) {
        final file = files[path];
        if (file == null) return null;
        return utf8.decode(file.content as List<int>, allowMalformed: true);
      }

      final container = read('META-INF/container.xml');
      if (container == null) return '';
      final rootfiles = xml.XmlDocument.parse(
        container,
      ).descendantElements.where((element) => element.name.local == 'rootfile');
      final packagePath = rootfiles.firstOrNull?.getAttribute('full-path');
      if (packagePath == null) return '';
      final package = read(packagePath);
      if (package == null) return '';
      final document = xml.XmlDocument.parse(package);
      final manifest = <String, xml.XmlElement>{
        for (final element in document.descendantElements)
          if (element.name.local == 'item' &&
              element.getAttribute('id') != null)
            element.getAttribute('id')!: element,
      };
      final buffer = StringBuffer();
      final seen = <String>{};
      for (final reference in document.descendantElements.where(
        (element) => element.name.local == 'itemref',
      )) {
        final item = manifest[reference.getAttribute('idref')];
        if (item == null) continue;
        final href = item.getAttribute('href');
        if (href == null ||
            (item.getAttribute('properties') ?? '').split(' ').contains('nav')) {
          continue;
        }
        final path = Uri.decodeComponent(
          Uri.parse(packagePath).resolve(href).path,
        );
        if (!seen.add(path)) continue;
        final html = read(path);
        if (html == null ||
            !(item.getAttribute('media-type') ?? '').contains('html')) {
          continue;
        }
        final text = _htmlToPlainText(html);
        if (text.isNotEmpty) {
          buffer.writeln(text);
          buffer.writeln();
        }
      }
      return buffer.toString().trimRight();
    } catch (_) {
      // Existing NCX/chapter extraction remains available for older variants.
      return '';
    }
  }

  Future<String> _readDocx(List<int> bytes) async {
    // Use a robust parser: docx_to_text can stop early on some malformed nodes.
    // We parse document.xml ourselves and keep going even if a paragraph fails.
    return await runZoned(
      () async {
        final text = _docxToTextSafely(Uint8List.fromList(bytes));
        return text;
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
      final matches = RegExp(
        r'<w:t[^>]*>([\s\S]*?)</w:t>',
        multiLine: true,
      ).allMatches(xmlText);
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
    final html = (chapter.HtmlContent ?? '').trim();
    if (html.isNotEmpty) {
      final text = _htmlToPlainText(html);
      if (text.isNotEmpty) {
        if (title.isNotEmpty && !text.startsWith(title)) {
          buffer.writeln(title);
          buffer.writeln();
        }
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

// ส่งออกรายงานการเข้าเรียนเป็น PDF / Excel (.xlsx) / Word (.docx)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show PdfGoogleFonts;
import 'package:share_plus/share_plus.dart';

const _headers = ['ลำดับ', 'รหัส', 'ชื่อ-สกุล', 'สถานะ', 'เวลา'];

/// kind: 'pdf' | 'xlsx' | 'docx'
Future<void> exportReport({
  required String kind,
  required String className,
  required String sessionLabel,
  required List<List<String>> rows,
  required int onTime,
  required int lateCount,
  required int absentCount,
}) async {
  final n = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  final stamp = '${n.year}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}';
  final summary = 'ตรงเวลา $onTime คน   สาย $lateCount คน   ขาด $absentCount คน';

  switch (kind) {
    case 'pdf':
      final bytes = await _buildPdf(className, sessionLabel, summary, rows);
      await _share('attendance_$stamp.pdf', bytes, 'application/pdf');
      break;
    case 'xlsx':
      final bytes = _buildXlsx(className, sessionLabel, summary, rows);
      await _share('attendance_$stamp.xlsx', bytes,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      break;
    case 'docx':
      final bytes = _buildDocx(className, sessionLabel, summary, rows);
      await _share('attendance_$stamp.docx', bytes,
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      break;
    default:
      throw 'ไม่รู้จักรูปแบบไฟล์: $kind';
  }
}

Future<void> _share(String name, Uint8List bytes, String mime) async {
  final XFile file;
  if (kIsWeb) {
    file = XFile.fromData(bytes, name: name, mimeType: mime);
  } else {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    file = XFile(f.path, mimeType: mime, name: name);
  }
  await SharePlus.instance.share(ShareParams(files: [file], subject: name));
}

// ---------------- PDF ----------------
Future<Uint8List> _buildPdf(
    String className, String sessionLabel, String summary, List<List<String>> rows) async {
  // ฟอนต์ไทยโหลดจาก Google Fonts ตอนส่งออก (ต้องต่ออินเทอร์เน็ต)
  final reg = await PdfGoogleFonts.sarabunRegular();
  final bold = await PdfGoogleFonts.sarabunBold();
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      pw.Text('รายงานการเข้าเรียน', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.Text('วิชา: $className', style: const pw.TextStyle(fontSize: 13)),
      pw.Text('คาบเรียน: $sessionLabel', style: const pw.TextStyle(fontSize: 13)),
      pw.Text(summary, style: const pw.TextStyle(fontSize: 13)),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: _headers,
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
        cellStyle: const pw.TextStyle(fontSize: 11),
        cellAlignments: {
          0: pw.Alignment.center,
          3: pw.Alignment.center,
          4: pw.Alignment.center,
        },
        columnWidths: {
          0: const pw.FixedColumnWidth(40),
          1: const pw.FixedColumnWidth(80),
          2: const pw.FlexColumnWidth(),
          3: const pw.FixedColumnWidth(60),
          4: const pw.FixedColumnWidth(70),
        },
      ),
    ],
  ));
  return doc.save();
}

// ---------------- Excel ----------------
Uint8List _buildXlsx(String className, String sessionLabel, String summary, List<List<String>> rows) {
  xl.CellValue t(String s) => xl.TextCellValue(s);
  final ex = xl.Excel.createExcel();
  ex.rename('Sheet1', 'Report');
  final sh = ex['Report'];
  sh.appendRow(<xl.CellValue?>[t('รายงานการเข้าเรียน')]);
  sh.appendRow(<xl.CellValue?>[t('วิชา'), t(className)]);
  sh.appendRow(<xl.CellValue?>[t('คาบเรียน'), t(sessionLabel)]);
  sh.appendRow(<xl.CellValue?>[t('สรุป'), t(summary)]);
  sh.appendRow(<xl.CellValue?>[for (final h in _headers) t(h)]);
  for (final r in rows) {
    sh.appendRow(<xl.CellValue?>[for (final c in r) t(c)]);
  }
  sh.setColumnWidth(1, 16.0);
  sh.setColumnWidth(2, 32.0);
  sh.setColumnWidth(4, 14.0);
  final out = ex.encode();
  if (out == null) throw 'สร้างไฟล์ Excel ไม่สำเร็จ';
  return Uint8List.fromList(out);
}

// ---------------- Word (.docx สร้างเอง ไม่ใช้แพ็กเกจเสริม) ----------------
String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _para(String text, {bool bold = false, int size = 24, String? color}) =>
    '<w:p><w:r><w:rPr><w:rFonts w:ascii="Tahoma" w:hAnsi="Tahoma" w:cs="Tahoma"/>'
    '${bold ? '<w:b/><w:bCs/>' : ''}'
    '${color != null ? '<w:color w:val="$color"/>' : ''}'
    '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>'
    '<w:t xml:space="preserve">${_x(text)}</w:t></w:r></w:p>';

String _cell(String text, int width, {bool header = false}) =>
    '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>'
    '${header ? '<w:shd w:val="clear" w:color="auto" w:fill="2E55C9"/>' : ''}</w:tcPr>'
    '${_para(text, bold: header, size: 22, color: header ? 'FFFFFF' : null)}</w:tc>';

Uint8List _buildDocx(String className, String sessionLabel, String summary, List<List<String>> rows) {
  const widths = [900, 1800, 3600, 1500, 1838]; // รวม 9638 = กว้างของ A4 หักขอบ
  const border = 'w:val="single" w:sz="4" w:space="0" w:color="BBBBBB"';
  final tbl = StringBuffer()
    ..write('<w:tbl><w:tblPr><w:tblW w:w="9638" w:type="dxa"/><w:tblBorders>'
        '<w:top $border/><w:left $border/><w:bottom $border/><w:right $border/>'
        '<w:insideH $border/><w:insideV $border/></w:tblBorders></w:tblPr><w:tblGrid>');
  for (final w in widths) {
    tbl.write('<w:gridCol w:w="$w"/>');
  }
  tbl.write('</w:tblGrid><w:tr>');
  for (var i = 0; i < _headers.length; i++) {
    tbl.write(_cell(_headers[i], widths[i], header: true));
  }
  tbl.write('</w:tr>');
  for (final r in rows) {
    tbl.write('<w:tr>');
    for (var i = 0; i < widths.length; i++) {
      tbl.write(_cell(i < r.length ? r[i] : '', widths[i]));
    }
    tbl.write('</w:tr>');
  }
  tbl.write('</w:tbl><w:p/>');

  final body = StringBuffer()
    ..write(_para('รายงานการเข้าเรียน', bold: true, size: 36))
    ..write(_para('วิชา: $className'))
    ..write(_para('คาบเรียน: $sessionLabel'))
    ..write(_para(summary))
    ..write(_para(''))
    ..write(tbl)
    ..write('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
        'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>');

  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  final files = <String, String>{
    '[Content_Types].xml': '$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    '_rels/.rels': '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/></Relationships>',
    'word/document.xml': '$head<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body</w:body></w:document>',
  };
  return _zip(files);
}

// zip แบบไม่บีบอัด (stored) เขียนเอง เพื่อไม่ต้องพึ่งแพ็กเกจ archive
final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _zip(Map<String, String> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  var count = 0;
  files.forEach((name, text) {
    final nameB = utf8.encode(name);
    final data = utf8.encode(text);
    final crc = _crc32(data);
    final offset = out.length;
    // local file header
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0x21);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, nameB.length);
    u16(out, 0);
    out.add(nameB);
    out.add(data);
    // central directory header
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0x21);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, nameB.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(nameB);
    count++;
  });
  final cdOffset = out.length;
  final cd = central.toBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, count);
  u16(out, count);
  u32(out, cd.length);
  u32(out, cdOffset);
  u16(out, 0);
  return out.toBytes();
}
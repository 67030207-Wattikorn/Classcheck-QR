// helpers.dart — ฟังก์ชันช่วยทั่วไป (toast, วันที่, GPS, กล่องถามข้อความ, ยืนยันออกจากระบบ)
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'config.dart';

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));

String p2(int n) => n.toString().padLeft(2, '0');
String fmt(DateTime? d) =>
    d == null ? '-' : '${p2(d.day)}/${p2(d.month)}/${d.year + 543} ${p2(d.hour)}:${p2(d.minute)}';
String fmtTime(DateTime? d) => d == null ? '-' : '${p2(d.hour)}:${p2(d.minute)} น.';

String genCode() {
  const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random();
  return List.generate(6, (_) => ch[r.nextInt(ch.length)]).join();
}

String genToken() {
  const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(10, (_) => ch[r.nextInt(ch.length)]).join();
}

Future<Position> getPos() async {
  if (!await Geolocator.isLocationServiceEnabled()) throw 'กรุณาเปิด GPS';
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
    throw 'ไม่ได้รับสิทธิ์เข้าถึงตำแหน่ง';
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
  );
}

// แปลงตัวอักษรที่พิมพ์เป็นตัวพิมพ์ใหญ่ทันที
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

Future<List<String>?> askText(BuildContext c, String title, List<String> labels,
    {bool upper = false}) {
  final ctrls = labels.map((_) => TextEditingController()).toList();
  return showDialog<List<String>>(
    context: c,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              controller: ctrls[i],
              textCapitalization:
                  upper ? TextCapitalization.characters : TextCapitalization.none,
              inputFormatters: upper ? [UpperCaseTextFormatter()] : null,
              decoration: InputDecoration(labelText: labels[i]),
            ),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('ยกเลิก')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(c, ctrls.map((e) => e.text.trim()).toList()),
          child: const Text('ตกลง'),
        ),
      ],
    ),
  );
}

// ถามยืนยันก่อนออกจากระบบ
Future<void> confirmSignOut(BuildContext c) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('ออกจากระบบ?', style: TextStyle(fontWeight: FontWeight.w600)),
      content: const Text('คุณต้องการออกจากระบบใช่หรือไม่', style: TextStyle(color: kMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ยกเลิก')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kAbsent, minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('ออกจากระบบ'),
        ),
      ],
    ),
  );
  if (ok == true) await auth.signOut();
}

Color statusColor(String s) =>
    s == 'ตรงเวลา' ? kOk : (s == 'สาย' ? kLate : (s == 'ขาด' ? kAbsent : kMuted));
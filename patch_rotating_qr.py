# -*- coding: utf-8 -*-
# Patch lib/main.dart: rotating QR token + smaller radius + mock-GPS check.
# Usage (run inside the classcheck_qr folder):  python3 patch_rotating_qr.py
import re
import shutil
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "lib/main.dart"
src = open(path, encoding="utf-8").read()

if "RotatingQr" in src:
    sys.exit("This file already looks patched (RotatingQr found). Nothing changed.")


def rep(old, new, label):
    global src
    n = src.count(old)
    if n != 1:
        sys.exit("ERROR at step '%s': anchor found %d times (expected 1). File NOT changed." % (label, n))
    src = src.replace(old, new)


# 1) imports
rep("import 'dart:math';", "import 'dart:async';\nimport 'dart:math';", "import dart:async")

# 2) radius 1000 m -> 100 m
src, n = re.subn(
    r"const kRadiusMeters = [0-9.]+;[^\n]*",
    "const kRadiusMeters = 100.0; // รัศมีเช็คชื่อ (เมตร) ปรับได้ตามขนาดตึก",
    src,
)
if n != 1:
    sys.exit("ERROR at step 'radius': found %d matches (expected 1). File NOT changed." % n)

# 3) refresh constant
rep(
    "const kLateMinutes = 15;",
    "const kQrRefreshSeconds = 20; // QR เปลี่ยนรหัสทุกกี่วินาที\nconst kLateMinutes = 15;",
    "refresh constant",
)

# 4) token generator
rep(
    "Future<Position> getPos() async {",
    r'''String genToken() {
  const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(10, (_) => ch[r.nextInt(ch.length)]).join();
}

Future<Position> getPos() async {''',
    "genToken",
)

# 5) high-accuracy GPS
rep(
    "return Geolocator.getCurrentPosition();",
    r'''return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
  );''',
    "high accuracy gps",
)

# 6) teacher QR uses the rotating widget
rep(
    "child: QrImageView(",
    "child: RotatingQr(classId: classId, sessionRef: sess.reference, builder: (qrData) => QrImageView(",
    "QR wrapper open",
)
rep("data: 'cc|$classId|${sess.id}',", "data: qrData,", "QR data")
rep(
    "dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: kInk),",
    "dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: kInk),\n                )",
    "QR wrapper close",
)

# 7) caption text
rep(
    "'ต้องอยู่ในรัศมีที่กำหนดจึงจะสแกนผ่าน'",
    "'QR เปลี่ยนใหม่ทุก 20 วินาที และต้องอยู่ในห้องจึงจะสแกนผ่าน'",
    "caption",
)

# 8) RotatingQr widget
rep(
    "class ReportTab extends StatefulWidget {",
    r'''// QR ที่เปลี่ยนรหัสทุก kQrRefreshSeconds วินาที (กันการถ่ายรูป QR ส่งให้เพื่อนต่างห้อง)
class RotatingQr extends StatefulWidget {
  final String classId;
  final DocumentReference<Map<String, dynamic>> sessionRef;
  final Widget Function(String data) builder;
  const RotatingQr({super.key, required this.classId, required this.sessionRef, required this.builder});
  @override
  State<RotatingQr> createState() => _RotatingQrState();
}

class _RotatingQrState extends State<RotatingQr> {
  late String token;
  String prev = '';
  Timer? timer;

  @override
  void initState() {
    super.initState();
    token = genToken();
    push();
    timer = Timer.periodic(const Duration(seconds: kQrRefreshSeconds), (_) {
      prev = token;
      setState(() => token = genToken());
      push();
    });
  }

  void push() => widget.sessionRef.update({'token': token, 'prevToken': prev}).catchError((_) {});

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder('cc|${widget.classId}|${widget.sessionRef.id}|$token');
}

class ReportTab extends StatefulWidget {''',
    "RotatingQr class",
)

# 9) student scan checks
rep(
    "if (parts.length != 3 || parts[0] != 'cc')",
    "if (parts.length != 4 || parts[0] != 'cc')",
    "4-part QR",
)
rep(
    "final stu = await db.doc('classes/$cid/students/$uid').get();",
    r'''final sd = s.data()!;
      final tok = parts[3];
      if (tok != sd['token'] && tok != sd['prevToken']) throw 'QR หมดอายุแล้ว ให้สแกนใหม่จากหน้าจอของอาจารย์';
      final stu = await db.doc('classes/$cid/students/$uid').get();''',
    "token check",
)
rep(
    "final dist = Geolocator.distanceBetween(p.latitude, p.longitude, s['lat'], s['lng']);",
    r'''if (p.isMocked) throw 'ตรวจพบการปลอมตำแหน่ง GPS';
      final dist = Geolocator.distanceBetween(p.latitude, p.longitude, s['lat'], s['lng']);''',
    "mock gps check",
)

shutil.copy(path, path + ".bak")
open(path, "w", encoding="utf-8").write(src)
print("OK: patched %s (backup saved as %s.bak)" % (path, path))
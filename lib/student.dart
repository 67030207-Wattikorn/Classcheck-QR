// student.dart — ฝั่งนักศึกษา: หน้าชั้นเรียน/ประวัติเข้าเรียน และหน้าสแกน QR
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'config.dart';
import 'features.dart';
import 'helpers.dart';
import 'home.dart';
import 'widgets.dart';

// ---------- student ----------
class StudentClass extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data, user;
  const StudentClass({super.key, required this.id, required this.data, required this.user});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(data['name']),
          actions: [LeaveClassButton(classId: id, className: '${data['name']}')],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScanPage(user: user))),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('สแกนเช็คชื่อ'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('classes/$id/sessions').orderBy('startedAt', descending: true).snapshots(),
          builder: (c, s) {
            if (!s.hasData) return const Loading();
            if (s.data!.docs.isEmpty) {
              return const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'ยังไม่มีการเช็คชื่อ',
                  hint: 'เมื่อครูเปิดเช็คชื่อ กด "สแกนเช็คชื่อ" แล้วสแกน QR บนจอ');
            }
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              LiveBanner(sessions: s.data!.docs, user: user),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text('ประวัติการเข้าเรียน', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              for (final d in s.data!.docs)
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: d.reference.collection('records').doc(auth.currentUser!.uid).get(),
                  builder: (c, r) {
                    final status = r.hasData
                        ? (r.data!.exists ? r.data!['status'] : (d['open'] == true && !sessionExpired(d.data()) ? 'ยังไม่เช็ค' : 'ขาด'))
                        : '...';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kLine)),
                      child: Row(children: [
                        const Icon(Icons.event_note_outlined, color: kMuted),
                        const SizedBox(width: 12),
                        Expanded(child: Text(fmt((d['startedAt'] as Timestamp?)?.toDate()))),
                        StatusChip(status),
                      ]),
                    );
                  },
                ),
            ]);
          },
        ),
      );
}

class ScanPage extends StatefulWidget {
  final Map<String, dynamic> user;
  const ScanPage({super.key, required this.user});
  @override
  State<ScanPage> createState() => _ScanState();
}

class _ScanState extends State<ScanPage> {
  bool busy = false;

  Future<void> onCode(String raw) async {
    if (busy) return;
    busy = true;
    try {
      final parts = raw.split('|');
      if (parts.length != 4 || parts[0] != 'cc') throw 'QR ไม่ถูกต้อง';
      final cid = parts[1], sid = parts[2], uid = auth.currentUser!.uid;
      final s = await db.doc('classes/$cid/sessions/$sid').get();
      if (!s.exists || s['open'] != true) throw 'การเช็คชื่อนี้ปิดแล้ว';
      final sd = s.data()!;
      if (sessionExpired(sd)) throw 'QR หมดเวลาแล้ว';
      final tok = parts[3];
      if (tok != sd['token'] && tok != sd['prevToken']) throw 'QR หมดอายุแล้ว ให้สแกนใหม่จากหน้าจอของอาจารย์';
      final stu = await db.doc('classes/$cid/students/$uid').get();
      if (!stu.exists) throw 'คุณไม่ได้อยู่ในชั้นเรียนนี้';
      var dist = 0.0;
      if (sd['gps'] != false) {
        final p = await getPos();
        if (p.isMocked) throw 'ตรวจพบการปลอมตำแหน่ง GPS';
        dist = Geolocator.distanceBetween(p.latitude, p.longitude, s['lat'], s['lng']);
        if (dist > (s['radius'] as num)) {
          throw 'อยู่นอกรัศมี (ห่าง ${dist.round()} เมตร)'
              '${dist > 1000 ? '\nตำแหน่งห้องของอาจารย์อาจคลาดเคลื่อน (เปิดจากคอม?) ให้อาจารย์เปิดเช็คชื่อจากมือถือ หรือปิดตรวจตำแหน่ง' : ''}';
        }
      }
      final started = (s['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final isLate = DateTime.now().difference(started).inMinutes > (s['lateMin'] as num);
      await db.doc('classes/$cid/sessions/$sid/records/$uid').set({
        'name': widget.user['name'],
        'studentId': widget.user['studentId'],
        'status': isLate ? 'สาย' : 'ตรงเวลา',
        'time': FieldValue.serverTimestamp(),
        'distance': dist.round(),
      });
      if (mounted) {
        toast(context, 'เช็คชื่อสำเร็จ (${isLate ? 'สาย' : 'ตรงเวลา'})');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
      await Future.delayed(const Duration(seconds: 2));
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('สแกน QR เพื่อเช็คชื่อ', style: TextStyle(color: Colors.white)),
        ),
        body: Stack(fit: StackFit.expand, children: [
          MobileScanner(onDetect: (cap) {
            final v = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
            if (v != null) onCode(v);
          }),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(32)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration:
                    BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
                child: const Text('จ่อกล้องไปที่ QR บนจอของอาจารย์', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ]),
      );
}
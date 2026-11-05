// teacher.dart — ฝั่งครู: หน้าชั้นเรียน (แท็บต่าง ๆ), แท็บเช็คชื่อ, QR ที่หมุนรหัส
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'config.dart';
import 'features.dart';
import 'helpers.dart';
import 'report.dart';
import 'widgets.dart';

// ---------- teacher ----------
class TeacherClass extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  const TeacherClass({super.key, required this.id, required this.data});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Text(data['name']),
            actions: [DeleteClassButton(classId: id, className: '${data['name']}')],
            bottom: const TabBar(
              labelColor: kBlueDeep,
              unselectedLabelColor: kMuted,
              indicatorColor: kBlue,
              dividerColor: kLine,
              tabs: [Tab(text: 'เช็คชื่อ'), Tab(text: 'รายงาน'), Tab(text: 'AI สรุป'), Tab(text: 'สมาชิก')],
            ),
          ),
          body: TabBarView(children: [
            CheckTab(classId: id, code: data['code']),
            ReportTab(classId: id),
            AiSummaryTab(classId: id, data: data),
            MembersTab(classId: id, code: '${data['code']}'),
          ]),
        ),
      );
}

class CheckTab extends StatelessWidget {
  final String classId, code;
  const CheckTab({super.key, required this.classId, required this.code});

  Future<void> openSession(BuildContext c) async {
    try {
      final p = await getPos();
      await db.collection('classes/$classId/sessions').add({
        'open': true,
        'startedAt': FieldValue.serverTimestamp(),
        'lat': p.latitude,
        'lng': p.longitude,
        'radius': kRadiusMeters,
        'lateMin': kLateMinutes,
      });
    } catch (e) {
      if (c.mounted) toast(c, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('classes/$classId/sessions').where('open', isEqualTo: true).snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const Loading();
          if (s.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('รหัสเข้าร่วมห้อง', style: TextStyle(color: kMuted)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      toast(context, 'คัดลอกรหัสห้องแล้ว');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(code,
                            style: const TextStyle(
                                fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 4, color: kBlueDeep)),
                        const SizedBox(width: 10),
                        const Icon(Icons.copy_rounded, size: 18, color: kMuted),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('แตะเพื่อคัดลอก แล้วส่งให้นักศึกษา', style: TextStyle(color: kMuted, fontSize: 13)),
                  const SizedBox(height: 36),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => SessionSetupPage(classId: classId))),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('เปิดเช็คชื่อ'),
                  ),
                ]),
              ),
            );
          }
          final sess = s.data!.docs.first;
          // หน้าจอ QR: เต็มจอสีน้ำเงิน ตั๋ว QR สีขาวอยู่กลาง
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kBlue, kBlueDeep]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('ให้นักศึกษาสแกน QR นี้',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('QR เปลี่ยนใหม่ทุก 20 วินาที และต้องอยู่ในห้องจึงจะสแกนผ่าน', style: TextStyle(color: Colors.white70, fontSize: 13)),
              SessionTimer(sess: sess),
              // สวิตช์ตรวจตำแหน่ง: ปิดได้เมื่ออาจารย์เปิดจากคอม (ตำแหน่งคอมไม่แม่น)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Container(
                  padding: const EdgeInsets.only(left: 14, right: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.location_on_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          sess.data()['gps'] == false ? 'ปิดตรวจตำแหน่ง (ไม่เช็คระยะ)' : 'ตรวจตำแหน่ง GPS',
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                    Switch(
                      value: sess.data()['gps'] != false,
                      activeThumbColor: Colors.white,
                      activeTrackColor: kOk,
                      onChanged: (v) => sess.reference.update({'gps': v}),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: kInk.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12))
                  ],
                ),
                child: RotatingQr(classId: classId, sessionRef: sess.reference, builder: (qrData) => QrImageView(
                  data: qrData,
                  size: 240,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: kInk),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: kInk),
                )
                ),
              ),
              const SizedBox(height: 24),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: sess.reference.collection('records').snapshots(),
                builder: (c, r) => Column(children: [
                  Text('${r.data?.docs.length ?? 0}',
                      style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700, height: 1)),
                  const Text('คนเช็คชื่อแล้ว', style: TextStyle(color: Colors.white70)),
                ]),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => sess.reference.update({'open': false}),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('ปิดการเช็คชื่อ'),
              ),
            ]),
          );
        },
      );
}

// QR ที่เปลี่ยนรหัสทุก kQrRefreshSeconds วินาที (กันการถ่ายรูป QR ส่งให้เพื่อนต่างห้อง)
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
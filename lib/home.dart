// home.dart — หน้าแรก (รายการชั้นเรียน), การ์ดชั้นเรียน, แจ้งเตือนสถานะห้อง
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'config.dart';
import 'features.dart';
import 'helpers.dart';
import 'student.dart';
import 'teacher.dart';
import 'widgets.dart';

// ---------- home ----------
class Home extends StatelessWidget {
  final Map<String, dynamic> user;
  const Home({super.key, required this.user});
  bool get isT => user['role'] == 'teacher';

  Future<void> createClass(BuildContext c) async {
    final v = await askText(c, 'สร้างชั้นเรียน', ['ชื่อวิชา', 'รหัสวิชา']);
    if (v == null || v[0].isEmpty) return;
    await db.collection('classes').add({
      'name': v[0],
      'subjectCode': v[1],
      'code': genCode(),
      'teacherId': auth.currentUser!.uid,
      'members': [],
    });
  }

  Future<void> joinClass(BuildContext c) async {
    final v = await askText(c, 'เข้าร่วมชั้นเรียน', ['รหัสห้อง 6 ตัว'], upper: true);
    if (v == null || v[0].isEmpty) return;
    final q = await db.collection('classes').where('code', isEqualTo: v[0].toUpperCase()).limit(1).get();
    if (q.docs.isEmpty) {
      if (c.mounted) toast(c, 'ไม่พบรหัสห้องนี้ ตรวจสอบรหัสกับอาจารย์อีกครั้ง');
      return;
    }
    final uid = auth.currentUser!.uid;
    final ref = q.docs.first.reference;
    await ref.update({'members': FieldValue.arrayUnion([uid])});
    await ref.collection('students').doc(uid).set({'name': user['name'], 'studentId': user['studentId']});
    if (c.mounted) toast(c, 'เข้าร่วมชั้นเรียนแล้ว');
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;
    final q = isT
        ? db.collection('classes').where('teacherId', isEqualTo: uid)
        : db.collection('classes').where('members', arrayContains: uid);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => isT ? createClass(context) : joinClass(context),
        icon: Icon(isT ? Icons.add_rounded : Icons.login_rounded),
        label: Text(isT ? 'สร้างชั้นเรียน' : 'เข้าร่วมชั้นเรียน'),
      ),
      body: Column(children: [
        Header(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('สวัสดี', style: TextStyle(color: Colors.white70, fontSize: 14)),
                Text('${user['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text(isT ? 'ครู / อาจารย์' : 'นักเรียน / นักศึกษา',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
            IconButton(
                tooltip: 'ออกจากระบบ',
                onPressed: () => confirmSignOut(context),
                icon: const Icon(Icons.logout_rounded, color: Colors.white)),
          ]),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (c, s) {
              if (!s.hasData) return const Loading();
              final docs = s.data!.docs;
              if (docs.isEmpty) {
                return EmptyState(
                  icon: Icons.class_outlined,
                  title: 'ยังไม่มีชั้นเรียน',
                  hint: isT ? 'กด "สร้างชั้นเรียน" แล้วแจกรหัสห้องให้นักศึกษา' : 'กด "เข้าร่วมชั้นเรียน" แล้วใส่รหัสห้องจากอาจารย์',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (c, i) {
                  return ClassCard(doc: docs[i], user: user, isT: isT);
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------- การแจ้งเตือนสถานะห้องเรียน ----------
// ป้ายเล็ก "เปิดเช็คชื่ออยู่"
class LivePill extends StatelessWidget {
  const LivePill({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: kOk.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: kOk, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          const Text('เปิดเช็คชื่ออยู่',
              style: TextStyle(color: kOk, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

// การ์ดชั้นเรียนในหน้าแรก: ฟังสถานะห้องแบบเรียลไทม์
// ถ้าครูเปิดเช็คชื่อขณะนักศึกษาเปิดแอปอยู่ จะเด้งแจ้งเตือนพร้อมปุ่ม "สแกนเลย"
class ClassCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic> user;
  final bool isT;
  const ClassCard({super.key, required this.doc, required this.user, required this.isT});
  @override
  State<ClassCard> createState() => _ClassCardState();
}

class _ClassCardState extends State<ClassCard> {
  StreamSubscription? sub;
  bool open = false, first = true;

  @override
  void initState() {
    super.initState();
    sub = widget.doc.reference
        .collection('sessions')
        .where('open', isEqualTo: true)
        .snapshots()
        .listen((s) {
      final now = s.docs.any((e) => !sessionExpired(e.data()));
      if (!first && now && !open && !widget.isT && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${widget.doc['name']} เปิดเช็คชื่อแล้ว'),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            backgroundColor: kInk,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            action: SnackBarAction(
              label: 'สแกนเลย',
              textColor: const Color(0xFF9DB8FF),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ScanPage(user: widget.user))),
            ),
          ));
      }
      first = false;
      if (mounted && now != open) setState(() => open = now);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final isT = widget.isT;
    final tile = kTiles[d.id.hashCode.abs() % kTiles.length];
    final members = (d['members'] as List).length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => isT
                    ? TeacherClass(id: d.id, data: d.data())
                    : StudentClass(id: d.id, data: d.data(), user: widget.user))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: open ? kOk.withValues(alpha: 0.6) : kLine, width: open ? 1.5 : 1)),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: tile.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.menu_book_rounded, color: tile),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(isT ? '${d['subjectCode']}  •  $members คน' : '${d['subjectCode']}',
                    style: const TextStyle(color: kMuted, fontSize: 13)),
                if (open) ...[const SizedBox(height: 6), const LivePill()],
              ]),
            ),
            if (isT)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: kPaper, borderRadius: BorderRadius.circular(10)),
                child: Text('${d['code']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, letterSpacing: 1.5, color: kBlueDeep)),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: kMuted),
          ]),
        ),
      ),
    );
  }
}

// แบนเนอร์ในหน้าชั้นเรียนของนักศึกษา: แจ้งว่าครูเปิดเช็คชื่ออยู่ / เช็คชื่อแล้ว
class LiveBanner extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions;
  final Map<String, dynamic> user;
  const LiveBanner({super.key, required this.sessions, required this.user});
  @override
  Widget build(BuildContext context) {
    final live = sessions.where((d) => d['open'] == true && !sessionExpired(d.data())).toList();
    if (live.isEmpty) return const SizedBox();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: live.first.reference.collection('records').doc(auth.currentUser!.uid).snapshots(),
      builder: (c, r) {
        if (!r.hasData) return const SizedBox();
        final done = r.data!.exists;
        final col = done ? kOk : kBlue;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: col.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.notifications_active_rounded, color: col, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(done ? 'เช็คชื่อแล้ว' : 'ครูเปิดเช็คชื่ออยู่',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(
                    done
                        ? 'บันทึกสถานะของคุณแล้ว (${r.data!['status']})'
                        : 'สแกน QR บนจอของอาจารย์ได้เลย',
                    style: const TextStyle(color: kMuted, fontSize: 13)),
              ]),
            ),
            if (!done)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ScanPage(user: user))),
                child: const Text('สแกน'),
              ),
          ]),
        );
      },
    );
  }
}
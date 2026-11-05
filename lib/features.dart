// ฟีเจอร์เพิ่มเติมของ ClassCheck QR (แยกไฟล์ เพื่อไม่ให้กระทบโค้ดเดิมใน main.dart)
//  - หน้าตั้งค่าก่อนเปิดเช็คชื่อ: ระยะเวลา QR / ช่วงตรงเวลา / ตำแหน่งห้อง
//  - ตัวนับเวลาถอยหลังบนหน้าจอ QR และปิดคาบอัตโนมัติเมื่อหมดเวลา
//  - แท็บ "AI สรุป" (นักศึกษาเสี่ยง + ร่างข้อความถึงอาจารย์ที่ปรึกษา) และแท็บ "สมาชิก"
//  - ปุ่มลบห้อง (อาจารย์) และปุ่มออกจากห้อง (นักศึกษา)
import 'dart:async';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

import 'main.dart';

// ---------- กติกาแจ้งเตือน (แก้ตัวเลขได้ตามนโยบายของวิชา) ----------
const kWatchAbsent = 2; // ขาดตั้งแต่ 2 ครั้ง = ควรเฝ้าระวัง
const kRiskAbsent = 4; // ขาดเกิน 3 ครั้ง (ตั้งแต่ 4 ครั้ง) = เสี่ยงหมดสิทธิ์สอบ

const _watchText = Color(0xFF8A5300);
const _riskText = Color(0xFFB4232A);

// ---------- helpers ----------
const _thMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

/// เช่น 23 ต.ค. 69
String fmtShort(DateTime? d) =>
    d == null ? '-' : '${d.day} ${_thMonths[d.month - 1]} ${p2((d.year + 543) % 100)}';

String durationText(int m) {
  if (m < 60) return '$m นาที';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h ชั่วโมง' : '$h ชม. $r นาที';
}

/// เวลาที่ QR หมดอายุ (null = คาบเก่าที่ไม่ได้ตั้งเวลาไว้ หรือเวลาเริ่มยังไม่มาจากเซิร์ฟเวอร์)
DateTime? sessionEndsAt(Map<String, dynamic> d) {
  final dur = d['durationMin'];
  final st = (d['startedAt'] as Timestamp?)?.toDate();
  if (dur is! num || st == null) return null;
  return st.add(Duration(minutes: dur.round()));
}

bool sessionExpired(Map<String, dynamic> d) {
  final end = sessionEndsAt(d);
  return end != null && !DateTime.now().isBefore(end);
}

/// คาบที่จบแล้ว = ถูกปิด หรือหมดเวลา
bool sessionEnded(Map<String, dynamic> d) => d['open'] != true || sessionExpired(d);

Future<bool> confirmDialog(
  BuildContext c, {
  required String title,
  required String message,
  required String okLabel,
}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (dCtx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('ยกเลิก')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kAbsent, minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(dCtx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return r == true;
}

Widget _sectionCard(Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
      child: child,
    );

class _Choice extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Choice({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: on ? kBlue : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: on ? kBlue : kLine, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(label,
                style: TextStyle(color: on ? Colors.white : kInk, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ),
      );
}

String _initial(String name) {
  // ข้ามสระนำหน้า (เ แ โ ใ ไ) เพื่อให้ได้พยัญชนะตัวแรก
  final r = name.runes.where((c) => c < 0xE40 || c > 0xE44);
  return r.isEmpty ? '?' : String.fromCharCode(r.first);
}

// ============================================================
//  1) หน้าตั้งค่าก่อนเปิดเช็คชื่อ
// ============================================================
class SessionSetupPage extends StatefulWidget {
  final String classId;
  const SessionSetupPage({super.key, required this.classId});
  @override
  State<SessionSetupPage> createState() => _SessionSetupState();
}

class _SessionSetupState extends State<SessionSetupPage> {
  static const presets = [10, 15, 30, 60];
  int duration = 10; // นาที
  bool custom = false;
  int onTime = 5; // นาทีแรกที่นับว่า "ตรงเวลา"
  Position? pos;
  String? posError;
  bool locating = false, opening = false;

  @override
  void initState() {
    super.initState();
    locate();
  }

  Future<void> locate() async {
    setState(() {
      locating = true;
      posError = null;
    });
    try {
      final p = await getPos();
      if (mounted) setState(() => pos = p);
    } on TimeoutException {
      if (mounted) setState(() => posError = 'หาตำแหน่งไม่ทัน กด "ใช้ตำแหน่งปัจจุบัน" เพื่อลองอีกครั้ง');
    } catch (e) {
      if (mounted) setState(() => posError = e.toString());
    }
    if (mounted) setState(() => locating = false);
  }

  Future<void> pickCustom() async {
    final ctrl = TextEditingController(text: custom ? '$duration' : '');
    String? err;
    final v = await showDialog<int>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('กำหนดเวลาเอง', style: TextStyle(fontWeight: FontWeight.w600)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'จำนวนนาที (1-600)', suffixText: 'นาที', errorText: err),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('ยกเลิก')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: () {
                final n = int.tryParse(ctrl.text.trim());
                if (n == null || n < 1 || n > 600) {
                  setS(() => err = 'ใส่ตัวเลข 1 ถึง 600');
                  return;
                }
                Navigator.pop(dCtx, n);
              },
              child: const Text('ตกลง'),
            ),
          ],
        ),
      ),
    );
    if (v != null) {
      setState(() {
        duration = v;
        custom = true;
      });
    }
  }

  Future<void> open() async {
    setState(() => opening = true);
    try {
      final Position p = pos ?? await getPos();
      await db.collection('classes/${widget.classId}/sessions').add({
        'open': true,
        'startedAt': FieldValue.serverTimestamp(),
        'lat': p.latitude,
        'lng': p.longitude,
        'radius': kRadiusMeters,
        'lateMin': min(onTime, duration), // ใช้ฟิลด์เดิมที่ ScanPage อ่านอยู่แล้ว
        'durationMin': duration, // ฟิลด์ใหม่: QR หมดอายุเมื่อครบเวลานี้
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        toast(context, e.toString());
        setState(() => opening = false);
      }
    }
  }

  String get radiusText => kRadiusMeters >= 1000
      ? '${(kRadiusMeters / 1000).toStringAsFixed(kRadiusMeters % 1000 == 0 ? 0 : 1)} กม.'
      : '${kRadiusMeters.round()} ม.';

  @override
  Widget build(BuildContext context) {
    final locText = locating
        ? 'กำลังหาตำแหน่ง...'
        : (posError ??
            (pos == null
                ? 'ยังไม่ได้ระบุตำแหน่ง'
                : 'ตำแหน่งปัจจุบัน · ${pos!.latitude.toStringAsFixed(4)}, ${pos!.longitude.toStringAsFixed(4)}'));
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าการเช็คชื่อ')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: opening ? null : open,
            icon: opening
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.qr_code_2_rounded),
            label: Text('เปิดคิวอาร์โค้ด (${durationText(duration)})'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        _sectionCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('QR ใช้งานได้นานเท่าไร', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final m in presets)
              _Choice(
                label: durationText(m),
                on: !custom && duration == m,
                onTap: () => setState(() {
                  duration = m;
                  custom = false;
                }),
              ),
            _Choice(
              label: custom ? 'กำหนดเอง (${durationText(duration)})' : 'กำหนดเอง',
              on: custom,
              onTap: pickCustom,
            ),
          ]),
        ])),
        _sectionCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('นับว่า “ตรงเวลา” ภายใน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final m in const [5, 10, 15])
              _Choice(label: '$m นาทีแรก', on: onTime == m, onTap: () => setState(() => onTime = m)),
          ]),
          const SizedBox(height: 12),
          Text(
            onTime >= duration
                ? 'เวลาของ QR สั้นกว่าหรือเท่ากับช่วงตรงเวลา ทุกคนที่สแกนทันจะนับเป็น “ตรงเวลา”'
                : 'หลังจากนั้นถึงเวลาที่ QR หมดจะเป็น “สาย” และคนที่ไม่สแกนจะถูกบันทึกเป็น “ขาด” ตอน QR หมดเวลา',
            style: const TextStyle(color: kMuted, fontSize: 13, height: 1.45),
          ),
        ])),
        _sectionCard(Column(children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: kBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.location_on_outlined, color: kBlueDeep),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ตำแหน่งห้องเรียน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(locText,
                    style: TextStyle(color: posError != null && !locating ? kAbsent : kMuted, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                      color: kOk.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: kOk, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('รัศมีเช็คชื่อ $radiusText',
                        style: const TextStyle(color: Color(0xFF0F7A52), fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: locating ? null : locate,
                  child: Text(locating ? 'กำลังหา...' : 'ใช้ตำแหน่งปัจจุบัน'),
                ),
              ],
            ),
          ),
        ])),
      ]),
    );
  }
}

// ============================================================
//  2) ตัวนับเวลาถอยหลังบนหน้าจอ QR (ปิดคาบอัตโนมัติเมื่อหมดเวลา)
// ============================================================
class SessionTimer extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>> sess;
  const SessionTimer({super.key, required this.sess});
  @override
  State<SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<SessionTimer> {
  Timer? timer;
  bool closing = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void tick() {
    if (!mounted) return;
    final end = sessionEndsAt(widget.sess.data() ?? {});
    if (end != null && !closing && !DateTime.now().isBefore(end)) {
      closing = true;
      widget.sess.reference.update({'open': false}).catchError((_) {});
    }
    setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.sess.data() ?? {};
    final end = sessionEndsAt(d);
    final start = (d['startedAt'] as Timestamp?)?.toDate();
    if (end == null || start == null) return const SizedBox.shrink();
    var rem = end.difference(DateTime.now());
    if (rem.isNegative) rem = Duration.zero;
    final clock = rem.inHours > 0
        ? '${rem.inHours}:${p2(rem.inMinutes % 60)}:${p2(rem.inSeconds % 60)}'
        : '${p2(rem.inMinutes)}:${p2(rem.inSeconds % 60)}';
    final lateMin = (d['lateMin'] as num?) ?? 0;
    final isLate = DateTime.now().difference(start).inMinutes >= lateMin;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(rem == Duration.zero ? 'หมดเวลาแล้ว' : 'เหลือเวลา $clock',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          if (rem != Duration.zero) ...[
            const SizedBox(width: 10),
            Text(isLate ? 'ตอนนี้นับ: สาย' : 'ตอนนี้นับ: ตรงเวลา',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ],
        ]),
      ),
    );
  }
}

// ============================================================
//  3) แท็บ "AI สรุป"
// ============================================================
class _Stat {
  final String uid, name, studentId;
  int absent = 0, lateN = 0;
  DateTime? lastAbsent;
  _Stat(this.uid, this.name, this.studentId);
  int get level => absent >= kRiskAbsent ? 2 : (absent >= kWatchAbsent ? 1 : 0);
}

class _AiResult {
  final int total; // จำนวนคาบที่จบแล้ว
  final List<_Stat> risky;
  _AiResult(this.total, this.risky);
  int get riskN => risky.where((s) => s.level == 2).length;
  int get watchN => risky.where((s) => s.level == 1).length;
}

class AiSummaryTab extends StatefulWidget {
  final String classId;
  final Map<String, dynamic> data;
  const AiSummaryTab({super.key, required this.classId, required this.data});
  @override
  State<AiSummaryTab> createState() => _AiSummaryState();
}

class _AiSummaryState extends State<AiSummaryTab> with AutomaticKeepAliveClientMixin {
  late Future<_AiResult> future = _load();

  @override
  bool get wantKeepAlive => true;

  Future<_AiResult> _load() async {
    final base = db.doc('classes/${widget.classId}');
    final sessionsSnap = await base.collection('sessions').get();
    final studentsSnap = await base.collection('students').get();
    final ended = sessionsSnap.docs.where((s) => sessionEnded(s.data())).toList();
    final recSnaps = await Future.wait(ended.map((s) => s.reference.collection('records').get()));
    final stats = <String, _Stat>{
      for (final s in studentsSnap.docs)
        s.id: _Stat(s.id, '${s.data()['name'] ?? ''}', '${s.data()['studentId'] ?? ''}'),
    };
    for (var i = 0; i < ended.length; i++) {
      final started = (ended[i].data()['startedAt'] as Timestamp?)?.toDate();
      final status = {for (final r in recSnaps[i].docs) r.id: r.data()['status']};
      for (final st in stats.values) {
        final v = status[st.uid];
        if (v == null || v == 'ขาด') {
          st.absent++;
          if (started != null && (st.lastAbsent == null || started.isAfter(st.lastAbsent!))) {
            st.lastAbsent = started;
          }
        } else if (v == 'สาย') {
          st.lateN++;
        }
      }
    }
    final risky = stats.values.where((s) => s.level > 0).toList()
      ..sort((a, b) {
        final c = b.absent.compareTo(a.absent);
        return c != 0 ? c : a.studentId.compareTo(b.studentId);
      });
    return _AiResult(ended.length, risky);
  }

  void reload() => setState(() => future = _load());

  String _advisorMessage(_Stat s, int total, String teacher) {
    final code = '${widget.data['subjectCode'] ?? ''}';
    final course = '${widget.data['name'] ?? ''}${code.isNotEmpty ? ' ($code)' : ''}';
    final status = s.level == 2
        ? 'เสี่ยงหมดสิทธิ์สอบ (ขาดเกิน ${kRiskAbsent - 1} ครั้ง)'
        : 'ควรเฝ้าระวัง (ขาดตั้งแต่ $kWatchAbsent ครั้ง)';
    return 'เรียน อาจารย์ที่ปรึกษา\n\n'
        'ขอแจ้งข้อมูลการเข้าเรียนของนักศึกษาในความดูแลของท่าน ในรายวิชา $course\n\n'
        'ชื่อ-สกุล: ${s.name}\n'
        'รหัสนักศึกษา: ${s.studentId}\n'
        'ขาดเรียน ${s.absent} ครั้ง จากการเช็คชื่อทั้งหมด $total ครั้ง (สาย ${s.lateN} ครั้ง)\n'
        'ขาดเรียนล่าสุดเมื่อ ${fmtShort(s.lastAbsent)}\n'
        'สถานะ: $status\n\n'
        'จึงเรียนมาเพื่อโปรดทราบ และพิจารณาให้คำปรึกษาแก่นักศึกษาต่อไป\n\n'
        'ขอแสดงความนับถือ\n'
        '${teacher.isEmpty ? 'อาจารย์ผู้สอน' : teacher}\n'
        'อาจารย์ผู้สอนวิชา $course';
  }

  Future<void> _draft(BuildContext context, _Stat s, int total) async {
    var teacher = '';
    try {
      final u = await db.doc('users/${auth.currentUser!.uid}').get();
      teacher = '${u.data()?['name'] ?? ''}';
    } catch (_) {}
    if (!context.mounted) return;
    final msg = _advisorMessage(s, total, teacher);
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('ข้อความถึงอาจารย์ที่ปรึกษา', style: TextStyle(fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(msg, style: const TextStyle(height: 1.5))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('ปิด')),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg));
              Navigator.pop(dCtx);
              if (context.mounted) toast(context, 'คัดลอกข้อความแล้ว');
            },
            child: const Text('คัดลอก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () {
              SharePlus.instance.share(ShareParams(text: msg, subject: 'แจ้งผลการเข้าเรียน ${s.name}'));
            },
            child: const Text('แชร์'),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(_AiResult r) {
    final summary = r.risky.isEmpty
        ? 'ยังไม่พบนักศึกษาเสี่ยงในวิชานี้ ทุกคนขาดเรียนไม่ถึง $kWatchAbsent ครั้ง (จากการเช็คชื่อที่จบแล้ว ${r.total} ครั้ง)'
        : 'พบนักศึกษาเสี่ยง ${r.risky.length} คนในวิชานี้ (เสี่ยงหมดสิทธิ์สอบ ${r.riskN} คน, ควรเฝ้าระวัง ${r.watchN} คน) '
            'เรียงจากขาดเรียนมากที่สุด กดที่รายชื่อเพื่อร่างข้อความแจ้งอาจารย์ที่ปรึกษา';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFEFF3FF)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: kBlueDeep, size: 20),
          const SizedBox(width: 8),
          const Text('สรุปอัตโนมัติ', style: TextStyle(color: kBlueDeep, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            tooltip: 'รีเฟรช',
            visualDensity: VisualDensity.compact,
            onPressed: reload,
            icon: const Icon(Icons.refresh_rounded, color: kMuted),
          ),
        ]),
        const SizedBox(height: 6),
        Text(summary, style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        Text(
          'สรุปนี้สร้างจากกฎ “ขาด $kWatchAbsent ครั้ง = ควรเฝ้าระวัง, ขาดเกิน ${kRiskAbsent - 1} ครั้ง = เสี่ยงหมดสิทธิ์สอบ” '
          'นับเฉพาะคาบที่เช็คชื่อจบแล้ว (ยังไม่ได้ใช้โมเดลภาษาช่วยเขียน)',
          style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.45),
        ),
      ]),
    );
  }

  Widget _studentCard(BuildContext context, _Stat s, int total) {
    final risk = s.level == 2;
    final color = risk ? kAbsent : kLate;
    final textColor = risk ? _riskText : _watchText;
    const bold = TextStyle(fontWeight: FontWeight.w700, color: kInk);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _draft(context, s, total),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20), border: Border.all(color: color, width: 1.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                  child: Text(_initial(s.name),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: textColor)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(s.studentId, style: const TextStyle(color: kMuted, fontSize: 13)),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: textColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(risk ? 'เสี่ยงหมดสิทธิ์สอบ' : 'ควรเฝ้าระวัง',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text.rich(TextSpan(style: const TextStyle(color: kMuted, fontSize: 13.5), children: [
                const TextSpan(text: 'ขาด '),
                TextSpan(text: '${s.absent}', style: bold),
                TextSpan(text: '/$total     สาย '),
                TextSpan(text: '${s.lateN}', style: bold),
                TextSpan(text: '     ขาดล่าสุด ${fmtShort(s.lastAbsent)}'),
              ])),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _draft(context, s, total),
                icon: const Icon(Icons.notifications_none_rounded, size: 20, color: kInk),
                label: const Text('ร่างข้อความแจ้งอาจารย์ที่ปรึกษา'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<_AiResult>(
      future: future,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) return const Loading();
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded, size: 40, color: kAbsent),
                const SizedBox(height: 12),
                const Text('โหลดสรุปไม่สำเร็จ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
                TextButton(onPressed: reload, child: const Text('ลองใหม่')),
              ]),
            ),
          );
        }
        final r = snap.data!;
        if (r.total == 0) {
          return const EmptyState(
            icon: Icons.auto_awesome_outlined,
            title: 'ยังไม่มีข้อมูลสำหรับสรุป',
            hint: 'เมื่อมีการเช็คชื่อที่จบแล้วอย่างน้อย 1 ครั้ง ระบบจะสรุปให้ที่นี่',
          );
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          _summaryCard(r),
          const SizedBox(height: 14),
          for (final s in r.risky) _studentCard(c, s, r.total),
        ]);
      },
    );
  }
}

// ============================================================
//  4) แท็บ "สมาชิก"
// ============================================================
class MembersTab extends StatelessWidget {
  final String classId, code;
  const MembersTab({super.key, required this.classId, required this.code});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('classes/$classId/students').snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const Loading();
          final docs = s.data!.docs.toList()
            ..sort((a, b) => '${a.data()['studentId']}'.compareTo('${b.data()['studentId']}'));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  toast(context, 'คัดลอกรหัสห้องแล้ว');
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('รหัสเข้าร่วมห้อง', style: TextStyle(color: kMuted, fontSize: 13)),
                        Text(code,
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 3, color: kBlueDeep)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${docs.length}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                      const Text('สมาชิก (คน)', style: TextStyle(color: kMuted, fontSize: 13)),
                    ]),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (docs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: Text('ยังไม่มีนักศึกษาเข้าร่วมห้องนี้', style: TextStyle(color: kMuted))),
              ),
            for (final d in docs)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: kBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Text(_initial('${d.data()['name'] ?? ''}'),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: kBlueDeep)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${d.data()['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${d.data()['studentId'] ?? ''}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
          ]);
        },
      );
}

// ============================================================
//  5) ลบห้อง (อาจารย์) / ออกจากห้อง (นักศึกษา)
// ============================================================
Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> c) async {
  final snap = await c.get();
  for (var i = 0; i < snap.docs.length; i += 400) {
    final b = db.batch();
    for (final d in snap.docs.skip(i).take(400)) {
      b.delete(d.reference);
    }
    await b.commit();
  }
}

/// Firestore ไม่ลบ subcollection ให้อัตโนมัติ จึงลบ records -> sessions -> students -> ห้อง ตามลำดับ
Future<void> deleteClassDeep(String classId) async {
  final base = db.doc('classes/$classId');
  final sessions = await base.collection('sessions').get();
  for (final s in sessions.docs) {
    await _deleteCollection(s.reference.collection('records'));
    await s.reference.delete();
  }
  await _deleteCollection(base.collection('students'));
  await base.delete();
}

Future<void> leaveClass(String classId) async {
  final uid = auth.currentUser!.uid;
  final ref = db.doc('classes/$classId');
  final b = db.batch();
  b.delete(ref.collection('students').doc(uid));
  b.update(ref, {'members': FieldValue.arrayRemove([uid])});
  await b.commit();
}

class DeleteClassButton extends StatelessWidget {
  final String classId, className;
  const DeleteClassButton({super.key, required this.classId, required this.className});

  Future<void> _run(BuildContext c) async {
    final ok = await confirmDialog(
      c,
      title: 'ลบห้องเรียน',
      message: 'ลบ “$className” ถาวร รวมถึงรายชื่อนักศึกษาและประวัติเช็คชื่อทั้งหมด ย้อนกลับไม่ได้ ต้องการลบใช่ไหม?',
      okLabel: 'ลบห้อง',
    );
    if (!ok || !c.mounted) return;
    showDialog<void>(
      context: c,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
    );
    try {
      await deleteClassDeep(classId);
      if (!c.mounted) return;
      toast(c, 'ลบห้องเรียนแล้ว');
      Navigator.pop(c); // ปิดวงกลมโหลด
      Navigator.pop(c); // ออกจากหน้าห้อง
    } catch (e) {
      if (!c.mounted) return;
      Navigator.pop(c);
      toast(c, 'ลบไม่สำเร็จ: $e');
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'ลบห้องเรียน',
        icon: const Icon(Icons.delete_outline_rounded, color: kAbsent),
        onPressed: () => _run(context),
      );
}

class LeaveClassButton extends StatelessWidget {
  final String classId, className;
  const LeaveClassButton({super.key, required this.classId, required this.className});

  Future<void> _run(BuildContext c) async {
    final ok = await confirmDialog(
      c,
      title: 'ออกจากห้องเรียน',
      message: 'ออกจาก “$className” ใช่ไหม? ห้องนี้จะหายจากรายการของคุณ และชื่อคุณจะไม่อยู่ในรายชื่อรายงานของอาจารย์ '
          'ถ้าเข้าร่วมใหม่ด้วยรหัสห้อง จะเห็นประวัติการเข้าเรียนเดิมกลับมา',
      okLabel: 'ออกจากห้อง',
    );
    if (!ok || !c.mounted) return;
    try {
      await leaveClass(classId);
      if (!c.mounted) return;
      toast(c, 'ออกจากห้องเรียนแล้ว');
      Navigator.pop(c);
    } catch (e) {
      if (c.mounted) toast(c, 'ออกจากห้องไม่สำเร็จ: $e');
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'ออกจากห้อง',
        icon: const Icon(Icons.exit_to_app_rounded, color: kAbsent),
        onPressed: () => _run(context),
      );
}
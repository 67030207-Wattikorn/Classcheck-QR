// report.dart — แท็บรายงาน และปุ่มส่งออก PDF / Excel / Word
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'export.dart';
import 'helpers.dart';
import 'widgets.dart';

// ปุ่มส่งออกรายงาน PDF / Excel / Word
class ExportBar extends StatefulWidget {
  final String classId, sessionLabel;
  final List<List<String>> rows;
  final int ok, late, absent;
  const ExportBar({
    super.key,
    required this.classId,
    required this.sessionLabel,
    required this.rows,
    required this.ok,
    required this.late,
    required this.absent,
  });
  @override
  State<ExportBar> createState() => _ExportBarState();
}

class _ExportBarState extends State<ExportBar> {
  bool busy = false;

  Future<void> run(String kind) async {
    if (widget.rows.isEmpty) return toast(context, 'ยังไม่มีรายชื่อให้ส่งออก');
    setState(() => busy = true);
    try {
      final cls = await db.doc('classes/${widget.classId}').get();
      final data = cls.data();
      final name = [data?['name'], data?['subjectCode']]
          .where((e) => e != null && '$e'.isNotEmpty)
          .join('  ');
      await exportReport(
        kind: kind,
        className: name,
        sessionLabel: widget.sessionLabel,
        rows: widget.rows,
        onTime: widget.ok,
        lateCount: widget.late,
        absentCount: widget.absent,
      );
    } catch (e) {
      if (mounted) toast(context, 'ส่งออกไม่สำเร็จ: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Widget btn(String label, IconData icon, String kind) => Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          onPressed: busy ? null : () => run(kind),
          icon: Icon(icon, size: 20, color: kBlue),
          label: Text(label),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          btn('PDF', Icons.picture_as_pdf_outlined, 'pdf'),
          const SizedBox(width: 8),
          btn('Excel', Icons.table_chart_outlined, 'xlsx'),
          const SizedBox(width: 8),
          btn('Word', Icons.description_outlined, 'docx'),
        ]),
      );
}

class ReportTab extends StatefulWidget {
  final String classId;
  const ReportTab({super.key, required this.classId});
  @override
  State<ReportTab> createState() => _ReportState();
}

class _ReportState extends State<ReportTab> {
  String? sid;
  @override
  Widget build(BuildContext context) {
    final base = 'classes/${widget.classId}';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('$base/sessions').orderBy('startedAt', descending: true).snapshots(),
      builder: (c, ss) {
        if (!ss.hasData) return const Loading();
        final sessions = ss.data!.docs;
        if (sessions.isEmpty) {
          return const EmptyState(
              icon: Icons.insert_chart_outlined_rounded,
              title: 'ยังไม่มีการเช็คชื่อ',
              hint: 'เปิดเช็คชื่อในแท็บแรก แล้วผลจะมาแสดงที่นี่');
        }
        sid ??= sessions.first.id;
        final current = sessions.any((e) => e.id == sid) ? sid : sessions.first.id;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: current,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  icon: const Icon(Icons.expand_more_rounded),
                  items: [
                    for (final s in sessions)
                      DropdownMenuItem(
                          value: s.id, child: Text('คาบ ${fmt((s['startedAt'] as Timestamp?)?.toDate())}')),
                  ],
                  onChanged: (v) => setState(() => sid = v),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('$base/students').snapshots(),
              builder: (c, st) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('$base/sessions/$current/records').snapshots(),
                builder: (c, rs) {
                  if (!st.hasData || !rs.hasData) return const Loading();
                  final rec = {for (final d in rs.data!.docs) d.id: d.data()};
                  final students = st.data!.docs.toList()
                    ..sort((a, b) => '${a['studentId']}'.compareTo('${b['studentId']}'));
                  final rows = <List<String>>[];
                  var ok = 0, late = 0, absent = 0;
                  for (var i = 0; i < students.length; i++) {
                    final s = students[i];
                    final r = rec[s.id];
                    final status = r?['status'] ?? 'ขาด';
                    if (status == 'ตรงเวลา') ok++;
                    if (status == 'สาย') late++;
                    if (status == 'ขาด') absent++;
                    rows.add([
                      '${i + 1}',
                      '${s['studentId']}',
                      '${s['name']}',
                      status,
                      fmtTime((r?['time'] as Timestamp?)?.toDate()),
                    ]);
                  }
                  return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    StatusBar(ok: ok, late: late, absent: absent),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('คัดลอกเป็น CSV (วางใน Excel)'),
                        onPressed: () {
                          final csv =
                              '\uFEFFลำดับ,รหัส,ชื่อ-สกุล,สถานะ,เวลา\n${rows.map((r) => r.join(',')).join('\n')}';
                          Clipboard.setData(ClipboardData(text: csv));
                          toast(context, 'คัดลอกแล้ว นำไปวางใน Excel ได้เลย');
                        },
                      ),
                    ),
                    ExportBar(
                      classId: widget.classId,
                      sessionLabel: fmt((sessions.firstWhere((e) => e.id == current)['startedAt'] as Timestamp?)?.toDate()),
                      rows: rows,
                      ok: ok,
                      late: late,
                      absent: absent,
                    ),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(child: Text('ยังไม่มีนักศึกษาเข้าร่วมห้องนี้', style: TextStyle(color: kMuted))),
                      ),
                    for (final r in rows)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kLine)),
                        child: Row(children: [
                          Container(
                            width: 4,
                            height: 36,
                            decoration: BoxDecoration(
                                color: statusColor(r[3]), borderRadius: BorderRadius.circular(4)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r[2], style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${r[1]}   ${r[4]}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                            ]),
                          ),
                          StatusChip(r[3]),
                        ]),
                      ),
                  ]);
                },
              ),
            ),
          ),
        ]);
      },
    );
  }
}
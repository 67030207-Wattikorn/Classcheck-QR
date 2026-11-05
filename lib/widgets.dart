// widgets.dart — วิดเจ็ตที่ใช้ซ้ำหลายหน้า (Header, StatusChip, EmptyState, StatusBar, Loading)
import 'package:flutter/material.dart';
import 'config.dart';
import 'helpers.dart';

class Header extends StatelessWidget {
  final Widget child;
  const Header({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kBlue, kBlueDeep]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        ),
        child: child,
      );
}

class StatusChip extends StatelessWidget {
  final String s;
  const StatusChip(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(s, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, hint;
  const EmptyState({super.key, required this.icon, required this.title, required this.hint});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: kBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: kBlue),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
          ]),
        ),
      );
}

// แถบสัดส่วน ตรงเวลา/สาย/ขาด (เหมือนในภาพ UI ของสไลด์)
class StatusBar extends StatelessWidget {
  final int ok, late, absent;
  const StatusBar({super.key, required this.ok, required this.late, required this.absent});
  @override
  Widget build(BuildContext context) {
    final total = ok + late + absent;
    Widget seg(int n, Color c) => n == 0 ? const SizedBox() : Expanded(flex: n, child: Container(color: c));
    Widget stat(String label, int n, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: c, height: 1.1)),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: total == 0
                ? Container(color: kLine)
                : Row(children: [seg(ok, kOk), seg(late, kLate), seg(absent, kAbsent)]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [stat('ตรงเวลา', ok, kOk), stat('สาย', late, kLate), stat('ขาด', absent, kAbsent)]),
      ]),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
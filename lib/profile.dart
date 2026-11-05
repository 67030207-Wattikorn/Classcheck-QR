// profile.dart — Gate (ตรวจว่ามีโปรไฟล์หรือยัง) และหน้าตั้งค่าโปรไฟล์
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'config.dart';
import 'helpers.dart';
import 'home.dart';
import 'widgets.dart';

// ---------- gate + profile ----------
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.doc('users/${auth.currentUser!.uid}').snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const Loading();
          if (!s.data!.exists) return registering ? const Loading() : const ProfileSetup();
          return Home(user: s.data!.data()!);
        },
      );
}

class ProfileSetup extends StatefulWidget {
  const ProfileSetup({super.key});
  @override
  State<ProfileSetup> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<ProfileSetup> {
  final name = TextEditingController(text: auth.currentUser?.displayName ?? '');
  final sid = TextEditingController();
  final email = auth.currentUser?.email ?? '';
  late final bool teacher = !email.endsWith('@kmitl.ac.th');

  Future<void> save() async {
    if (name.text.trim().isEmpty) return toast(context, 'กรุณากรอกชื่อ-สกุล');
    if (!teacher && sid.text.trim().isEmpty) return toast(context, 'กรุณากรอกรหัสนักศึกษา');
    await db.doc('users/${auth.currentUser!.uid}').set({
      'email': email,
      'name': name.text.trim(),
      'studentId': sid.text.trim(),
      'role': teacher ? 'teacher' : 'student',
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Header(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ตั้งค่าโปรไฟล์',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(email, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text(teacher ? 'ครู / อาจารย์' : 'นักเรียน / นักศึกษา',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              IconButton(onPressed: () => confirmSignOut(context), icon: const Icon(Icons.logout, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(24), children: [
              TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'ชื่อ-สกุล', prefixIcon: Icon(Icons.person_outline))),
              if (!teacher) ...[
                const SizedBox(height: 12),
                TextField(
                    controller: sid,
                    decoration: const InputDecoration(labelText: 'รหัสนักศึกษา', prefixIcon: Icon(Icons.tag))),
              ],
              const SizedBox(height: 22),
              FilledButton(onPressed: save, child: const Text('บันทึกและเริ่มใช้งาน')),
            ]),
          ),
        ]),
      );
}
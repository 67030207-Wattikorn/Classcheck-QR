// login_page.dart — หน้าเข้าสู่ระบบ / สมัครสมาชิก
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'config.dart';
import 'helpers.dart';
import 'widgets.dart';

// ---------- login / register ----------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController();
  final name = TextEditingController(), sid = TextEditingController();
  bool teacher = false, register = false, busy = false, hide = true;

  Future<void> submit() async {
    final e = email.text.trim();
    setState(() => busy = true);
    try {
      if (register) {
        if (teacher && !e.endsWith('@gmail.com')) throw 'อาจารย์ต้องใช้อีเมล @gmail.com';
        if (!teacher && !e.endsWith('@kmitl.ac.th')) throw 'นักศึกษาต้องใช้อีเมล @kmitl.ac.th';
        if (pass.text.length < 6) throw 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
        if (name.text.trim().isEmpty) throw 'กรุณากรอกชื่อ-สกุล';
        if (!teacher && sid.text.trim().isEmpty) throw 'กรุณากรอกรหัสนักศึกษา';
        registering = true;
        final cr = await auth.createUserWithEmailAndPassword(email: e, password: pass.text);
        await db.doc('users/${cr.user!.uid}').set({
          'email': e,
          'name': name.text.trim(),
          'studentId': sid.text.trim(),
          'role': teacher ? 'teacher' : 'student',
        });
      } else {
        await auth.signInWithEmailAndPassword(email: e, password: pass.text);
      }
    } on FirebaseAuthException catch (ex) {
      final m = {
        'invalid-credential': 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
        'wrong-password': 'รหัสผ่านไม่ถูกต้อง',
        'user-not-found': 'ไม่พบบัญชีนี้',
        'email-already-in-use': 'อีเมลนี้ถูกใช้แล้ว',
        'invalid-email': 'รูปแบบอีเมลไม่ถูกต้อง',
      };
      if (mounted) toast(context, m[ex.code] ?? 'เกิดข้อผิดพลาด: ${ex.code}');
    } catch (ex) {
      if (mounted) toast(context, ex.toString());
    } finally {
      registering = false;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> googleLogin() async {
    setState(() => busy = true);
    try {
      final UserCredential cr;
      if (kIsWeb) {
        cr = await auth.signInWithPopup(GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}));
      } else {
        if (!gsiReady) {
          await GoogleSignIn.instance.initialize(serverClientId: kWebClientId);
          gsiReady = true;
        }
        final acc = await GoogleSignIn.instance.authenticate();
        final idToken = acc.authentication.idToken;
        if (idToken == null) throw 'ไม่ได้รับ ID token จาก Google';
        cr = await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      }
      final e = cr.user?.email ?? '';
      if (!e.endsWith('@gmail.com') && !e.endsWith('@kmitl.ac.th')) {
        await auth.signOut();
        if (!kIsWeb) await GoogleSignIn.instance.signOut();
        throw 'ใช้ได้เฉพาะอีเมล @gmail.com (ครู) หรือ @kmitl.ac.th (นักศึกษา)';
      }
    } on GoogleSignInException catch (ex) {
      if (mounted && ex.code != GoogleSignInExceptionCode.canceled) {
        toast(context, 'Google: ${ex.code.name} ${ex.description ?? ''}');
      }
    } on FirebaseAuthException catch (ex) {
      if (mounted) toast(context, 'Firebase: ${ex.code}');
    } catch (ex) {
      if (mounted) toast(context, ex.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  Widget roleButton(String label, IconData icon, bool value) {
    final on = teacher == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => teacher = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: on ? kBlue : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? kBlue : kLine, width: 1.5),
          ),
          child: Column(children: [
            Icon(icon, color: on ? Colors.white : kMuted),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : kMuted)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Header(
            child: Column(children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.qr_code_2_rounded, size: 42, color: kBlue),
              ),
              const SizedBox(height: 14),
              const Text('ClassCheck QR',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('เช็คชื่อด้วย QR ครูเห็นผลทันที ไม่ต้องขานชื่อ',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), children: [
                  Text(register ? 'สร้างบัญชีใหม่' : 'เข้าสู่ระบบ',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  if (register) ...[
                    Row(children: [
                      roleButton('นักเรียน / นักศึกษา', Icons.school_outlined, false),
                      const SizedBox(width: 12),
                      roleButton('ครู / อาจารย์', Icons.badge_outlined, true),
                    ]),
                    const SizedBox(height: 14),
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: 'ชื่อ-สกุล', prefixIcon: Icon(Icons.person_outline))),
                    if (!teacher) ...[
                      const SizedBox(height: 12),
                      TextField(
                          controller: sid,
                          decoration: const InputDecoration(
                              labelText: 'รหัสนักศึกษา', prefixIcon: Icon(Icons.tag))),
                    ],
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'อีเมล',
                      prefixIcon: const Icon(Icons.mail_outline),
                      helperText: register ? (teacher ? 'ใช้ @gmail.com' : 'ใช้อีเมลสถาบัน @kmitl.ac.th') : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: hide,
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                          icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => hide = !hide)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(register ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ'),
                  ),
                  const SizedBox(height: 18),
                  Row(children: const [
                    Expanded(child: Divider(color: kLine)),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('หรือ', style: TextStyle(color: kMuted))),
                    Expanded(child: Divider(color: kLine)),
                  ]),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: busy ? null : googleLogin,
                    icon: const Icon(Icons.account_circle_outlined, color: kBlue),
                    label: const Text('เข้าสู่ระบบด้วย Google'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => register = !register),
                    child: Text(register ? 'มีบัญชีแล้ว? เข้าสู่ระบบ' : 'ยังไม่มีบัญชี? สมัครสมาชิก'),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      );
}
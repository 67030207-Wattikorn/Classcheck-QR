// main.dart — จุดเริ่มต้นของแอป + ธีม (ส่วนอื่นแยกอยู่ในไฟล์ต่าง ๆ ในโฟลเดอร์ lib/)
// ต้องมีแพ็กเกจ: flutter pub add google_fonts
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config.dart';
import 'firebase_options.dart'; // สร้างโดย flutterfire configure
import 'login_page.dart';
import 'profile.dart';
import 'widgets.dart';

// ส่งต่อทุกไฟล์ออกไป เพื่อให้ไฟล์เดิม (features.dart / export.dart) ที่ import 'main.dart' ยังใช้ db, auth, toast, สี ฯลฯ ได้เหมือนเดิม
export 'config.dart';
export 'helpers.dart';
export 'widgets.dart';
export 'login_page.dart';
export 'profile.dart';
export 'home.dart';
export 'teacher.dart';
export 'report.dart';
export 'student.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const App());
}

// ---------- app ----------
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    final field = OutlineInputBorder(
        borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine));
    return MaterialApp(
      title: 'ClassCheck QR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue, surface: Colors.white),
        scaffoldBackgroundColor: kPaper,
        textTheme: GoogleFonts.promptTextTheme().apply(bodyColor: kInk, displayColor: kInk),
        appBarTheme: AppBarTheme(
          backgroundColor: kPaper,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: kInk,
          titleTextStyle: GoogleFonts.prompt(fontSize: 19, fontWeight: FontWeight.w600, color: kInk),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: field,
          enabledBorder: field,
          focusedBorder: field.copyWith(borderSide: const BorderSide(color: kBlue, width: 2)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kBlue,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: GoogleFonts.prompt(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kInk,
            minimumSize: const Size.fromHeight(54),
            side: const BorderSide(color: kLine, width: 1.5),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: GoogleFonts.prompt(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: kBlue,
          foregroundColor: Colors.white,
          extendedTextStyle: GoogleFonts.prompt(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: auth.authStateChanges(),
        builder: (c, s) {
          if (s.connectionState == ConnectionState.waiting) return const Loading();
          return s.data == null ? const LoginPage() : const Gate();
        },
      ),
    );
  }
}
// config.dart — ค่าคงที่, สี, และตัวแปรกลางของแอป (แก้ค่าตั้งต้นที่นี่)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// Web client ID: Firebase Console > Authentication > Sign-in method > Google > Web SDK configuration
const kWebClientId = '816524800203-j6no7arilqku3pvi7mq09i152e79kf5m.apps.googleusercontent.com';
const kRadiusMeters = 100.0; // รัศมีเช็คชื่อ (เมตร) ปรับได้ตามขนาดตึก
const kQrRefreshSeconds = 20; // QR เปลี่ยนรหัสทุกกี่วินาที
const kLateMinutes = 15; // เกินกี่นาทีนับว่า "สาย"

// ---------- palette ----------
const kBlue = Color(0xFF4F7FE8); // น้ำเงินจากสไลด์
const kBlueDeep = Color(0xFF2E55C9);
const kInk = Color(0xFF16213A);
const kMuted = Color(0xFF6B7690);
const kPaper = Color(0xFFF5F8FF);
const kLine = Color(0xFFE1E8F7);
const kOk = Color(0xFF1FA971);
const kLate = Color(0xFFF29B2C);
const kAbsent = Color(0xFFE5484D);
const kTiles = [kBlue, Color(0xFF2FB38A), Color(0xFFF2994A), Color(0xFF8B6BE0), Color(0xFFE2607D)];

bool gsiReady = false;
bool registering = false;
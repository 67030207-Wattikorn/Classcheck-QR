
// Unit tests for lib/helpers.dart (no Firebase connection needed)
import 'package:classcheck_qr/config.dart';
import 'package:classcheck_qr/helpers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('genCode / genToken', () {
    test('genCode is 6 chars from the allowed alphabet', () {
      final c = genCode();
      expect(c.length, 6);
      expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(c), isTrue);
    });

    test('genToken is 10 chars and random', () {
      final a = genToken(), b = genToken();
      expect(a.length, 10);
      expect(a == b, isFalse);
    });
  });

  group('date and time', () {
    test('p2 pads with a leading zero', () {
      expect(p2(5), '05');
      expect(p2(12), '12');
    });

    test('fmt uses the Buddhist year', () {
      expect(fmt(DateTime(2026, 11, 5, 9, 7)), '05/11/2569 09:07');
    });

    test('fmt and fmtTime accept null', () {
      expect(fmt(null), '-');
      expect(fmtTime(null), '-');
    });

    test('fmtTime appends the Thai time suffix', () {
      expect(fmtTime(DateTime(2026, 1, 1, 8, 30)), '08:30 \u0e19.');
    });
  });

  group('statusColor', () {
    test('each status maps to the right color', () {
      expect(statusColor('\u0e15\u0e23\u0e07\u0e40\u0e27\u0e25\u0e32'), kOk);
      expect(statusColor('\u0e2a\u0e32\u0e22'), kLate);
      expect(statusColor('\u0e02\u0e32\u0e14'), kAbsent);
      expect(statusColor('\u0e22\u0e31\u0e07\u0e44\u0e21\u0e48\u0e40\u0e0a\u0e47\u0e04'), kMuted);
    });
  });

  group('UpperCaseTextFormatter', () {
    test('converts typed text to upper case', () {
      final out = UpperCaseTextFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'ab3x'),
      );
      expect(out.text, 'AB3X');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/datetime_utils.dart';

void main() {
  group('parseApiDateTime', () {
    test('parses UTC Z suffix into local time', () {
      final parsed = parseApiDateTime('2026-04-11T14:00:00.000Z');
      expect(parsed.isUtc, isFalse);
      expect(parsed.year, 2026);
      expect(parsed.month, 4);
      expect(parsed.day, 11);
    });

    test('parses explicit offset into local time', () {
      final parsed = parseApiDateTime('2026-04-11T09:00:00-04:00');
      expect(parsed.isUtc, isFalse);
    });

    test('treats offset-less values as UTC', () {
      final parsed = parseApiDateTime('2026-04-11T09:00:00.000');
      expect(parsed.isUtc, isFalse);
    });
  });
}

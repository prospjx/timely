import 'package:flutter/services.dart';

class HapticService {
  HapticService._();

  static Future<void> lightImpact() => HapticFeedback.lightImpact();

  static Future<void> selectionClick() => HapticFeedback.selectionClick();

  static Future<void> mediumImpact() => HapticFeedback.mediumImpact();
}

/// Parses API datetimes stored in UTC and converts them to the device timezone for display.
DateTime parseApiDateTime(String raw) {
  if (raw.endsWith('Z')) {
    return DateTime.parse(raw).toLocal();
  }

  final hasOffset = RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
  if (hasOffset) {
    return DateTime.parse(raw).toLocal();
  }

  return DateTime.parse('${raw}Z').toLocal();
}

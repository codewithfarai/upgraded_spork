// Valid Zimbabwean mobile prefixes (after stripping country code / leading 0):
// 71x = NetOne, 73x = Telecel/Africell, 77x/78x = Econet
final _zwMobilePrefix = RegExp(r'^7[1378]\d{7}$');

const zwCities = [
  'Harare',
  'Bulawayo',
  'Masvingo',
  'Gweru',
  'Kadoma',
  'Victoria Falls',
];

/// Validates and normalises a Zimbabwean mobile number.
/// Returns the E.164 form (+263xxxxxxxxx) on success, null on failure.
String? parseZwNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');

  String local;
  if (digits.startsWith('+263')) {
    local = digits.substring(4);
  } else if (digits.startsWith('263')) {
    local = digits.substring(3);
  } else if (digits.startsWith('0')) {
    local = digits.substring(1);
  } else {
    local = digits;
  }

  if (!_zwMobilePrefix.hasMatch(local)) return null;
  return '+263$local';
}

const zwPhoneError = 'Enter a valid Zimbabwean number (077, 078, 071, 073)';

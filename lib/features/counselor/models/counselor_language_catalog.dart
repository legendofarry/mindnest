const counselorLanguageOptions = <String>[
  'English',
  'Swahili',
  'Kikuyu',
  'Luo',
  'Kalenjin',
  'Luhya',
  'Kamba',
  'Somali',
];

String normalizeCounselorLanguage(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  switch (trimmed.toLowerCase()) {
    case 'english':
      return 'English';
    case 'swahili':
    case 'kiswahili':
      return 'Swahili';
    case 'kikuyu':
      return 'Kikuyu';
    case 'luo':
      return 'Luo';
    case 'kalenjin':
      return 'Kalenjin';
    case 'luhya':
      return 'Luhya';
    case 'kamba':
      return 'Kamba';
    case 'somali':
      return 'Somali';
    default:
      return trimmed;
  }
}

List<String> normalizeCounselorLanguages(Iterable<dynamic> values) {
  final normalized = <String>[];
  final seen = <String>{};

  for (final value in values) {
    final cleaned = normalizeCounselorLanguage(value?.toString() ?? '');
    if (cleaned.isEmpty) {
      continue;
    }
    final key = cleaned.toLowerCase();
    if (seen.add(key)) {
      normalized.add(cleaned);
    }
  }

  return normalized;
}

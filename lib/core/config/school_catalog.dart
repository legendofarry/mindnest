class CatalogSchool {
  const CatalogSchool({required this.id, required this.name});

  final String id;
  final String name;
}

String _normalizeCatalogKey(String value) {
  return value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _catalogSchoolIdFromName(String name) => _normalizeCatalogKey(name);

final List<String> _catalogSchoolNames = List<String>.unmodifiable(
  <String>[
    'University of Nairobi',
    'Kenyatta University',
    'Moi University',
    'Egerton University',
    'Jomo Kenyatta University of Agriculture and Technology (JKUAT)',
    'Maseno University',
    'Masinde Muliro University of Science and Technology',
    'Dedan Kimathi University of Technology',
    'Chuka University',
    'Technical University of Kenya',
    'Technical University of Mombasa',
    'Pwani University',
    'Kisii University',
    'University of Eldoret',
    'Maasai Mara University',
    'Jaramogi Oginga Odinga University of Science and Technology',
    'Laikipia University',
    'South Eastern Kenya University',
    'Meru University of Science and Technology',
    'Multimedia University of Kenya',
    'Karatina University',
    'Kibabii University',
    'Rongo University',
    'Taita Taveta University',
    'Co-operative University of Kenya',
    "Murang'a University of Technology",
    'University of Embu',
    'Machakos University',
    'Kirinyaga University',
    'Garissa University',
    'Alupe University',
    'Kaimosi Friends University',
    'Tom Mboya University',
    'Tharaka Nithi University',
    'University of Kabianga',
    'Strathmore University',
    'Mount Kenya University',
    'Daystar University',
    'Catholic University of Eastern Africa (CUEA)',
    'United States International University (USIU-Africa)',
    'Africa Nazarene University',
    'Kenya Methodist University (KeMU)',
    "St. Paul's University",
    'Pan Africa Christian University',
    'Kabarak University',
    'Africa International University',
    'Kenya Highlands University',
    'Great Lakes University of Kisumu',
    'KCA University',
    'Adventist University of Africa',
    'KAG East University',
    'Umma University',
    'Presbyterian University of East Africa',
    'Aga Khan University',
    "Kiriri Women's University of Science and Technology",
    'The East African University',
    'Zetech University',
    'Lukenya University',
    'Management University of Africa',
    'Tangaza University',
    'Islamic University of Kenya',
    'Scott Christian University',
    'National Defence University-Kenya',
    'Open University of Kenya',
    'National Intelligence and Research University',
    'Kenya Coast National Polytechnic',
    'Kisumu National Polytechnic',
    'Eldoret National Polytechnic',
    'Kabete National Polytechnic',
    'Rift Valley National Polytechnic',
    'Nyeri National Polytechnic',
    'Meru National Polytechnic',
    'Sigalagala National Polytechnic',
    'North Eastern National Polytechnic',
    'Kitale National Polytechnic',
    'Nairobi Technical Training Institute',
    'Thika Technical Training Institute',
    'Machakos Technical Training Institute',
    'Kitale Technical Training Institute',
    'Nakuru Technical Training Institute',
    'Rift Valley Technical Training Institute',
    'Mombasa Technical Training Institute',
    'Kenya Institute of Mass Communication (KIMC)',
    'Kenya Medical Training College (KMTC)',
    'Kenya School of Government',
    'Kenya Institute of Surveying and Mapping',
    'Kenya Forestry College',
    'Bura Vocational Rehabilitation Centre',
    'Muriranjas Vocational Rehabilitation Centre',
    'Kakamega Vocational Rehabilitation Centre',
    'Odiado Vocational Rehabilitation Centre',
    'Machakos Vocational Rehabilitation Centre',
    'Industrial Rehabilitation Centre (IRC) - Nairobi',
    'Embu Vocational Rehabilitation Centre',
    'Kabarnet Vocational Rehabilitation Centre',
    'Nyandarua Vocational Rehabilitation Centre',
    'Kericho Vocational Rehabilitation Centre',
    'Itando Vocational Rehabilitation Centre',
    'Kisii Vocational Rehabilitation Centre',
    'Kenya Institute of Special Education (KISE) - Nairobi',
    'Kenya Institute for the Blind (KIB) - Nairobi',
    'Karen Technical Training Institute for the Deaf - Nairobi',
    'Machakos Technical Training Institute for the Blind - Machakos',
    'Variety Village Vocational Training Centre - Thika',
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
);

final List<CatalogSchool> kCatalogSchools = List<CatalogSchool>.unmodifiable(
  _catalogSchoolNames.map(
    (name) => CatalogSchool(id: _catalogSchoolIdFromName(name), name: name),
  ),
);

final Map<String, CatalogSchool> kCatalogSchoolsById = <String, CatalogSchool>{
  for (final school in kCatalogSchools) school.id: school,
};

const Map<String, String> _legacyCatalogSchoolAliases = <String, String>{
  'ke_uon': 'university_of_nairobi',
  'ke_ku': 'kenyatta_university',
  'ke_mu': 'moi_university',
  'ke_jkuat': 'jomo_kenyatta_university_of_agriculture_and_technology_jkuat',
  'ke_egerton': 'egerton_university',
  'ke_maseno': 'maseno_university',
  'ke_usiu_africa': 'united_states_international_university_usiu_africa',
  'ke_strathmore': 'strathmore_university',
  'ke_mku': 'mount_kenya_university',
  'ke_kca': 'kca_university',
  'ke_daystar': 'daystar_university',
  'ke_tuk': 'technical_university_of_kenya',
  'ke_mmust': 'multimedia_university_of_kenya',
  'ke_anu': 'africa_nazarene_university',
  'ke_zetech': 'zetech_university',
};

CatalogSchool? catalogSchoolById(String? id) {
  final normalizedId = id?.trim() ?? '';
  if (normalizedId.isEmpty) {
    return null;
  }
  final resolvedId = _legacyCatalogSchoolAliases[normalizedId] ?? normalizedId;
  return kCatalogSchoolsById[resolvedId];
}

final List<String> kHardcodedSchools = List<String>.unmodifiable(
  kCatalogSchools.map((school) => school.name),
);

class CatalogSchool {
  const CatalogSchool({required this.id, required this.name});

  final String id;
  final String name;
}

const List<CatalogSchool> kCatalogSchools = <CatalogSchool>[
  CatalogSchool(id: 'ke_uon', name: 'University of Nairobi'),
  CatalogSchool(id: 'ke_ku', name: 'Kenyatta University'),
  CatalogSchool(id: 'ke_mu', name: 'Moi University'),
  CatalogSchool(
    id: 'ke_jkuat',
    name: 'Jomo Kenyatta University of Agriculture and Technology',
  ),
  CatalogSchool(id: 'ke_egerton', name: 'Egerton University'),
  CatalogSchool(id: 'ke_maseno', name: 'Maseno University'),
  CatalogSchool(id: 'ke_usiu_africa', name: 'USIU-Africa'),
  CatalogSchool(id: 'ke_strathmore', name: 'Strathmore University'),
  CatalogSchool(id: 'ke_mku', name: 'Mount Kenya University'),
  CatalogSchool(id: 'ke_kca', name: 'KCA University'),
  CatalogSchool(id: 'ke_daystar', name: 'Daystar University'),
  CatalogSchool(id: 'ke_tuk', name: 'Technical University of Kenya'),
  CatalogSchool(id: 'ke_mmust', name: 'Multimedia University of Kenya'),
  CatalogSchool(id: 'ke_anu', name: 'Africa Nazarene University'),
  CatalogSchool(id: 'ke_zetech', name: 'Zetech University'),
];

final Map<String, CatalogSchool> kCatalogSchoolsById = <String, CatalogSchool>{
  for (final school in kCatalogSchools) school.id: school,
};

CatalogSchool? catalogSchoolById(String? id) {
  final normalizedId = id?.trim() ?? '';
  if (normalizedId.isEmpty) {
    return null;
  }
  return kCatalogSchoolsById[normalizedId];
}

final List<String> kHardcodedSchools = List<String>.unmodifiable(
  kCatalogSchools.map((school) => school.name),
);

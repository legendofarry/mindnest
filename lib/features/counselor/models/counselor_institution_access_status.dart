enum CounselorInstitutionAccessStatus {
  inactive,
  pending,
  active,
  suspended,
  removed,
}

extension CounselorInstitutionAccessStatusX
    on CounselorInstitutionAccessStatus {
  bool get allowsCounselorWorkflow =>
      this == CounselorInstitutionAccessStatus.pending ||
      this == CounselorInstitutionAccessStatus.active;

  bool get isRemoved => this == CounselorInstitutionAccessStatus.removed;
}

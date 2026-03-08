class CounselorWorkflowSettings {
  const CounselorWorkflowSettings({
    required this.directoryEnabled,
    required this.reassignmentEnabled,
  });

  const CounselorWorkflowSettings.disabled()
    : directoryEnabled = false,
      reassignmentEnabled = false;

  final bool directoryEnabled;
  final bool reassignmentEnabled;

  factory CounselorWorkflowSettings.fromInstitutionData(
    Map<String, dynamic>? data,
  ) {
    final source = data ?? const <String, dynamic>{};
    return CounselorWorkflowSettings(
      directoryEnabled: (source['counselorDirectoryEnabled'] as bool?) ?? false,
      reassignmentEnabled:
          (source['counselorReassignmentEnabled'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toInstitutionPatch() {
    return <String, dynamic>{
      'counselorDirectoryEnabled': directoryEnabled,
      'counselorReassignmentEnabled': reassignmentEnabled,
    };
  }
}

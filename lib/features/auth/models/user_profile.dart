enum UserRole { individual, student, staff, counselor, institutionAdmin, other }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.individual:
        return 'Individual';
      case UserRole.student:
        return 'Student';
      case UserRole.staff:
        return 'Staff';
      case UserRole.counselor:
        return 'Counselor';
      case UserRole.institutionAdmin:
        return 'Institution Admin';
      case UserRole.other:
        return 'Other';
    }
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.onboardingCompletedRoles = const {},
    this.counselorSetupCompleted = false,
    this.counselorSetupData = const {},
    this.counselorPreferences = const {},
    this.institutionId,
    this.institutionName,
  });

  final String id;
  final String email;
  final String name;
  final UserRole role;
  final Map<String, int> onboardingCompletedRoles;
  final bool counselorSetupCompleted;
  final Map<String, dynamic> counselorSetupData;
  final Map<String, dynamic> counselorPreferences;
  final String? institutionId;
  final String? institutionName;

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role.name,
      'onboardingCompletedRoles': onboardingCompletedRoles,
      'counselorSetupCompleted': counselorSetupCompleted,
      'counselorSetupData': counselorSetupData,
      'counselorPreferences': counselorPreferences,
      'institutionId': institutionId,
      'institutionName': institutionName,
    };
  }

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    final persistedRole = data['role'] as String?;
    final normalizedRole = persistedRole == 'admin'
        ? UserRole.institutionAdmin.name
        : persistedRole;

    final completedRaw = data['onboardingCompletedRoles'];
    final completed = <String, int>{};
    if (completedRaw is Map) {
      for (final entry in completedRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is int) {
          completed[key] = value;
        } else if (value is num) {
          completed[key] = value.toInt();
        }
      }
    }

    final counselorSetupRaw = data['counselorSetupData'];
    final counselorSetup = <String, dynamic>{};
    if (counselorSetupRaw is Map) {
      for (final entry in counselorSetupRaw.entries) {
        counselorSetup[entry.key.toString()] = entry.value;
      }
    }

    final counselorPreferencesRaw = data['counselorPreferences'];
    final counselorPreferences = <String, dynamic>{};
    if (counselorPreferencesRaw is Map) {
      for (final entry in counselorPreferencesRaw.entries) {
        counselorPreferences[entry.key.toString()] = entry.value;
      }
    }

    return UserProfile(
      id: id,
      email: (data['email'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      role: UserRole.values.firstWhere(
        (role) => role.name == normalizedRole,
        orElse: () => UserRole.other,
      ),
      onboardingCompletedRoles: completed,
      counselorSetupCompleted:
          (data['counselorSetupCompleted'] as bool?) ?? false,
      counselorSetupData: counselorSetup,
      counselorPreferences: counselorPreferences,
      institutionId: data['institutionId'] as String?,
      institutionName: data['institutionName'] as String?,
    );
  }
}

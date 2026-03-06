import 'package:flutter/foundation.dart';

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
    this.aiAssistantPreferences = const {},
    this.institutionId,
    this.institutionName,
    this.phoneNumber,
    this.additionalPhoneNumber,
    this.phoneNumbers = const [],
  });

  final String id;
  final String email;
  final String name;
  final UserRole role;
  final Map<String, int> onboardingCompletedRoles;
  final bool counselorSetupCompleted;
  final Map<String, dynamic> counselorSetupData;
  final Map<String, dynamic> counselorPreferences;
  final Map<String, dynamic> aiAssistantPreferences;
  final String? institutionId;
  final String? institutionName;
  final String? phoneNumber;
  final String? additionalPhoneNumber;
  final List<String> phoneNumbers;

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role.name,
      'onboardingCompletedRoles': onboardingCompletedRoles,
      'counselorSetupCompleted': counselorSetupCompleted,
      'counselorSetupData': counselorSetupData,
      'counselorPreferences': counselorPreferences,
      'aiAssistantPreferences': aiAssistantPreferences,
      'institutionId': institutionId,
      'institutionName': institutionName,
      'phoneNumber': phoneNumber,
      'additionalPhoneNumber': additionalPhoneNumber,
      'phoneNumbers': phoneNumbers,
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

    final aiAssistantPreferencesRaw = data['aiAssistantPreferences'];
    final aiAssistantPreferences = <String, dynamic>{};
    if (aiAssistantPreferencesRaw is Map) {
      for (final entry in aiAssistantPreferencesRaw.entries) {
        aiAssistantPreferences[entry.key.toString()] = entry.value;
      }
    }

    final phoneNumbersRaw = data['phoneNumbers'];
    final phoneNumbers = <String>[];
    if (phoneNumbersRaw is List) {
      for (final value in phoneNumbersRaw) {
        final normalized = value?.toString().trim() ?? '';
        if (normalized.isNotEmpty) {
          phoneNumbers.add(normalized);
        }
      }
    }

    final mappedRole = UserRole.values.firstWhere(
      (role) => role.name == normalizedRole,
      orElse: () => UserRole.other,
    );
    if (kDebugMode &&
        mappedRole == UserRole.other &&
        normalizedRole != null &&
        normalizedRole.isNotEmpty &&
        normalizedRole != UserRole.other.name) {
      debugPrint(
        "[Auth][UserProfile] Unknown role '$normalizedRole' for user $id. "
        'Falling back to "other".',
      );
    }

    return UserProfile(
      id: id,
      email: (data['email'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      role: mappedRole,
      onboardingCompletedRoles: completed,
      counselorSetupCompleted:
          (data['counselorSetupCompleted'] as bool?) ?? false,
      counselorSetupData: counselorSetup,
      counselorPreferences: counselorPreferences,
      aiAssistantPreferences: aiAssistantPreferences,
      institutionId: data['institutionId'] as String?,
      institutionName: data['institutionName'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      additionalPhoneNumber: data['additionalPhoneNumber'] as String?,
      phoneNumbers: phoneNumbers,
    );
  }
}

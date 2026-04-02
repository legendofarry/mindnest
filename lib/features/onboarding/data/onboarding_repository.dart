import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/onboarding/data/onboarding_question_bank.dart';

class OnboardingRepository {
  OnboardingRepository({
    required FirebaseFirestore Function()? firestoreFactory,
    required AppAuthClient auth,
    required WindowsFirestoreRestClient windowsRest,
  }) : _firestoreFactory = firestoreFactory,
       _auth = auth,
       _windowsRest = windowsRest;

  final FirebaseFirestore Function()? _firestoreFactory;
  FirebaseFirestore? _cachedFirestore;
  final AppAuthClient _auth;
  final WindowsFirestoreRestClient _windowsRest;

  FirebaseFirestore get _firestore => _cachedFirestore ??=
      _firestoreFactory?.call() ??
      (throw StateError(
        'Native Firestore is disabled for Windows REST auth flows.',
      ));

  bool requiresQuestionnaire(UserProfile? profile) {
    if (profile == null) {
      return false;
    }
    if (profile.isCounselorRegistrationIntentPending) {
      return false;
    }
    if (!OnboardingQuestionBank.roleRequiresQuestionnaire(profile.role)) {
      return false;
    }
    final completedVersion = _completedVersionForRole(
      role: profile.role,
      completedRoles: profile.onboardingCompletedRoles,
    );
    return completedVersion < OnboardingQuestionBank.version;
  }

  Future<void> submitResponses({
    required UserRole role,
    required Map<String, dynamic> answers,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (!OnboardingQuestionBank.roleRequiresQuestionnaire(role)) {
      return;
    }

    final responseDocId =
        '${user.uid}_${role.name}_v${OnboardingQuestionBank.version}';
    final batch = _firestore.batch();
    final supportRaw = answers['support_preference'];
    final supportPreferences = supportRaw is List
        ? supportRaw.whereType<String>().toSet()
        : <String>{};
    final aiEnabled =
        supportPreferences.contains('ai_guidance') ||
        answers['ai_assist_enabled'] == true;
    final aiStyle = answers['ai_coach_style'] as String?;
    final aiCadence = answers['ai_checkin_cadence'] as String?;

    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      final existingUser =
          (await _windowsRest.getDocument('users/${user.uid}'))?.data ??
          const <String, dynamic>{};
      final completedRoles = Map<String, dynamic>.from(
        (existingUser['onboardingCompletedRoles'] as Map?) ??
            const <String, dynamic>{},
      );
      for (final completedRole
          in OnboardingQuestionBank.completionEquivalentRoles(role)) {
        completedRoles[completedRole.name] = OnboardingQuestionBank.version;
      }
      final existingAiPreferences = Map<String, dynamic>.from(
        (existingUser['aiAssistantPreferences'] as Map?) ??
            const <String, dynamic>{},
      );

      await _windowsRest.setDocument('onboarding_responses/$responseDocId', {
        'userId': user.uid,
        'role': role.name,
        'version': OnboardingQuestionBank.version,
        'answers': answers,
        'submittedAt': now,
      });
      await _windowsRest.setDocument('users/${user.uid}', {
        ...existingUser,
        'onboardingCompletedRoles': completedRoles,
        'onboardingLastCompletedRole': role.name,
        'onboardingUpdatedAt': now,
        'aiAssistantPreferences': {
          ...existingAiPreferences,
          'enabled': aiEnabled,
          'style': aiStyle,
          'checkInCadence': aiCadence,
          'updatedAt': now,
        },
        'updatedAt': now,
      });
      return;
    }

    final completedRoleUpdates = <String, Object?>{
      for (final completedRole
          in OnboardingQuestionBank.completionEquivalentRoles(role))
        'onboardingCompletedRoles.${completedRole.name}':
            OnboardingQuestionBank.version,
    };

    batch
        .set(_firestore.collection('onboarding_responses').doc(responseDocId), {
          'userId': user.uid,
          'role': role.name,
          'version': OnboardingQuestionBank.version,
          'answers': answers,
          'submittedAt': FieldValue.serverTimestamp(),
        });
    batch.update(_firestore.collection('users').doc(user.uid), {
      ...completedRoleUpdates,
      'onboardingLastCompletedRole': role.name,
      'onboardingUpdatedAt': FieldValue.serverTimestamp(),
      'aiAssistantPreferences': {
        'enabled': aiEnabled,
        'style': aiStyle,
        'checkInCadence': aiCadence,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  int _completedVersionForRole({
    required UserRole role,
    required Map<String, int> completedRoles,
  }) {
    var completedVersion = 0;
    for (final completedRole
        in OnboardingQuestionBank.completionEquivalentRoles(role)) {
      final roleVersion = completedRoles[completedRole.name] ?? 0;
      if (roleVersion > completedVersion) {
        completedVersion = roleVersion;
      }
    }
    return completedVersion;
  }
}

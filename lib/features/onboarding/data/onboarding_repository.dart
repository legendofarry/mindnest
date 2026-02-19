import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/onboarding/data/onboarding_question_bank.dart';

class OnboardingRepository {
  OnboardingRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  bool requiresQuestionnaire(UserProfile? profile) {
    if (profile == null) {
      return false;
    }
    if (!OnboardingQuestionBank.roleRequiresQuestionnaire(profile.role)) {
      return false;
    }
    final completedVersion =
        profile.onboardingCompletedRoles[profile.role.name] ?? 0;
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

    batch
        .set(_firestore.collection('onboarding_responses').doc(responseDocId), {
          'userId': user.uid,
          'role': role.name,
          'version': OnboardingQuestionBank.version,
          'answers': answers,
          'submittedAt': FieldValue.serverTimestamp(),
        });
    batch.update(_firestore.collection('users').doc(user.uid), {
      'onboardingCompletedRoles.${role.name}': OnboardingQuestionBank.version,
      'onboardingLastCompletedRole': role.name,
      'onboardingUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}

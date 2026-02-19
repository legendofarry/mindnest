import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class CounselorRepository {
  CounselorRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  bool requiresSetup(UserProfile? profile) {
    if (profile == null || profile.role != UserRole.counselor) {
      return false;
    }
    return !profile.counselorSetupCompleted;
  }

  Future<void> completeSetup({
    required String title,
    required String specialization,
    required int yearsExperience,
    required String sessionMode,
    required String timezone,
    required String bio,
    required List<String> languages,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data();
    final institutionId = (userData?['institutionId'] as String?) ?? '';
    final displayName =
        (userData?['name'] as String?) ?? user.displayName ?? '';
    if (institutionId.isEmpty) {
      throw Exception('Counselor must be linked to an institution.');
    }

    final trimmedTitle = title.trim();
    final trimmedSpecialization = specialization.trim();
    final trimmedMode = sessionMode.trim();
    final trimmedTimezone = timezone.trim();
    final trimmedBio = bio.trim();
    final cleanedLanguages = languages
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (trimmedTitle.length < 2) {
      throw Exception('Professional title is required.');
    }
    if (trimmedSpecialization.length < 2) {
      throw Exception('Specialization is required.');
    }
    if (yearsExperience < 0) {
      throw Exception('Years of experience is invalid.');
    }
    if (trimmedMode.isEmpty) {
      throw Exception('Session mode is required.');
    }
    if (trimmedTimezone.isEmpty) {
      throw Exception('Timezone is required.');
    }

    final counselorProfileRef = _firestore
        .collection('counselor_profiles')
        .doc(user.uid);
    final counselorProfileDoc = await counselorProfileRef.get();
    final existingRatingAverage =
        (counselorProfileDoc.data()?['ratingAverage'] as num?)?.toDouble() ??
        0.0;
    final existingRatingCount =
        (counselorProfileDoc.data()?['ratingCount'] as num?)?.toInt() ?? 0;

    final counselorData = <String, dynamic>{
      'institutionId': institutionId,
      'displayName': displayName,
      'title': trimmedTitle,
      'specialization': trimmedSpecialization,
      'yearsExperience': yearsExperience,
      'sessionMode': trimmedMode,
      'timezone': trimmedTimezone,
      'bio': trimmedBio,
      'languages': cleanedLanguages,
      'ratingAverage': existingRatingAverage,
      'ratingCount': existingRatingCount,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    batch.update(_firestore.collection('users').doc(user.uid), {
      'counselorSetupCompleted': true,
      'counselorSetupData': {
        ...counselorData,
        'completedAt': FieldValue.serverTimestamp(),
      },
      'counselorPreferences': {
        'defaultSessionMinutes': 50,
        'breakBetweenSessionsMins': 10,
        'allowDirectBooking': true,
        'autoApproveFollowUps': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(counselorProfileRef, {
      ...counselorData,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> updateProfileAndSettings({
    required String displayName,
    required String title,
    required String specialization,
    required int yearsExperience,
    required String sessionMode,
    required String timezone,
    required String bio,
    required List<String> languages,
    required bool isActive,
    required int defaultSessionMinutes,
    required int breakBetweenSessionsMins,
    required bool allowDirectBooking,
    required bool autoApproveFollowUps,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();
    final userData = userDoc.data();
    if (userData == null) {
      throw Exception('User profile not found.');
    }

    final institutionId = (userData['institutionId'] as String?) ?? '';
    if (institutionId.isEmpty) {
      throw Exception('Counselor must be linked to an institution.');
    }

    final trimmedName = displayName.trim();
    final trimmedTitle = title.trim();
    final trimmedSpecialization = specialization.trim();
    final trimmedMode = sessionMode.trim();
    final trimmedTimezone = timezone.trim();
    final trimmedBio = bio.trim();
    final cleanedLanguages = languages
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (trimmedName.length < 2) {
      throw Exception('Display name is required.');
    }
    if (trimmedTitle.length < 2) {
      throw Exception('Professional title is required.');
    }
    if (trimmedSpecialization.length < 2) {
      throw Exception('Specialization is required.');
    }
    if (yearsExperience < 0 || yearsExperience > 60) {
      throw Exception('Years of experience must be between 0 and 60.');
    }
    if (trimmedMode.isEmpty) {
      throw Exception('Session mode is required.');
    }
    if (trimmedTimezone.isEmpty) {
      throw Exception('Timezone is required.');
    }
    if (defaultSessionMinutes < 15 || defaultSessionMinutes > 120) {
      throw Exception('Default session must be between 15 and 120 minutes.');
    }
    if (breakBetweenSessionsMins < 0 || breakBetweenSessionsMins > 60) {
      throw Exception('Break between sessions must be between 0 and 60.');
    }

    final counselorProfileRef = _firestore
        .collection('counselor_profiles')
        .doc(user.uid);
    final counselorProfileDoc = await counselorProfileRef.get();
    final existingRatingAverage =
        (counselorProfileDoc.data()?['ratingAverage'] as num?)?.toDouble() ??
        0.0;
    final existingRatingCount =
        (counselorProfileDoc.data()?['ratingCount'] as num?)?.toInt() ?? 0;

    final existingSetup =
        (userData['counselorSetupData'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    final counselorData = <String, dynamic>{
      'institutionId': institutionId,
      'displayName': trimmedName,
      'title': trimmedTitle,
      'specialization': trimmedSpecialization,
      'yearsExperience': yearsExperience,
      'sessionMode': trimmedMode,
      'timezone': trimmedTimezone,
      'bio': trimmedBio,
      'languages': cleanedLanguages,
      'ratingAverage': existingRatingAverage,
      'ratingCount': existingRatingCount,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final preferences = <String, dynamic>{
      'defaultSessionMinutes': defaultSessionMinutes,
      'breakBetweenSessionsMins': breakBetweenSessionsMins,
      'allowDirectBooking': allowDirectBooking,
      'autoApproveFollowUps': autoApproveFollowUps,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    batch.set(counselorProfileRef, {
      ...counselorData,
      if (!counselorProfileDoc.exists)
        'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.update(userRef, {
      'name': trimmedName,
      'counselorSetupCompleted': true,
      'counselorSetupData': {
        ...counselorData,
        'completedAt':
            existingSetup['completedAt'] ?? FieldValue.serverTimestamp(),
      },
      'counselorPreferences': preferences,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}

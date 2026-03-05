import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mindnest/features/auth/data/auth_session_manager.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class AuthRepository {
  AuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : _auth = auth,
       _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.userChanges();

  User? get currentAuthUser => _auth.currentUser;

  Stream<UserProfile?> userProfileChanges(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return UserProfile.fromMap(doc.id, doc.data()!);
    });
  }

  Future<void> registerIndividual({
    required String name,
    required String email,
    required String password,
  }) async {
    await _registerWithProfile(
      name: name,
      email: email,
      password: password,
      role: UserRole.individual,
    );
  }

  Future<void> registerInstitutionAdmin({
    required String name,
    required String email,
    required String password,
    required String institutionId,
    required String institutionName,
  }) async {
    await _registerWithProfile(
      name: name,
      email: email,
      password: password,
      role: UserRole.institutionAdmin,
      institutionId: institutionId,
      institutionName: institutionName,
    );
  }

  Future<void> setCurrentUserAsIndividual() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    await _firestore.collection('users').doc(user.uid).update({
      'role': UserRole.individual.name,
      'institutionId': null,
      'institutionName': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _registerWithProfile({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? institutionId,
    String? institutionName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = credential.user;

    if (user == null) {
      throw Exception('Unable to create user account.');
    }

    await user.updateDisplayName(name.trim());
    await user.sendEmailVerification();

    final profile = UserProfile(
      id: user.uid,
      email: user.email ?? normalizedEmail,
      name: name.trim(),
      role: role,
      institutionId: institutionId,
      institutionName: institutionName,
    );

    await _firestore.collection('users').doc(user.uid).set({
      ...profile.toMap(),
      'onboardingCompletedRoles': <String, int>{},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (kIsWeb) {
      await _auth.setPersistence(
        rememberMe ? Persistence.LOCAL : Persistence.SESSION,
      );
    }
    final credential = await _auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw Exception('Unable to sign in.');
    }

    await _ensureProfileExists(user);
    await AuthSessionManager.markLogin(rememberMe: rememberMe);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await AuthSessionManager.clear();
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> changePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
  }

  Future<Map<String, dynamic>> exportCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final onboarding = await _firestore
        .collection('onboarding_responses')
        .where('userId', isEqualTo: user.uid)
        .get();
    final studentAppointments = await _firestore
        .collection('appointments')
        .where('studentId', isEqualTo: user.uid)
        .get();
    final counselorAppointments = await _firestore
        .collection('appointments')
        .where('counselorId', isEqualTo: user.uid)
        .get();
    final notifications = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .get();
    final goals = await _firestore
        .collection('care_goals')
        .where('studentId', isEqualTo: user.uid)
        .get();
    final privacy = await _firestore
        .collection('user_privacy_settings')
        .doc(user.uid)
        .get();

    List<Map<String, dynamic>> mapDocs(
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) {
      return snapshot.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList(growable: false);
    }

    return <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'user': userDoc.data() ?? const <String, dynamic>{},
      'onboardingResponses': mapDocs(onboarding),
      'studentAppointments': mapDocs(studentAppointments),
      'counselorAppointments': mapDocs(counselorAppointments),
      'notifications': mapDocs(notifications),
      'careGoals': mapDocs(goals),
      'privacySettings': privacy.data() ?? const <String, dynamic>{},
    };
  }

  Future<void> deleteCurrentAccount() async {
    if (!kDebugMode) {
      throw Exception('Delete account is enabled for development only.');
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final uid = user.uid;
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final institutionId = (userDoc.data()?['institutionId'] as String?)?.trim();

    await _deleteWhere(
      collectionPath: 'notifications',
      field: 'userId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'user_push_tokens',
      field: 'userId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'onboarding_responses',
      field: 'userId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'institution_members',
      field: 'userId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'mood_entries',
      field: 'userId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'mood_events',
      field: 'userId',
      value: uid,
    );

    await _deleteWhere(
      collectionPath: 'appointments',
      field: 'studentId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'appointments',
      field: 'counselorId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'care_goals',
      field: 'studentId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'care_goals',
      field: 'counselorId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'counselor_ratings',
      field: 'studentId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'counselor_ratings',
      field: 'counselorId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'counselor_public_ratings',
      field: 'studentId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'counselor_public_ratings',
      field: 'counselorId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'counselor_availability',
      field: 'counselorId',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'user_invites',
      field: 'inviteeUid',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'user_invites',
      field: 'invitedBy',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'institution_membership_audit',
      field: 'actorUid',
      value: uid,
    );
    await _deleteWhere(
      collectionPath: 'institution_membership_audit',
      field: 'targetUserId',
      value: uid,
    );

    await _deleteCollectionGroupWhere(
      groupPath: 'participants',
      field: 'userId',
      value: uid,
    );
    await _deleteCollectionGroupWhere(
      groupPath: 'mic_requests',
      field: 'userId',
      value: uid,
    );
    await _deleteCollectionGroupWhere(
      groupPath: 'comments',
      field: 'userId',
      value: uid,
    );
    await _deleteCollectionGroupWhere(
      groupPath: 'reactions',
      field: 'userId',
      value: uid,
    );
    await _deleteCollectionGroupWhere(
      groupPath: 'comment_reports',
      field: 'userId',
      value: uid,
    );

    final hostedSessions = await _firestore
        .collection('live_sessions')
        .where('createdBy', isEqualTo: uid)
        .get();
    for (final session in hostedSessions.docs) {
      for (final subCollection in const <String>[
        'participants',
        'mic_requests',
        'comments',
        'reactions',
        'comment_reports',
      ]) {
        await _deleteCollectionPath(
          'live_sessions/${session.id}/$subCollection',
        );
      }
      await session.reference.delete();
    }

    if (institutionId != null && institutionId.isNotEmpty) {
      await _deleteDocIfExists('institution_members', '${institutionId}_$uid');
    }

    await _deleteDocIfExists('counselor_profiles', uid);
    await _deleteDocIfExists('user_privacy_settings', uid);
    await _deleteDocIfExists('user_notification_settings', uid);
    await _deleteDocIfExists('users', uid);

    try {
      await user.delete();
      await AuthSessionManager.clear();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        throw Exception(
          'For security, log in again before deleting your account.',
        );
      }
      rethrow;
    }
  }

  Future<void> _deleteDocIfExists(String collectionPath, String docId) async {
    final ref = _firestore.collection(collectionPath).doc(docId);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      return;
    }
    await ref.delete();
  }

  Future<void> _deleteWhere({
    required String collectionPath,
    required String field,
    required Object value,
    int batchSize = 200,
  }) async {
    while (true) {
      final snapshot = await _firestore
          .collection(collectionPath)
          .where(field, isEqualTo: value)
          .limit(batchSize)
          .get();
      if (snapshot.docs.isEmpty) {
        break;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < batchSize) {
        break;
      }
    }
  }

  Future<void> _deleteCollectionGroupWhere({
    required String groupPath,
    required String field,
    required Object value,
    int batchSize = 200,
  }) async {
    while (true) {
      final snapshot = await _firestore
          .collectionGroup(groupPath)
          .where(field, isEqualTo: value)
          .limit(batchSize)
          .get();
      if (snapshot.docs.isEmpty) {
        break;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < batchSize) {
        break;
      }
    }
  }

  Future<void> _deleteCollectionPath(
    String collectionPath, {
    int batchSize = 200,
  }) async {
    while (true) {
      final snapshot = await _firestore
          .collection(collectionPath)
          .limit(batchSize)
          .get();
      if (snapshot.docs.isEmpty) {
        break;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < batchSize) {
        break;
      }
    }
  }

  Future<void> _ensureProfileExists(User user) async {
    final userDoc = _firestore.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();
    if (snapshot.exists) {
      return;
    }

    await userDoc.set({
      'email': user.email ?? '',
      'name': user.displayName ?? '',
      'role': UserRole.individual.name,
      'onboardingCompletedRoles': <String, int>{},
      'institutionId': null,
      'institutionName': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

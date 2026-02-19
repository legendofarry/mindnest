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

  Future<void> setCurrentUserRole(UserRole role) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    await _firestore.collection('users').doc(user.uid).update({
      'role': role.name,
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
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final uid = user.uid;
    final batch = _firestore.batch();
    batch.delete(_firestore.collection('users').doc(uid));
    batch.delete(_firestore.collection('user_privacy_settings').doc(uid));
    batch.delete(_firestore.collection('user_notification_settings').doc(uid));

    final memberships = await _firestore
        .collection('institution_members')
        .where('userId', isEqualTo: uid)
        .get();
    for (final doc in memberships.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

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

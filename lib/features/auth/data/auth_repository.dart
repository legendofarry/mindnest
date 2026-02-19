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

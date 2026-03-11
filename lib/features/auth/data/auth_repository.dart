import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  static const _kenyaPrefix = '+254';

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
    required String phoneNumber,
    String? additionalPhoneNumber,
    bool counselorRegistrationIntent = false,
  }) async {
    await _registerWithProfile(
      name: name,
      email: email,
      password: password,
      role: UserRole.individual,
      phoneNumber: phoneNumber,
      additionalPhoneNumber: additionalPhoneNumber,
      registrationIntent: counselorRegistrationIntent
          ? UserProfile.counselorRegistrationIntent
          : null,
    );
  }

  Future<void> registerInstitutionAdmin({
    required String name,
    required String email,
    required String password,
    required String institutionId,
    required String institutionName,
    String? phoneNumber,
    String? additionalPhoneNumber,
  }) async {
    await _registerWithProfile(
      name: name,
      email: email,
      password: password,
      role: UserRole.institutionAdmin,
      institutionId: institutionId,
      institutionName: institutionName,
      phoneNumber: phoneNumber,
      additionalPhoneNumber: additionalPhoneNumber,
    );
  }

  Future<bool> isPhoneNumberAvailableForRegistration(String phoneNumber) async {
    final normalizedPhoneNumber = _normalizeRequiredKenyaPhone(phoneNumber);
    final registryRef = _firestore
        .collection('phone_number_registry')
        .doc(_phoneRegistryDocId(normalizedPhoneNumber));
    final snapshot = await registryRef.get();
    if (!snapshot.exists) {
      return true;
    }

    final ownerUid = ((snapshot.data()?['uid'] as String?) ?? '').trim();
    if (ownerUid.isEmpty) {
      return true;
    }

    final currentUid = _auth.currentUser?.uid;
    if (currentUid != null && currentUid == ownerUid) {
      return true;
    }
    return false;
  }

  Future<void> setCurrentUserAsIndividual() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final userDoc = _firestore.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();
    if (!snapshot.exists) {
      await userDoc.set({
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'role': UserRole.individual.name,
        'onboardingCompletedRoles': <String, int>{},
        'institutionId': null,
        'institutionName': null,
        'phoneNumber': '',
        'additionalPhoneNumber': null,
        'phoneNumbers': const <String>[],
        'registrationIntent': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    await userDoc.update({
      'role': UserRole.individual.name,
      'institutionId': null,
      'institutionName': null,
      'registrationIntent': null,
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
    String? phoneNumber,
    String? additionalPhoneNumber,
    String? registrationIntent,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhoneNumber = _normalizeRequiredKenyaPhone(phoneNumber);
    final normalizedAdditionalPhoneNumber = _normalizeOptionalKenyaPhone(
      additionalPhoneNumber,
    );
    if (normalizedAdditionalPhoneNumber == normalizedPhoneNumber) {
      throw Exception(
        'Additional mobile number must be different from primary mobile number.',
      );
    }
    final phoneCandidates = _buildPhoneCandidates(
      primaryPhone: normalizedPhoneNumber,
      additionalPhone: normalizedAdditionalPhoneNumber,
    );

    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = credential.user;

    if (user == null) {
      throw Exception('Unable to create user account.');
    }

    await user.updateDisplayName(name.trim());

    final profile = UserProfile(
      id: user.uid,
      email: user.email ?? normalizedEmail,
      name: name.trim(),
      role: role,
      institutionId: institutionId,
      institutionName: institutionName,
      phoneNumber: normalizedPhoneNumber,
      additionalPhoneNumber: normalizedAdditionalPhoneNumber,
      phoneNumbers: phoneCandidates,
      registrationIntent: registrationIntent,
    );

    try {
      await _firestore.runTransaction((transaction) async {
        final phoneRegistryRefs = _phoneRegistryRefsForRegistration(
          primaryPhoneNumber: normalizedPhoneNumber,
          additionalPhoneNumber: normalizedAdditionalPhoneNumber,
        );

        for (final ref in phoneRegistryRefs) {
          final snapshot = await transaction.get(ref);
          if (!snapshot.exists) {
            continue;
          }
          final ownerUid = (snapshot.data()?['uid'] as String?) ?? '';
          if (ownerUid != user.uid) {
            final claimedPhone =
                (snapshot.data()?['phoneNumber'] as String?) ?? ref.id;
            throw _PhoneNumberAlreadyInUseException(
              'The mobile number $claimedPhone is already linked to another account.',
            );
          }
        }

        transaction.set(_firestore.collection('users').doc(user.uid), {
          ...profile.toMap(),
          'onboardingCompletedRoles': <String, int>{},
          'createdAt': FieldValue.serverTimestamp(),
        });

        for (final ref in phoneRegistryRefs) {
          transaction.set(ref, {
            'uid': user.uid,
            'phoneNumber': _phoneFromRegistryDocId(ref.id),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on _PhoneNumberAlreadyInUseException catch (error) {
      try {
        await user.delete();
      } catch (_) {
        // If rollback auth deletion fails, keep a user-facing error.
      }
      throw Exception(error.message);
    }

    await user.sendEmailVerification();
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
    await _backfillPhoneRegistryForCurrentUser(user.uid);
    await AuthSessionManager.markLogin(rememberMe: rememberMe);
  }

  Future<UserCredential> signInWithGoogle({bool rememberMe = true}) async {
    if (kIsWeb) {
      await _auth.setPersistence(
        rememberMe ? Persistence.LOCAL : Persistence.SESSION,
      );
      final provider = GoogleAuthProvider()
        ..setCustomParameters(<String, String>{'prompt': 'select_account'});
      final credential = await _auth.signInWithPopup(provider);
      final user = credential.user;
      if (user == null) {
        throw Exception('Unable to complete Google sign-in.');
      }
      await AuthSessionManager.markLogin(rememberMe: rememberMe);
      await _ensureProfileExists(user);
      return credential;
    }

    final googleSignIn = GoogleSignIn(scopes: const <String>['email']);
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled.');
    }
    final googleAuth = await googleUser.authentication;
    final providerCredential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    try {
      final credential =
          await _auth.signInWithCredential(providerCredential);
      final user = credential.user;
      if (user == null) {
        throw Exception('Unable to complete Google sign-in.');
      }
      await AuthSessionManager.markLogin(rememberMe: rememberMe);
      await _ensureProfileExists(user);
      return credential;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'account-exists-with-different-credential') {
        throw Exception(
          'This email already exists with another sign-in method. '
          'Sign in with that method, then link Google in your profile settings.',
        );
      }
      rethrow;
    }
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

  Future<void> updateAccountProfile({
    required String name,
    required String phoneNumber,
    String? additionalPhoneNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final trimmedName = name.trim();
    if (trimmedName.length < 2) {
      throw Exception('Please enter your full name.');
    }

    final normalizedPrimary = _normalizeRequiredKenyaPhone(phoneNumber);
    final normalizedAdditional =
        _normalizeOptionalKenyaPhone(additionalPhoneNumber);
    if (normalizedAdditional == normalizedPrimary) {
      throw Exception(
        'Additional mobile number must be different from primary mobile number.',
      );
    }
    final phoneCandidates = _buildPhoneCandidates(
      primaryPhone: normalizedPrimary,
      additionalPhone: normalizedAdditional,
    );

    final userRef = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        throw Exception('Profile not found.');
      }
      final existing = snapshot.data() ?? const <String, dynamic>{};

      final previousPhones = <String>{};
      void addPrevious(String? raw) {
        final normalized = _normalizeOptionalKenyaPhone(raw);
        if (normalized != null) {
          previousPhones.add(normalized);
        }
      }

      addPrevious(existing['phoneNumber'] as String?);
      addPrevious(existing['additionalPhoneNumber'] as String?);
      final rawPhoneList = existing['phoneNumbers'];
      if (rawPhoneList is List) {
        for (final value in rawPhoneList) {
          addPrevious(value?.toString());
        }
      }

      final registryRefs = _phoneRegistryRefsForRegistration(
        primaryPhoneNumber: normalizedPrimary,
        additionalPhoneNumber: normalizedAdditional,
      );

      for (final ref in registryRefs) {
        final registrySnapshot = await transaction.get(ref);
        if (registrySnapshot.exists) {
          final ownerUid = (registrySnapshot.data()?['uid'] as String?) ?? '';
          if (ownerUid.isNotEmpty && ownerUid != user.uid) {
            final claimedPhone =
                (registrySnapshot.data()?['phoneNumber'] as String?) ??
                _phoneFromRegistryDocId(ref.id);
            throw _PhoneNumberAlreadyInUseException(
              'The mobile number $claimedPhone is already linked to another account.',
            );
          }
        }
      }

      transaction.update(userRef, {
        'name': trimmedName,
        'phoneNumber': normalizedPrimary,
        'additionalPhoneNumber': normalizedAdditional,
        'phoneNumbers': phoneCandidates,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final ref in registryRefs) {
        transaction.set(ref, {
          'uid': user.uid,
          'phoneNumber': _phoneFromRegistryDocId(ref.id),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final registryIds = registryRefs.map((ref) => ref.id).toSet();
      for (final phone in previousPhones) {
        final docId = _phoneRegistryDocId(phone);
        if (registryIds.contains(docId)) continue;
        final staleRef =
            _firestore.collection('phone_number_registry').doc(docId);
        final staleSnapshot = await transaction.get(staleRef);
        final ownerUid = (staleSnapshot.data()?['uid'] as String?) ?? '';
        if (ownerUid == user.uid) {
          transaction.delete(staleRef);
        }
      }
    });

    await user.updateDisplayName(trimmedName);
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
      'phoneNumber': '',
      'additionalPhoneNumber': null,
      'phoneNumbers': const <String>[],
      'registrationIntent': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _normalizeRequiredKenyaPhone(String? value) {
    final normalized = _normalizeOptionalKenyaPhone(value);
    if (normalized == null) {
      throw Exception('Primary mobile number is required.');
    }
    return normalized;
  }

  String? _normalizeOptionalKenyaPhone(String? value) {
    var raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }

    if (raw == _kenyaPrefix) {
      return null;
    }

    if (!raw.startsWith('+')) {
      raw = '+$raw';
    }

    if (!RegExp(r'^\+254\d{9}$').hasMatch(raw)) {
      throw Exception(
        'Use a valid Kenya mobile number in +254 format (example: +254712345678).',
      );
    }

    return raw;
  }

  List<String> _buildPhoneCandidates({
    required String primaryPhone,
    String? additionalPhone,
  }) {
    final candidates = <String>{primaryPhone, primaryPhone.substring(1)};
    if (additionalPhone != null && additionalPhone.isNotEmpty) {
      candidates.add(additionalPhone);
      candidates.add(additionalPhone.substring(1));
    }
    return candidates.toList(growable: false);
  }

  String _phoneRegistryDocId(String phoneE164) {
    return phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _phoneFromRegistryDocId(String docId) {
    return '+$docId';
  }

  List<DocumentReference<Map<String, dynamic>>>
  _phoneRegistryRefsForRegistration({
    required String primaryPhoneNumber,
    String? additionalPhoneNumber,
  }) {
    final keys = <String>{
      _phoneRegistryDocId(primaryPhoneNumber),
      if (additionalPhoneNumber != null && additionalPhoneNumber.isNotEmpty)
        _phoneRegistryDocId(additionalPhoneNumber),
    };
    return keys
        .map((key) => _firestore.collection('phone_number_registry').doc(key))
        .toList(growable: false);
  }

  Future<void> _backfillPhoneRegistryForCurrentUser(String uid) async {
    try {
      final userSnapshot = await _firestore.collection('users').doc(uid).get();
      final data = userSnapshot.data();
      if (data == null) {
        return;
      }

      final phones = <String>{};
      final primary = _normalizeOptionalKenyaPhone(
        data['phoneNumber'] as String?,
      );
      if (primary != null) {
        phones.add(primary);
      }
      final additional = _normalizeOptionalKenyaPhone(
        data['additionalPhoneNumber'] as String?,
      );
      if (additional != null) {
        phones.add(additional);
      }

      final rawPhoneList = data['phoneNumbers'];
      if (rawPhoneList is List) {
        for (final value in rawPhoneList) {
          final raw = value?.toString().trim() ?? '';
          if (raw.isEmpty) {
            continue;
          }
          final normalized = raw.startsWith('+')
              ? _normalizeOptionalKenyaPhone(raw)
              : _normalizeOptionalKenyaPhone('+$raw');
          if (normalized != null) {
            phones.add(normalized);
          }
        }
      }

      if (phones.isEmpty) {
        return;
      }

      final refs = phones
          .map(
            (phone) => _firestore
                .collection('phone_number_registry')
                .doc(_phoneRegistryDocId(phone)),
          )
          .toList(growable: false);

      await _firestore.runTransaction((transaction) async {
        for (final ref in refs) {
          final snapshot = await transaction.get(ref);
          if (snapshot.exists) {
            final ownerUid = (snapshot.data()?['uid'] as String?) ?? '';
            if (ownerUid != uid) {
              continue;
            }
          }
          transaction.set(ref, {
            'uid': uid,
            'phoneNumber': _phoneFromRegistryDocId(ref.id),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {
      // Registry backfill should not block authentication.
    }
  }
}

class _PhoneNumberAlreadyInUseException implements Exception {
  const _PhoneNumberAlreadyInUseException(this.message);

  final String message;
}

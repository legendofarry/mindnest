import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_session_manager.dart';
import 'package:mindnest/features/auth/models/app_auth_user.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class AuthRepository {
  AuthRepository({
    required AppAuthClient auth,
    required FirebaseFirestore Function()? firestoreFactory,
    required WindowsFirestoreRestClient windowsRest,
  }) : _auth = auth,
       _firestoreFactory = firestoreFactory,
       _windowsRest = windowsRest;

  final AppAuthClient _auth;
  final FirebaseFirestore Function()? _firestoreFactory;
  FirebaseFirestore? _cachedFirestore;
  final WindowsFirestoreRestClient _windowsRest;
  static const _kenyaPrefix = '+254';
  static const Duration _windowsPollInterval = Duration(seconds: 15);

  bool get _useWindowsPollingWorkaround =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  FirebaseFirestore get _firestore => _cachedFirestore ??=
      _firestoreFactory?.call() ??
      (throw StateError(
        'Native Firestore is disabled for Windows REST auth flows.',
      ));

  Stream<AppAuthUser?> authStateChanges() {
    if (!_useWindowsPollingWorkaround) {
      return _auth.userChanges();
    }

    return _buildWindowsPollingStream<AppAuthUser?>(
      load: () async => _auth.currentUser,
      signature: (user) => user == null
          ? 'signed-out'
          : '${user.uid}|${user.email}|${user.emailVerified}|${user.displayName ?? ''}|${user.phoneNumber ?? ''}',
    );
  }

  AppAuthUser? get currentAuthUser => _auth.currentUser;

  Stream<UserProfile?> userProfileChanges(String userId) {
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<UserProfile?>(
        load: () async => _fetchUserProfile(userId),
        signature: (profile) => profile == null
            ? 'missing'
            : '${profile.id}|${profile.email}|${profile.name}|${profile.role.name}|${profile.institutionId ?? ''}|${profile.institutionName ?? ''}|${profile.phoneNumber ?? ''}|${profile.additionalPhoneNumber ?? ''}|${profile.registrationIntent ?? ''}|${profile.phoneNumbers.join(',')}',
      );
    }

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
    final registryDocId = _phoneRegistryDocId(normalizedPhoneNumber);
    final data = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument(
            'phone_number_registry/$registryDocId',
          ))?.data
        : (await _firestore
                  .collection('phone_number_registry')
                  .doc(registryDocId)
                  .get())
              .data();
    if (data == null) {
      return true;
    }

    final ownerUid = ((data['uid'] as String?) ?? '').trim();
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

    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument('users/${user.uid}');
      if (existing == null) {
        await _windowsRest.setDocument('users/${user.uid}', {
          'email': user.email,
          'name': user.displayName ?? '',
          'role': UserRole.individual.name,
          'onboardingCompletedRoles': <String, int>{},
          'institutionId': null,
          'institutionName': null,
          'phoneNumber': '',
          'additionalPhoneNumber': null,
          'phoneNumbers': const <String>[],
          'registrationIntent': null,
          'createdAt': DateTime.now().toUtc(),
          'updatedAt': DateTime.now().toUtc(),
        });
        return;
      }

      await _windowsRest.updateDocument('users/${user.uid}', {
        'role': UserRole.individual.name,
        'institutionId': null,
        'institutionName': null,
        'registrationIntent': null,
        'updatedAt': DateTime.now().toUtc(),
      });
      return;
    }

    final userDoc = _firestore.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();
    if (!snapshot.exists) {
      await userDoc.set({
        'email': user.email,
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
      displayName: name.trim(),
    );
    final user = credential.user;

    final profile = UserProfile(
      id: user.uid,
      email: user.email,
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
      if (kUseWindowsRestAuth) {
        final now = DateTime.now().toUtc();
        final phoneRegistryRefs = _phoneRegistryRefsForRegistration(
          primaryPhoneNumber: normalizedPhoneNumber,
          additionalPhoneNumber: normalizedAdditionalPhoneNumber,
        );

        for (final ref in phoneRegistryRefs) {
          final snapshot = await _windowsRest.getDocument(
            'phone_number_registry/${ref.id}',
          );
          if (snapshot == null) {
            continue;
          }
          final ownerUid = (snapshot.data['uid'] as String?) ?? '';
          if (ownerUid != user.uid) {
            final claimedPhone =
                (snapshot.data['phoneNumber'] as String?) ?? ref.id;
            throw _PhoneNumberAlreadyInUseException(
              'The mobile number $claimedPhone is already linked to another account.',
            );
          }
        }

        await _windowsRest.setDocument('users/${user.uid}', {
          ...profile.toMap(),
          'onboardingCompletedRoles': <String, int>{},
          'createdAt': now,
          'updatedAt': now,
        });

        for (final ref in phoneRegistryRefs) {
          await _windowsRest.setDocument('phone_number_registry/${ref.id}', {
            'uid': user.uid,
            'phoneNumber': _phoneFromRegistryDocId(ref.id),
            'createdAt': now,
            'updatedAt': now,
          });
        }
        await _auth.sendEmailVerification();
        return;
      }

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
      throw Exception(error.message);
    }

    await _auth.sendEmailVerification();
  }

  Future<void> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (kIsWeb) {
      await fb.FirebaseAuth.instance.setPersistence(
        rememberMe ? fb.Persistence.LOCAL : fb.Persistence.SESSION,
      );
    }
    final credential = await _auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = credential.user;

    if (_useWindowsPollingWorkaround) {
      await _ensureWindowsLoginProfileExists(user);
      await AuthSessionManager.markLogin(rememberMe: rememberMe);
      return;
    }

    await AuthSessionManager.markLogin(rememberMe: rememberMe);
    await _ensureProfileExists(user);
    await _backfillPhoneRegistryForCurrentUser(user.uid);
  }

  Future<AppAuthSignInResult> signInWithGoogle({bool rememberMe = true}) async {
    if (kUseWindowsRestAuth) {
      final credential = await _auth.signInWithGoogle(
        existingAccountsOnly: true,
      );
      await _ensureWindowsLoginProfileExists(credential.user);
      await AuthSessionManager.markLogin(rememberMe: rememberMe);
      return credential;
    }

    if (kIsWeb) {
      final auth = fb.FirebaseAuth.instance;
      await auth.setPersistence(
        rememberMe ? fb.Persistence.LOCAL : fb.Persistence.SESSION,
      );
      final provider = fb.GoogleAuthProvider()
        ..setCustomParameters(<String, String>{'prompt': 'select_account'});
      final credential = await auth.signInWithPopup(provider);
      final user = credential.user;
      if (user == null) {
        throw Exception('Unable to complete Google sign-in.');
      }
      await AuthSessionManager.markLogin(rememberMe: rememberMe);
      await _ensureProfileExists(
        AppAuthUser(
          uid: user.uid,
          email: user.email ?? '',
          emailVerified: user.emailVerified,
          displayName: user.displayName,
          phoneNumber: user.phoneNumber,
          creationTime: user.metadata.creationTime?.toUtc(),
        ),
      );
      return AppAuthSignInResult(
        user: AppAuthUser(
          uid: user.uid,
          email: user.email ?? '',
          emailVerified: user.emailVerified,
          displayName: user.displayName,
          phoneNumber: user.phoneNumber,
          creationTime: user.metadata.creationTime?.toUtc(),
        ),
      );
    }

    final googleSignIn = GoogleSignIn(scopes: const <String>['email']);
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled.');
    }
    final googleAuth = await googleUser.authentication;
    final providerCredential = fb.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    try {
      final auth = fb.FirebaseAuth.instance;
      final credential = await auth.signInWithCredential(providerCredential);
      final user = credential.user;
      if (user == null) {
        throw Exception('Unable to complete Google sign-in.');
      }
      await AuthSessionManager.markLogin(rememberMe: rememberMe);
      final mappedUser = AppAuthUser(
        uid: user.uid,
        email: user.email ?? '',
        emailVerified: user.emailVerified,
        displayName: user.displayName,
        phoneNumber: user.phoneNumber,
        creationTime: user.metadata.creationTime?.toUtc(),
      );
      await _ensureProfileExists(mappedUser);
      return AppAuthSignInResult(user: mappedUser);
    } on fb.FirebaseAuthException catch (error) {
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
    return _auth.sendPasswordResetEmail(email.trim().toLowerCase());
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await _auth.sendEmailVerification();
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
    final normalizedAdditional = _normalizeOptionalKenyaPhone(
      additionalPhoneNumber,
    );
    if (normalizedAdditional == normalizedPrimary) {
      throw Exception(
        'Additional mobile number must be different from primary mobile number.',
      );
    }
    final phoneCandidates = _buildPhoneCandidates(
      primaryPhone: normalizedPrimary,
      additionalPhone: normalizedAdditional,
    );

    if (kUseWindowsRestAuth) {
      final existing = (await _windowsRest.getDocument(
        'users/${user.uid}',
      ))?.data;
      if (existing == null) {
        throw Exception('Profile not found.');
      }

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
        final registrySnapshot = await _windowsRest.getDocument(
          'phone_number_registry/${ref.id}',
        );
        if (registrySnapshot == null) {
          continue;
        }
        final ownerUid = (registrySnapshot.data['uid'] as String?) ?? '';
        if (ownerUid.isNotEmpty && ownerUid != user.uid) {
          final claimedPhone =
              (registrySnapshot.data['phoneNumber'] as String?) ??
              _phoneFromRegistryDocId(ref.id);
          throw _PhoneNumberAlreadyInUseException(
            'The mobile number $claimedPhone is already linked to another account.',
          );
        }
      }

      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('users/${user.uid}', {
        ...existing,
        'name': trimmedName,
        'phoneNumber': normalizedPrimary,
        'additionalPhoneNumber': normalizedAdditional,
        'phoneNumbers': phoneCandidates,
        'updatedAt': now,
      });

      final registryIds = <String>{};
      for (final ref in registryRefs) {
        registryIds.add(ref.id);
        final existingRegistry = await _windowsRest.getDocument(
          'phone_number_registry/${ref.id}',
        );
        await _windowsRest.setDocument('phone_number_registry/${ref.id}', {
          ...?existingRegistry?.data,
          'uid': user.uid,
          'phoneNumber': _phoneFromRegistryDocId(ref.id),
          'updatedAt': now,
          'createdAt': existingRegistry?.data['createdAt'] ?? now,
        });
      }

      for (final phone in previousPhones) {
        final docId = _phoneRegistryDocId(phone);
        if (registryIds.contains(docId)) {
          continue;
        }
        final staleSnapshot = await _windowsRest.getDocument(
          'phone_number_registry/$docId',
        );
        final ownerUid = (staleSnapshot?.data['uid'] as String?) ?? '';
        if (ownerUid == user.uid) {
          await _windowsRest.deleteDocument('phone_number_registry/$docId');
        }
      }

      await _auth.updateDisplayName(trimmedName);
      return;
    }

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
        final staleRef = _firestore
            .collection('phone_number_registry')
            .doc(docId);
        final staleSnapshot = await transaction.get(staleRef);
        final ownerUid = (staleSnapshot.data()?['uid'] as String?) ?? '';
        if (ownerUid == user.uid) {
          transaction.delete(staleRef);
        }
      }
    });

    await _auth.updateDisplayName(trimmedName);
  }

  Future<void> reloadCurrentUser() async {
    await _auth.reloadCurrentUser();
  }

  Future<void> _ensureWindowsLoginProfileExists(AppAuthUser user) async {
    final profile = await _fetchUserProfile(user.uid);
    if (profile != null) {
      return;
    }

    await _auth.signOut();
    await AuthSessionManager.clear();
    throw Exception(
      'This Windows app only supports existing accounts. Create or finish setting up your account on the web first.',
    );
  }

  Future<UserProfile?> getUserProfile(String userId) {
    return _fetchUserProfile(userId);
  }

  Future<UserProfile?> _fetchUserProfile(String userId) async {
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument('users/$userId');
      final data = document?.data;
      if (data == null) {
        return null;
      }
      return UserProfile.fromMap(document!.id, data);
    }

    final snapshot = await _firestore.collection('users').doc(userId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return null;
    }
    return UserProfile.fromMap(snapshot.id, data);
  }

  Stream<T> _buildWindowsPollingStream<T>({
    required Future<T> Function() load,
    required String Function(T value) signature,
  }) {
    late final StreamController<T> controller;
    Timer? timer;
    String? lastEmissionSignature;

    Future<void> emitIfChanged() async {
      if (controller.isClosed) {
        return;
      }
      try {
        final value = await load();
        final nextSignature = 'value:${signature(value)}';
        if (nextSignature == lastEmissionSignature) {
          return;
        }
        lastEmissionSignature = nextSignature;
        if (!controller.isClosed) {
          controller.add(value);
        }
      } catch (error, stackTrace) {
        final nextSignature = 'error:$error';
        if (nextSignature == lastEmissionSignature) {
          return;
        }
        lastEmissionSignature = nextSignature;
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<T>(
      onListen: () {
        unawaited(emitIfChanged());
        timer = Timer.periodic(_windowsPollInterval, (_) {
          unawaited(emitIfChanged());
        });
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> changePassword(String newPassword) async {
    await _auth.updatePassword(newPassword);
  }

  Future<Map<String, dynamic>> exportCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final userDoc = await _windowsRest.getDocument('users/${user.uid}');
      final onboarding = await _windowsRest.queryCollection(
        collectionId: 'onboarding_responses',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', user.uid),
        ],
      );
      final studentAppointments = await _windowsRest.queryCollection(
        collectionId: 'appointments',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('studentId', user.uid),
        ],
      );
      final counselorAppointments = await _windowsRest.queryCollection(
        collectionId: 'appointments',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('counselorId', user.uid),
        ],
      );
      final notifications = await _windowsRest.queryCollection(
        collectionId: 'notifications',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', user.uid),
        ],
      );
      final goals = await _windowsRest.queryCollection(
        collectionId: 'care_goals',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('studentId', user.uid),
        ],
      );
      final privacy = await _windowsRest.getDocument(
        'user_privacy_settings/${user.uid}',
      );

      List<Map<String, dynamic>> mapDocs(List<WindowsFirestoreDocument> docs) {
        return docs
            .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data})
            .toList(growable: false);
      }

      final export = <String, dynamic>{
        'exportedAt': DateTime.now().toIso8601String(),
        'user': userDoc?.data ?? const <String, dynamic>{},
        'onboardingResponses': mapDocs(onboarding),
        'studentAppointments': mapDocs(studentAppointments),
        'counselorAppointments': mapDocs(counselorAppointments),
        'notifications': mapDocs(notifications),
        'careGoals': mapDocs(goals),
        'privacySettings': privacy?.data ?? const <String, dynamic>{},
      };
      return export.map((key, value) => MapEntry(key, _jsonReady(value)));
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

    final export = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'user': userDoc.data() ?? const <String, dynamic>{},
      'onboardingResponses': mapDocs(onboarding),
      'studentAppointments': mapDocs(studentAppointments),
      'counselorAppointments': mapDocs(counselorAppointments),
      'notifications': mapDocs(notifications),
      'careGoals': mapDocs(goals),
      'privacySettings': privacy.data() ?? const <String, dynamic>{},
    };
    return export.map((key, value) => MapEntry(key, _jsonReady(value)));
  }

  Future<void> _ensureProfileExists(AppAuthUser user) async {
    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument('users/${user.uid}');
      if (existing != null) {
        return;
      }
      await _windowsRest.setDocument('users/${user.uid}', {
        'email': user.email,
        'name': user.displayName ?? '',
        'role': UserRole.individual.name,
        'onboardingCompletedRoles': <String, int>{},
        'institutionId': null,
        'institutionName': null,
        'phoneNumber': '',
        'additionalPhoneNumber': null,
        'phoneNumbers': const <String>[],
        'registrationIntent': null,
        'createdAt': DateTime.now().toUtc(),
        'updatedAt': DateTime.now().toUtc(),
      });
      return;
    }

    final userDoc = _firestore.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();
    if (snapshot.exists) {
      return;
    }

    await userDoc.set({
      'email': user.email,
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
      final data = kUseWindowsRestAuth
          ? (await _windowsRest.getDocument('users/$uid'))?.data
          : (await _firestore.collection('users').doc(uid).get()).data();
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

      if (kUseWindowsRestAuth) {
        final now = DateTime.now().toUtc();
        for (final phone in phones) {
          final documentPath =
              'phone_number_registry/${_phoneRegistryDocId(phone)}';
          final existing = await _windowsRest.getDocument(documentPath);
          if (existing != null) {
            final ownerUid = (existing.data['uid'] as String?) ?? '';
            if (ownerUid.isNotEmpty && ownerUid != uid) {
              continue;
            }
          }
          await _windowsRest.setDocument(documentPath, {
            'uid': uid,
            'phoneNumber': phone,
            'createdAt': now,
            'updatedAt': now,
          });
        }
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

  dynamic _jsonReady(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, nested) {
        result[key.toString()] = _jsonReady(nested);
      });
      return result;
    }
    if (value is Iterable) {
      return value.map(_jsonReady).toList(growable: false);
    }
    return value;
  }
}

class _PhoneNumberAlreadyInUseException implements Exception {
  const _PhoneNumberAlreadyInUseException(this.message);

  final String message;
}

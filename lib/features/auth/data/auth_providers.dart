import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/auth_repository.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: ref.read(firebaseAuthProvider),
    firestore: ref.read(firestoreProvider),
  );
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authUser = ref.watch(authStateChangesProvider).valueOrNull;
  if (authUser == null) {
    return const Stream<UserProfile?>.empty();
  }
  return ref.watch(authRepositoryProvider).userProfileChanges(authUser.uid);
});

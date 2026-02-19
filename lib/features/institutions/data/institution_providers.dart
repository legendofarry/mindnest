import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/institutions/data/institution_repository.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

final institutionRepositoryProvider = Provider<InstitutionRepository>((ref) {
  return InstitutionRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

final pendingUserInviteProvider = StreamProvider<UserInvite?>((ref) {
  final authUser = ref.watch(authStateChangesProvider).valueOrNull;
  final email = authUser?.email;
  if (email == null || email.isEmpty) {
    return Stream<UserInvite?>.value(null);
  }
  return ref.watch(institutionRepositoryProvider).pendingInviteForEmail(email);
});

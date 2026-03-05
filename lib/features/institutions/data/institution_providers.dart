import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/institutions/data/institution_repository.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

final institutionHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final institutionRepositoryProvider = Provider<InstitutionRepository>((ref) {
  return InstitutionRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    httpClient: ref.watch(institutionHttpClientProvider),
  );
});

final pendingUserInviteProvider = StreamProvider<UserInvite?>((ref) {
  final authUser = ref.watch(authStateChangesProvider).valueOrNull;
  final uid = authUser?.uid;
  if (uid == null || uid.isEmpty) {
    return Stream<UserInvite?>.value(null);
  }
  return ref.watch(institutionRepositoryProvider).pendingInviteForUid(uid);
});

final pendingUserInviteByIdProvider =
    StreamProvider.family<UserInvite?, String>((ref, inviteId) {
      final authUser = ref.watch(authStateChangesProvider).valueOrNull;
      final uid = authUser?.uid;
      if (uid == null || uid.isEmpty || inviteId.trim().isEmpty) {
        return Stream<UserInvite?>.value(null);
      }
      return ref
          .watch(institutionRepositoryProvider)
          .pendingInviteByIdForUid(inviteId: inviteId, uid: uid);
    });

final currentAdminInstitutionRequestProvider =
    StreamProvider<Map<String, dynamic>?>((ref) {
      final authUser = ref.watch(authStateChangesProvider).valueOrNull;
      if (authUser == null) {
        return Stream.value(null);
      }
      return ref
          .watch(institutionRepositoryProvider)
          .watchCurrentAdminInstitution();
    });

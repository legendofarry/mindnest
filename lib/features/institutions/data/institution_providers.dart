import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';
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

/// Raw invite fetch (no UID filtering) so we can show useful errors when
/// the invite exists but belongs to another account.
final inviteByIdProvider =
    StreamProvider.family<UserInvite?, String>((ref, inviteId) {
      final trimmed = inviteId.trim();
      if (trimmed.isEmpty) {
        return Stream<UserInvite?>.value(null);
      }
      return ref
          .watch(firestoreProvider)
          .collection('user_invites')
          .doc(trimmed)
          .snapshots()
          .map((doc) => doc.exists
              ? UserInvite.fromMap(doc.id, doc.data() ?? const {})
              : null);
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

final institutionDocumentProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, institutionId) {
      final normalized = institutionId.trim();
      if (normalized.isEmpty) {
        return Stream.value(null);
      }
      return ref
          .watch(firestoreProvider)
          .collection('institutions')
          .doc(normalized)
          .snapshots()
          .map((doc) {
            final data = doc.data();
            if (data == null) {
              return null;
            }
            return <String, dynamic>{'id': doc.id, ...data};
          });
    });

final counselorWorkflowSettingsProvider =
    Provider.family<AsyncValue<CounselorWorkflowSettings>, String>((
      ref,
      institutionId,
    ) {
      final institutionAsync = ref.watch(
        institutionDocumentProvider(institutionId),
      );
      return institutionAsync.whenData(
        CounselorWorkflowSettings.fromInstitutionData,
      );
    });

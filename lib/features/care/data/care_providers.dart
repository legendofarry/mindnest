import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/care/data/care_repository.dart';
import 'package:mindnest/features/care/models/session_reassignment_request.dart';

final careHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final careRepositoryProvider = Provider<CareRepository>((ref) {
  return CareRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    httpClient: ref.watch(careHttpClientProvider),
  );
});

final unreadNotificationCountProvider = StreamProvider.family<int, String>((
  ref,
  userId,
) {
  final normalized = userId.trim();
  if (normalized.isEmpty) {
    return Stream.value(0);
  }

  return ref
      .watch(careRepositoryProvider)
      .watchUserNotifications(normalized)
      .map(
        (items) =>
            items.where((entry) => !entry.isRead && !entry.isArchived).length,
      )
      .distinct();
});

final appointmentReassignmentRequestProvider =
    StreamProvider.family<SessionReassignmentRequest?, String>((
      ref,
      appointmentId,
    ) {
      return ref
          .watch(careRepositoryProvider)
          .watchAppointmentReassignmentRequest(appointmentId);
    });

final institutionReassignmentBoardProvider =
    StreamProvider.family<List<SessionReassignmentRequest>, String>((
      ref,
      institutionId,
    ) {
      final normalized = institutionId.trim();
      if (normalized.isEmpty) {
        return Stream.value(const <SessionReassignmentRequest>[]);
      }
      return ref
          .watch(careRepositoryProvider)
          .watchInstitutionReassignmentBoard(institutionId: normalized);
    });

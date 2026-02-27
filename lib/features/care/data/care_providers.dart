import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/care/data/care_repository.dart';

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

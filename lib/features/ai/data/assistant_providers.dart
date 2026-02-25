import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/ai/data/assistant_repository.dart';
import 'package:mindnest/features/ai/data/local_assistant_chat_store.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';

final assistantHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  return AssistantRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    httpClient: ref.watch(assistantHttpClientProvider),
  );
});

final assistantLocalChatStoreProvider = Provider<AssistantLocalChatStore>((
  ref,
) {
  return const AssistantLocalChatStore();
});

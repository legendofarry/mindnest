import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/ai/data/assistant_repository.dart';
import 'package:mindnest/features/ai/data/local_assistant_chat_store.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';

final assistantHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  return AssistantRepository(
    firestoreFactory: kUseWindowsRestAuth
        ? null
        : () => ref.watch(firestoreProvider),
    windowsRest: ref.watch(windowsFirestoreRestClientProvider),
    auth: ref.watch(appAuthClientProvider),
    httpClient: ref.watch(assistantHttpClientProvider),
  );
});

final assistantLocalChatStoreProvider = Provider<AssistantLocalChatStore>((
  ref,
) {
  return const AssistantLocalChatStore();
});

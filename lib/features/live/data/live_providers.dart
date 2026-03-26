import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/live/data/live_repository.dart';

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  return LiveRepository(
    firestoreFactory: kUseWindowsRestAuth
        ? null
        : () => ref.read(firestoreProvider),
    auth: ref.watch(appAuthClientProvider),
    windowsRest: ref.watch(windowsFirestoreRestClientProvider),
  );
});

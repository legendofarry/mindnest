import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/counselor/data/counselor_repository.dart';

final counselorRepositoryProvider = Provider<CounselorRepository>((ref) {
  return CounselorRepository(
    firestoreFactory: kUseWindowsRestAuth
        ? null
        : () => ref.read(firestoreProvider),
    auth: ref.watch(appAuthClientProvider),
    windowsRest: ref.watch(windowsFirestoreRestClientProvider),
  );
});

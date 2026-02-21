import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/live/data/live_repository.dart';

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  return LiveRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/care/data/care_repository.dart';

final careRepositoryProvider = Provider<CareRepository>((ref) {
  return CareRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/counselor/data/counselor_repository.dart';

final counselorRepositoryProvider = Provider<CounselorRepository>((ref) {
  return CounselorRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

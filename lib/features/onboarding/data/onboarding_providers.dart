import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/onboarding/data/onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

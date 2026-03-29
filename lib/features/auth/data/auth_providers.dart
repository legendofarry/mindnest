import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/account_export_service.dart';
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_repository.dart';
import 'package:mindnest/features/auth/models/app_auth_user.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

const Duration _windowsAuthPollInterval = Duration(seconds: 1);

bool get _useWindowsAuthSessionWorkaround =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

final firebaseAuthProvider = Provider<fb.FirebaseAuth>((ref) {
  return fb.FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final authHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final appAuthClientProvider = Provider<AppAuthClient>((ref) {
  if (kUseWindowsRestAuth) {
    return WindowsRestAppAuthClient(
      httpClient: ref.watch(authHttpClientProvider),
    );
  }
  return FirebaseAppAuthClient(ref.watch(firebaseAuthProvider));
});

final windowsFirestoreRestClientProvider = Provider<WindowsFirestoreRestClient>(
  (ref) {
    return WindowsFirestoreRestClient(
      authClient: ref.watch(appAuthClientProvider),
      httpClient: ref.watch(authHttpClientProvider),
    );
  },
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: ref.read(appAuthClientProvider),
    firestoreFactory: kUseWindowsRestAuth
        ? null
        : () => ref.read(firestoreProvider),
    windowsRest: ref.read(windowsFirestoreRestClientProvider),
  );
});

final accountExportServiceProvider = Provider<AccountExportService>((ref) {
  return const AccountExportService();
});

final authStateChangesProvider =
    AsyncNotifierProvider<AuthStateController, AppAuthUser?>(
      AuthStateController.new,
    );

final currentUserProfileProvider =
    AsyncNotifierProvider<CurrentUserProfileController, UserProfile?>(
      CurrentUserProfileController.new,
    );

Future<void> syncAuthSessionState(WidgetRef ref) async {
  await ref.read(authStateChangesProvider.notifier).refreshAuthState();
  if (_useWindowsAuthSessionWorkaround) {
    unawaited(ref.read(currentUserProfileProvider.notifier).refreshProfile());
    return;
  }
  await ref.read(currentUserProfileProvider.notifier).refreshProfile();
}

class AuthStateController extends AsyncNotifier<AppAuthUser?> {
  StreamSubscription<AppAuthUser?>? _subscription;
  Timer? _pollTimer;
  String? _lastSignature;

  @override
  FutureOr<AppAuthUser?> build() async {
    _disposeListeners();
    ref.onDispose(_disposeListeners);

    final authClient = ref.read(appAuthClientProvider);
    final initialUser = await authClient.initialize();
    _lastSignature = _userSignature(initialUser);

    if (_useWindowsAuthSessionWorkaround) {
      _pollTimer = Timer.periodic(_windowsAuthPollInterval, (_) {
        unawaited(refreshAuthState());
      });
      return initialUser;
    }

    _subscription = authClient.userChanges().listen(
      (user) {
        final nextSignature = _userSignature(user);
        if (nextSignature == _lastSignature) {
          return;
        }
        _lastSignature = nextSignature;
        state = AsyncData(user);
      },
      onError: (error, stackTrace) {
        state = AsyncError(error, stackTrace);
      },
    );

    return initialUser;
  }

  Future<void> refreshAuthState() async {
    final authClient = ref.read(appAuthClientProvider);
    final user = authClient.currentUser;
    final nextSignature = _userSignature(user);
    if (nextSignature == _lastSignature) {
      return;
    }
    _lastSignature = nextSignature;
    state = AsyncData(user);
  }

  void _disposeListeners() {
    _subscription?.cancel();
    _subscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  String _userSignature(AppAuthUser? user) {
    if (user == null) {
      return 'signed-out';
    }
    return [
      user.uid,
      user.email,
      user.displayName ?? '',
      user.phoneNumber ?? '',
      '${user.emailVerified}',
    ].join('|');
  }
}

class CurrentUserProfileController extends AsyncNotifier<UserProfile?> {
  StreamSubscription<UserProfile?>? _subscription;
  Timer? _pollTimer;
  String? _lastSignature;

  @override
  FutureOr<UserProfile?> build() async {
    _disposeListeners();
    ref.onDispose(_disposeListeners);

    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    if (authUser == null) {
      _lastSignature = _profileSignature(null);
      return null;
    }

    if (_useWindowsAuthSessionWorkaround) {
      final currentProfile = state.valueOrNull;
      _lastSignature = _profileSignature(currentProfile);
      _pollTimer = Timer.periodic(_windowsAuthPollInterval, (_) {
        unawaited(refreshProfile());
      });
      unawaited(refreshProfile());
      return currentProfile;
    }

    final authRepository = ref.read(authRepositoryProvider);
    final initialProfile = await authRepository.getUserProfile(authUser.uid);
    _lastSignature = _profileSignature(initialProfile);

    _subscription = authRepository
        .userProfileChanges(authUser.uid)
        .listen(
          (profile) {
            final nextSignature = _profileSignature(profile);
            if (nextSignature == _lastSignature) {
              return;
            }
            _lastSignature = nextSignature;
            state = AsyncData(profile);
          },
          onError: (error, stackTrace) {
            state = AsyncError(error, stackTrace);
          },
        );

    return initialProfile;
  }

  Future<void> refreshProfile() async {
    final authUser = ref.read(authStateChangesProvider).valueOrNull;
    if (authUser == null) {
      final nextSignature = _profileSignature(null);
      if (nextSignature != _lastSignature) {
        _lastSignature = nextSignature;
        state = const AsyncData(null);
      }
      return;
    }

    try {
      final authRepository = ref.read(authRepositoryProvider);
      final profile = _useWindowsAuthSessionWorkaround
          ? await authRepository
                .getUserProfile(authUser.uid)
                .timeout(const Duration(seconds: 5))
          : await authRepository.getUserProfile(authUser.uid);
      final nextSignature = _profileSignature(profile);
      if (nextSignature == _lastSignature) {
        return;
      }
      _lastSignature = nextSignature;
      state = AsyncData(profile);
    } on TimeoutException {
      return;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  void _disposeListeners() {
    _subscription?.cancel();
    _subscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  String _profileSignature(UserProfile? profile) {
    if (profile == null) {
      return 'missing-profile';
    }
    return [
      profile.id,
      profile.email,
      profile.name,
      profile.role.name,
      profile.institutionId ?? '',
      profile.institutionName ?? '',
      profile.phoneNumber ?? '',
      profile.additionalPhoneNumber ?? '',
      profile.registrationIntent ?? '',
      profile.phoneNumbers.join(','),
      '${profile.institutionWelcomePending}',
    ].join('|');
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/counselor/data/counselor_repository.dart';
import 'package:mindnest/features/counselor/models/counselor_institution_access_status.dart';

const Duration _windowsCounselorAccessPollInterval = Duration(seconds: 15);

bool get _useWindowsCounselorAccessPolling =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Stream<T> _buildWindowsCounselorPollingStream<T>({
  required Future<T> Function() load,
  required String Function(T value) signature,
}) {
  late final StreamController<T> controller;
  Timer? timer;
  String? lastSignature;

  Future<void> emitIfChanged() async {
    if (controller.isClosed) {
      return;
    }
    try {
      final value = await load();
      final nextSignature = signature(value);
      if (nextSignature == lastSignature) {
        return;
      }
      lastSignature = nextSignature;
      if (!controller.isClosed) {
        controller.add(value);
      }
    } catch (error, stackTrace) {
      final nextSignature = 'error:$error';
      if (nextSignature == lastSignature) {
        return;
      }
      lastSignature = nextSignature;
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }

  controller = StreamController<T>(
    onListen: () {
      unawaited(emitIfChanged());
      timer = Timer.periodic(_windowsCounselorAccessPollInterval, (_) {
        unawaited(emitIfChanged());
      });
    },
    onCancel: () {
      timer?.cancel();
    },
  );

  return controller.stream;
}

final counselorRepositoryProvider = Provider<CounselorRepository>((ref) {
  return CounselorRepository(
    firestoreFactory: kUseWindowsRestAuth
        ? null
        : () => ref.read(firestoreProvider),
    auth: ref.watch(appAuthClientProvider),
    windowsRest: ref.watch(windowsFirestoreRestClientProvider),
  );
});

final currentCounselorInstitutionAccessStatusProvider =
    StreamProvider<CounselorInstitutionAccessStatus>((ref) {
      final authUser = ref.watch(authStateChangesProvider).valueOrNull;
      final profile = ref.watch(currentUserProfileProvider).valueOrNull;
      if (!_useWindowsCounselorAccessPolling ||
          authUser == null ||
          profile == null ||
          profile.role != UserRole.counselor) {
        return Stream.value(CounselorInstitutionAccessStatus.inactive);
      }

      final repository = ref.watch(counselorRepositoryProvider);
      return _buildWindowsCounselorPollingStream<
        CounselorInstitutionAccessStatus
      >(
        load: repository.getCurrentInstitutionAccessStatus,
        signature: (status) => status.name,
      );
    });

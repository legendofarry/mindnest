import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
      if (authUser == null) {
        return Stream.value(CounselorInstitutionAccessStatus.inactive);
      }

      final repository = ref.watch(counselorRepositoryProvider);
      if (_useWindowsCounselorAccessPolling) {
        return _buildWindowsCounselorPollingStream<
          CounselorInstitutionAccessStatus
        >(
          load: repository.getCurrentInstitutionAccessStatus,
          signature: (status) => status.name,
        );
      }

      final firestore = ref.watch(firestoreProvider);
      return firestore
          .collection('users')
          .doc(authUser.uid)
          .snapshots()
          .map(
            (userSnapshot) =>
                _counselorAccessStatusFromUserSnapshot(userSnapshot),
          )
          .distinct();
    });

CounselorInstitutionAccessStatus _counselorAccessStatusFromUserSnapshot(
  DocumentSnapshot<Map<String, dynamic>> snapshot,
) {
  final userData = snapshot.data();
  if (userData == null ||
      (userData['role'] as String?) != UserRole.counselor.name) {
    return CounselorInstitutionAccessStatus.inactive;
  }

  final approvalStatus =
      ((userData['counselorApprovalStatus'] as String?) ?? '')
          .trim()
          .toLowerCase();
  final institutionId = ((userData['institutionId'] as String?) ?? '').trim();

  switch (approvalStatus) {
    case 'removed':
      return CounselorInstitutionAccessStatus.removed;
    case 'suspended':
      return CounselorInstitutionAccessStatus.suspended;
    case 'pending':
      return CounselorInstitutionAccessStatus.pending;
    case 'active':
      return institutionId.isEmpty
          ? CounselorInstitutionAccessStatus.inactive
          : CounselorInstitutionAccessStatus.active;
  }

  if (institutionId.isNotEmpty) {
    return CounselorInstitutionAccessStatus.active;
  }

  return CounselorInstitutionAccessStatus.inactive;
}

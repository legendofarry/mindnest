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
      late final StreamController<CounselorInstitutionAccessStatus> controller;
      StreamSubscription<CounselorInstitutionAccessStatus>?
      membershipSubscription;
      late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
      userSubscription;

      void emitImmediateStatus(String approvalStatus) {
        if (approvalStatus == 'removed') {
          controller.add(CounselorInstitutionAccessStatus.removed);
          return;
        }
        if (approvalStatus == 'suspended') {
          controller.add(CounselorInstitutionAccessStatus.suspended);
          return;
        }
        controller.add(CounselorInstitutionAccessStatus.inactive);
      }

      controller = StreamController<CounselorInstitutionAccessStatus>(
        onListen: () {
          userSubscription = firestore
              .collection('users')
              .doc(authUser.uid)
              .snapshots()
              .listen((userSnapshot) async {
                await membershipSubscription?.cancel();
                membershipSubscription = null;

                final userData = userSnapshot.data();
                if (userData == null ||
                    (userData['role'] as String?) != UserRole.counselor.name) {
                  controller.add(CounselorInstitutionAccessStatus.inactive);
                  return;
                }

                final institutionId =
                    ((userData['institutionId'] as String?) ?? '').trim();
                final approvalStatus =
                    ((userData['counselorApprovalStatus'] as String?) ?? '')
                        .trim()
                        .toLowerCase();
                if (institutionId.isEmpty) {
                  emitImmediateStatus(approvalStatus);
                  return;
                }

                membershipSubscription = firestore
                    .collection('institution_members')
                    .doc('${institutionId}_${authUser.uid}')
                    .snapshots()
                    .asyncMap(
                      (_) => repository.getCurrentInstitutionAccessStatus(),
                    )
                    .listen(controller.add, onError: controller.addError);
              }, onError: controller.addError);
        },
        onCancel: () async {
          await membershipSubscription?.cancel();
          await userSubscription.cancel();
        },
      );

      return controller.stream;
    });

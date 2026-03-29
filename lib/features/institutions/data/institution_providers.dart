import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';
import 'package:mindnest/features/institutions/data/institution_repository.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

final institutionHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final institutionRepositoryProvider = Provider<InstitutionRepository>((ref) {
  return InstitutionRepository(
    firestoreFactory: kUseWindowsRestAuth
        ? null
        : () => ref.read(firestoreProvider),
    auth: ref.watch(appAuthClientProvider),
    httpClient: ref.watch(institutionHttpClientProvider),
    windowsRest: ref.watch(windowsFirestoreRestClientProvider),
  );
});

const Duration _windowsPollInterval = Duration(seconds: 15);

bool get _useWindowsPollingWorkaround =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

String _stableValueSignature(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is DateTime) {
    return 'date:${value.toUtc().toIso8601String()}';
  }
  if (value is Iterable) {
    return 'list:[${value.map(_stableValueSignature).join(',')}]';
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return 'map:{${keys.map((key) => '$key=${_stableValueSignature(value[key])}').join(',')}}';
  }
  return '${value.runtimeType}:$value';
}

Stream<T> _buildWindowsPollingStream<T>({
  required Future<T> Function() load,
  required String Function(T value) signature,
}) {
  late final StreamController<T> controller;
  Timer? timer;
  String? lastEmissionSignature;

  Future<void> emitIfChanged() async {
    if (controller.isClosed) {
      return;
    }
    try {
      final value = await load();
      final nextSignature = 'value:${signature(value)}';
      if (nextSignature == lastEmissionSignature) {
        return;
      }
      lastEmissionSignature = nextSignature;
      if (!controller.isClosed) {
        controller.add(value);
      }
    } catch (error, stackTrace) {
      final nextSignature = 'error:$error';
      if (nextSignature == lastEmissionSignature) {
        return;
      }
      lastEmissionSignature = nextSignature;
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }

  controller = StreamController<T>(
    onListen: () {
      unawaited(emitIfChanged());
      timer = Timer.periodic(_windowsPollInterval, (_) {
        unawaited(emitIfChanged());
      });
    },
    onCancel: () {
      timer?.cancel();
    },
  );

  return controller.stream;
}

final pendingUserInviteProvider = StreamProvider<UserInvite?>((ref) {
  final authUser = ref.watch(authStateChangesProvider).valueOrNull;
  final uid = authUser?.uid;
  if (uid == null || uid.isEmpty) {
    return Stream<UserInvite?>.value(null);
  }
  if (_useWindowsPollingWorkaround) {
    final repository = ref.watch(institutionRepositoryProvider);
    return _buildWindowsPollingStream<UserInvite?>(
      load: () => repository.getPendingInviteForUid(uid),
      signature: (invite) => invite == null
          ? 'null'
          : '${invite.id}|${invite.status.name}|${invite.institutionId}|${invite.intendedRole.name}|${invite.expiresAt?.toIso8601String() ?? ''}|${invite.revokedAt?.toIso8601String() ?? ''}',
    );
  }
  return ref.watch(institutionRepositoryProvider).pendingInviteForUid(uid);
});

final pendingUserInvitesProvider = StreamProvider<List<UserInvite>>((ref) {
  final authUser = ref.watch(authStateChangesProvider).valueOrNull;
  final uid = authUser?.uid;
  if (uid == null || uid.isEmpty) {
    return Stream<List<UserInvite>>.value(const []);
  }
  if (_useWindowsPollingWorkaround) {
    final repository = ref.watch(institutionRepositoryProvider);
    return _buildWindowsPollingStream<List<UserInvite>>(
      load: () => repository.getPendingInvitesForUid(uid),
      signature: (invites) => invites
          .map(
            (invite) =>
                '${invite.id}|${invite.status.name}|${invite.institutionId}|${invite.intendedRole.name}',
          )
          .join(';'),
    );
  }
  return ref.watch(institutionRepositoryProvider).pendingInvitesForUid(uid);
});

final pendingUserInviteByIdProvider = StreamProvider.family<UserInvite?, String>((
  ref,
  inviteId,
) {
  final authUser = ref.watch(authStateChangesProvider).valueOrNull;
  final uid = authUser?.uid;
  if (uid == null || uid.isEmpty || inviteId.trim().isEmpty) {
    return Stream<UserInvite?>.value(null);
  }
  if (_useWindowsPollingWorkaround) {
    final repository = ref.watch(institutionRepositoryProvider);
    return _buildWindowsPollingStream<UserInvite?>(
      load: () =>
          repository.getPendingInviteByIdForUid(inviteId: inviteId, uid: uid),
      signature: (invite) => invite == null
          ? 'null'
          : '${invite.id}|${invite.status.name}|${invite.institutionId}|${invite.intendedRole.name}|${invite.revokedAt?.toIso8601String() ?? ''}',
    );
  }
  return ref
      .watch(institutionRepositoryProvider)
      .pendingInviteByIdForUid(inviteId: inviteId, uid: uid);
});

/// Raw invite fetch (no UID filtering) so we can show useful errors when
/// the invite exists but belongs to another account.
final inviteByIdProvider = StreamProvider.family<UserInvite?, String>((
  ref,
  inviteId,
) {
  final trimmed = inviteId.trim();
  if (trimmed.isEmpty) {
    return Stream<UserInvite?>.value(null);
  }
  if (_useWindowsPollingWorkaround) {
    final repository = ref.watch(institutionRepositoryProvider);
    return _buildWindowsPollingStream<UserInvite?>(
      load: () => repository.getInviteById(trimmed),
      signature: (invite) => invite == null
          ? 'null'
          : '${invite.id}|${invite.status.name}|${invite.institutionId}|${invite.intendedRole.name}|${invite.revokedAt?.toIso8601String() ?? ''}',
    );
  }
  return ref
      .watch(firestoreProvider)
      .collection('user_invites')
      .doc(trimmed)
      .snapshots()
      .map(
        (doc) => doc.exists
            ? UserInvite.fromMap(doc.id, doc.data() ?? const {})
            : null,
      );
});

final currentAdminInstitutionRequestProvider =
    StreamProvider<Map<String, dynamic>?>((ref) {
      final authUser = ref.watch(authStateChangesProvider).valueOrNull;
      if (authUser == null) {
        return Stream.value(null);
      }
      if (_useWindowsPollingWorkaround) {
        final repository = ref.watch(institutionRepositoryProvider);
        return _buildWindowsPollingStream<Map<String, dynamic>?>(
          load: repository.getCurrentAdminInstitution,
          signature: _stableValueSignature,
        );
      }
      return ref
          .watch(institutionRepositoryProvider)
          .watchCurrentAdminInstitution();
    });

final institutionDocumentProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, institutionId) {
      final normalized = institutionId.trim();
      if (normalized.isEmpty) {
        return Stream.value(null);
      }
      if (_useWindowsPollingWorkaround) {
        final repository = ref.watch(institutionRepositoryProvider);
        return _buildWindowsPollingStream<Map<String, dynamic>?>(
          load: () => repository.getInstitutionDocument(normalized),
          signature: _stableValueSignature,
        );
      }
      return ref
          .watch(firestoreProvider)
          .collection('institutions')
          .doc(normalized)
          .snapshots()
          .map((doc) {
            final data = doc.data();
            if (data == null) {
              return null;
            }
            return <String, dynamic>{'id': doc.id, ...data};
          });
    });

final counselorWorkflowSettingsProvider =
    Provider.family<AsyncValue<CounselorWorkflowSettings>, String>((
      ref,
      institutionId,
    ) {
      final institutionAsync = ref.watch(
        institutionDocumentProvider(institutionId),
      );
      return institutionAsync.whenData(
        CounselorWorkflowSettings.fromInstitutionData,
      );
    });

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/modern_banner.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/data/passkey_repository.dart';

Future<void> showPasskeyManagementDialog({
  required BuildContext context,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
          child: const PasskeyManagementDialog(),
        ),
      );
    },
  );
}

class PasskeyManagementDialog extends ConsumerStatefulWidget {
  const PasskeyManagementDialog({super.key});

  @override
  ConsumerState<PasskeyManagementDialog> createState() =>
      _PasskeyManagementDialogState();
}

class _PasskeyManagementDialogState
    extends ConsumerState<PasskeyManagementDialog> {
  bool _loading = true;
  bool _adding = false;
  bool _refreshing = false;
  bool _removingAll = false;
  final Set<String> _deletingIds = <String>{};
  String? _errorMessage;
  List<PasskeyCredentialRecord> _passkeys = const <PasskeyCredentialRecord>[];

  PasskeyRepository get _repository =>
      ref.read(passkeyRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadPasskeys());
  }

  Future<void> _showBanner(
    String message, {
    bool isError = false,
  }) async {
    if (!mounted) {
      return;
    }
    showModernBanner(
      context,
      message: message,
      icon: isError ? Icons.error_outline_rounded : Icons.fingerprint_rounded,
      color: isError ? const Color(0xFFBE123C) : const Color(0xFF0E9B90),
      autoDismissAfter: const Duration(seconds: 5),
    );
  }

  String _formatTimestamp(DateTime? value) {
    final local = value?.toLocal();
    if (local == null) {
      return 'Never';
    }
    return local.toIso8601String().replaceFirst('T', ' ').split('.').first;
  }

  Future<void> _loadPasskeys({bool showSpinner = true}) async {
    if (!mounted) {
      return;
    }
    if (showSpinner) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _refreshing = true;
        _errorMessage = null;
      });
    }

    try {
      final passkeys = await _repository.listMyPasskeys();
      passkeys.sort((a, b) {
        final aTime = a.lastUsedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastUsedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _passkeys = passkeys;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
      await _showBanner(_errorMessage!, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _addPasskey() async {
    if (_adding) {
      return;
    }
    setState(() {
      _adding = true;
      _errorMessage = null;
    });

    try {
      await _repository.enrollCurrentUser();
      if (!mounted) {
        return;
      }
      await _loadPasskeys(showSpinner: false);
      await _showBanner(
        'Passkey added. You can now use it on the login screen.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _errorMessage = message);
      await _showBanner(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _removePasskey(PasskeyCredentialRecord passkey) async {
    final credentialId = passkey.credentialId.trim();
    if (credentialId.isEmpty || _deletingIds.contains(credentialId)) {
      return;
    }
    setState(() {
      _deletingIds.add(credentialId);
      _errorMessage = null;
    });

    try {
      final deleted = await _repository.deleteMyPasskey(credentialId);
      if (!mounted) {
        return;
      }
      await _loadPasskeys(showSpinner: false);
      await _showBanner(
        deleted
            ? 'Passkey removed from this account.'
            : 'Passkey was already removed.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _errorMessage = message);
      await _showBanner(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _deletingIds.remove(credentialId));
      }
    }
  }

  Future<void> _removeAllPasskeys() async {
    if (_removingAll || _passkeys.isEmpty) {
      return;
    }
    setState(() {
      _removingAll = true;
      _errorMessage = null;
    });

    try {
      final deleted = await _repository.deleteAllMyPasskeys();
      if (!mounted) {
        return;
      }
      await _loadPasskeys(showSpinner: false);
      await _showBanner(
        deleted > 0
            ? 'Removed $deleted passkeys from this account.'
            : 'No passkeys were left to remove.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _errorMessage = message);
      await _showBanner(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _removingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final canUsePasskeys = !_loading && !_adding && !_refreshing && !_removingAll;

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAFBF8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: Color(0xFF0E9B90),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Passkeys',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF071937),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add or remove fingerprint, Face ID, Touch ID, and Windows Hello sign-ins.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF64748B),
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (profile != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FCFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD9EFEA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF0E9B90)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Signed in as ${profile.name.isNotEmpty ? profile.name : profile.email}.',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: canUsePasskeys ? _addPasskey : null,
                icon: _adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(_adding ? 'Setting up...' : 'Set up passkey'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E9B90),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _refreshing ? null : () => _loadPasskeys(showSpinner: false),
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
              TextButton.icon(
                onPressed: _passkeys.isEmpty || _removingAll ? null : _removeAllPasskeys,
                icon: _removingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_rounded),
                label: Text(_removingAll ? 'Removing...' : 'Remove all'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFF9F1239),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_passkeys.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.fingerprint_outlined,
                        size: 54,
                        color: Color(0xFF94A3B8),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'No passkeys are set up yet.',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Add one to use fingerprint sign-in on the login screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _passkeys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final passkey = _passkeys[index];
                    final deleting = _deletingIds.contains(passkey.credentialId);
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0E0F172A),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAFBF8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.fingerprint_rounded,
                              color: Color(0xFF0E9B90),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  passkey.displayLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  passkey.detailLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Last used: ${_formatTimestamp(passkey.lastUsedAt)}',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'Remove passkey',
                            onPressed: deleting
                                ? null
                                : () => _removePasskey(passkey),
                            icon: deleting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline_rounded),
                            color: const Color(0xFFBE123C),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

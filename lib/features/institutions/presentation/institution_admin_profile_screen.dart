import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/account_export_sheet.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

const Duration _windowsPollInterval = Duration(seconds: 15);

bool get _useWindowsPollingWorkaround =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

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

  controller = StreamController<T>.broadcast(
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

class InstitutionAdminProfileScreen extends ConsumerStatefulWidget {
  const InstitutionAdminProfileScreen({super.key});

  @override
  ConsumerState<InstitutionAdminProfileScreen> createState() =>
      _InstitutionAdminProfileScreenState();
}

class _InstitutionAdminProfileScreenState
    extends ConsumerState<InstitutionAdminProfileScreen> {
  final _name = TextEditingController();
  final _primaryPhone = TextEditingController(text: '+254');
  final _additionalPhone = TextEditingController();
  Stream<int>? _unreadMessageCount;

  bool _seeded = false;
  bool _saving = false;
  bool _sendingReset = false;

  @override
  void dispose() {
    _name.dispose();
    _primaryPhone.dispose();
    _additionalPhone.dispose();
    super.dispose();
  }

  void _seed(UserProfile profile) {
    if (_seeded) return;
    _unreadMessageCount ??= _useWindowsPollingWorkaround
        ? _buildWindowsPollingStream<int>(
            load: () async =>
                (await ref
                        .read(windowsFirestoreRestClientProvider)
                        .queryCollection(
                          collectionId: 'admin_counselor_messages',
                          filters: <WindowsFirestoreFieldFilter>[
                            WindowsFirestoreFieldFilter.equal(
                              'adminId',
                              profile.id,
                            ),
                            WindowsFirestoreFieldFilter.equal(
                              'senderRole',
                              'counselor',
                            ),
                            WindowsFirestoreFieldFilter.equal('isRead', false),
                          ],
                          limit: 200,
                        ))
                    .length,
            signature: (count) => '$count',
          )
        : ref
              .read(firestoreProvider)
              .collection('admin_counselor_messages')
              .where('adminId', isEqualTo: profile.id)
              .where('senderRole', isEqualTo: 'counselor')
              .where('isRead', isEqualTo: false)
              .snapshots()
              .map((snap) => snap.size);
    _name.text = profile.name;
    _primaryPhone.text = (profile.phoneNumber ?? '').isNotEmpty
        ? profile.phoneNumber!
        : '+254';
    _additionalPhone.text = profile.additionalPhoneNumber ?? '';
    _seeded = true;
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((element) => element.isNotEmpty);
    return parts.take(2).map((e) => e[0].toUpperCase()).join();
  }

  Future<void> _save(UserProfile profile) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .updateAccountProfile(
            name: _name.text.trim(),
            phoneNumber: _primaryPhone.text.trim(),
            additionalPhoneNumber: _additionalPhone.text.trim().isEmpty
                ? null
                : _additionalPhone.text.trim(),
          );
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Account updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendReset(UserProfile profile) async {
    setState(() => _sendingReset = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(profile.email.trim());
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } catch (error) {
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text(error.toString()))),
      data: (profile) {
        if (profile == null) {
          return const Scaffold(
            body: Center(child: Text('No profile found for this account.')),
          );
        }
        _seed(profile);
        return _ProfileBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 92, 18, 26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ProfileHero(
                              name: profile.name,
                              email: profile.email,
                              institution: profile.institutionName ?? '',
                              initials: _initials(
                                profile.name.isNotEmpty
                                    ? profile.name
                                    : profile.email,
                              ),
                            ),
                            const SizedBox(height: 18),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 920;
                                final accountCard = _SettingsCard(
                                  title: 'Account',
                                  subtitle:
                                      'Edit your display identity and mobile reach.',
                                  child: Column(
                                    children: [
                                      _LabeledField(
                                        label: 'Full name',
                                        icon: Icons.badge_rounded,
                                        controller: _name,
                                        hint: 'e.g. Jane Doe',
                                      ),
                                      const SizedBox(height: 12),
                                      _LabeledField(
                                        label: 'Primary mobile',
                                        icon: Icons.phone_rounded,
                                        controller: _primaryPhone,
                                        keyboardType: TextInputType.phone,
                                        hint: '+2547...',
                                      ),
                                      const SizedBox(height: 12),
                                      _LabeledField(
                                        label: 'Additional mobile (optional)',
                                        icon: Icons.smartphone_rounded,
                                        controller: _additionalPhone,
                                        keyboardType: TextInputType.phone,
                                        hint: '+254...',
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Use Kenya mobile numbers in +254 format.',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: _saving
                                              ? null
                                              : () => _save(profile),
                                          icon: _saving
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.4,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(Icons.save_rounded),
                                          label: Text(
                                            _saving
                                                ? 'Saving...'
                                                : 'Save changes',
                                          ),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                final accountToolsCard = _SettingsCard(
                                  title: 'Account tools',
                                  subtitle:
                                      'Manage your privacy and download your account data.',
                                  child: Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => context.push(
                                          AppRoute.privacyControls,
                                        ),
                                        icon: const Icon(
                                          Icons.verified_user_outlined,
                                        ),
                                        label: const Text('Privacy controls'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          showAccountExportSheet(
                                            context: context,
                                            ref: ref,
                                            title:
                                                'Download your admin account data',
                                            subtitle:
                                                'Choose a polished PDF summary, spreadsheet-ready CSV tables, or advanced raw JSON for your admin account export.',
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.download_rounded,
                                        ),
                                        label: const Text('Download my data'),
                                      ),
                                    ],
                                  ),
                                );

                                final securityCard = _SettingsCard(
                                  title: 'Security',
                                  subtitle:
                                      'Manage sign-in and account protections.',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Icons.mail_outline_rounded,
                                        ),
                                        title: const Text('Email'),
                                        subtitle: Text(profile.email),
                                        trailing: IconButton(
                                          tooltip: 'Copy email',
                                          icon: const Icon(Icons.copy_rounded),
                                          onPressed: () async {
                                            await Clipboard.setData(
                                              ClipboardData(
                                                text: profile.email,
                                              ),
                                            );
                                            if (!context.mounted) return;
                                            showModernBannerFromSnackBar(
                                              context,
                                              const SnackBar(
                                                content: Text('Email copied.'),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      FilledButton.icon(
                                        onPressed: _sendingReset
                                            ? null
                                            : () => _sendReset(profile),
                                        icon: _sendingReset
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.4,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.lock_reset_rounded,
                                              ),
                                        label: Text(
                                          _sendingReset
                                              ? 'Sending reset...'
                                              : 'Send password reset',
                                        ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          backgroundColor: const Color(
                                            0xFF0E9B90,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        onPressed: () => confirmAndLogout(
                                          context: context,
                                          ref: ref,
                                        ),
                                        icon: const Icon(Icons.logout_rounded),
                                        label: const Text('Log out'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (isWide) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: accountCard),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            accountToolsCard,
                                            const SizedBox(height: 14),
                                            securityCard,
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    accountCard,
                                    const SizedBox(height: 14),
                                    accountToolsCard,
                                    const SizedBox(height: 14),
                                    securityCard,
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    child: StreamBuilder<int>(
                      stream: _unreadMessageCount,
                      builder: (context, snapshot) {
                        final unread = snapshot.data ?? 0;
                        return _AdminProfileFloatingHeader(
                          unreadCount: unread,
                          onHome: () => context.go(AppRoute.institutionAdmin),
                          onMessages: () =>
                              context.go(AppRoute.institutionAdminMessages),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminProfileFloatingHeader extends StatelessWidget {
  const _AdminProfileFloatingHeader({
    required this.unreadCount,
    required this.onHome,
    required this.onMessages,
  });

  final int unreadCount;
  final VoidCallback onHome;
  final VoidCallback onMessages;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ProfileHeaderActionButton(
              tooltip: 'Institution home',
              icon: Icons.home_rounded,
              onPressed: onHome,
            ),
            const _ProfileHeaderTitleChip(title: 'Admin Profile'),
          ],
        ),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _ProfileHeaderActionButton(
              tooltip: 'Message counselors',
              icon: Icons.chat_bubble_outline_rounded,
              onPressed: onMessages,
            ),
            if (unreadCount > 0)
              Positioned(top: -4, right: -4, child: _Badge(count: unreadCount)),
          ],
        ),
        const SizedBox(width: 12),
        const WindowsDesktopWindowControls(),
      ],
    );
  }
}

class _ProfileHeaderTitleChip extends StatelessWidget {
  const _ProfileHeaderTitleChip({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E2EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: -0.2,
          color: Color(0xFF081A30),
        ),
      ),
    );
  }
}

class _ProfileHeaderActionButton extends StatelessWidget {
  const _ProfileHeaderActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD8E2EE)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF16324F)),
          ),
        ),
      ),
    );
  }
}

class _ProfileBackdrop extends StatelessWidget {
  const _ProfileBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEDF6FB), Color(0xFFEAF4F2), Color(0xFFF7F8F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: -60,
            child: _Orb(color: const Color(0x3314B8A6), size: 220),
          ),
          Positioned(
            right: -40,
            top: 260,
            child: _Orb(color: const Color(0x3338BDF8), size: 260),
          ),
          Positioned(
            left: 120,
            bottom: -60,
            child: _Orb(color: const Color(0x3358D8C5), size: 210),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 90, spreadRadius: 10)],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.email,
    required this.institution,
    required this.initials,
  });

  final String name;
  final String email;
  final String institution;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E9B90), Color(0xFF0B7D73)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0E9B90),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFF0E9B90),
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        color: Color(0xFFE0F2F1),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (institution.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B6B63),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.apartment_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                institution,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x33CBD5E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF081A30),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                color: Color(0xFF5E728D),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.icon,
    required this.controller,
    this.hint,
    this.keyboardType,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
            ),
          ),
        ),
      ],
    );
  }
}

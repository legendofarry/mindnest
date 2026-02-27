// features/live/presentation/live_hub_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_section_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/live/data/live_providers.dart';
import 'package:mindnest/features/live/models/live_participant.dart';
import 'package:mindnest/features/live/models/live_session.dart';

class LiveHubScreen extends ConsumerStatefulWidget {
  const LiveHubScreen({
    super.key,
    this.autoOpenCreate = false,
    this.embeddedInDesktopShell = false,
  });

  final bool autoOpenCreate;
  final bool embeddedInDesktopShell;

  @override
  ConsumerState<LiveHubScreen> createState() => _LiveHubScreenState();
}

class _LiveHubScreenState extends ConsumerState<LiveHubScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _allowStudents = true;
  bool _allowStaff = true;
  bool _allowCounselors = true;
  bool _creating = false;
  bool _autoCreateHandled = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool _canUseLive(UserProfile profile) {
    return profile.role == UserRole.student ||
        profile.role == UserRole.staff ||
        profile.role == UserRole.counselor;
  }

  String _statusLabel(LiveSessionStatus status) {
    switch (status) {
      case LiveSessionStatus.live:
        return 'Live';
      case LiveSessionStatus.paused:
        return 'Paused';
      case LiveSessionStatus.ended:
        return 'Ended';
    }
  }

  Color _statusColor(LiveSessionStatus status) {
    switch (status) {
      case LiveSessionStatus.live:
        return const Color(0xFF16A34A);
      case LiveSessionStatus.paused:
        return const Color(0xFFD97706);
      case LiveSessionStatus.ended:
        return const Color(0xFF64748B);
    }
  }

  Future<void> _openCreateLiveDialog(UserProfile profile) async {
    _titleController.clear();
    _descriptionController.clear();
    setState(() {
      _allowStudents = true;
      _allowStaff = true;
      _allowCounselors = true;
      _creating = false;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              final title = _titleController.text.trim();
              if (title.length < 4) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Title must be at least 4 characters.'),
                  ),
                );
                return;
              }
              final allowedRoles = <UserRole>[
                if (_allowStudents) UserRole.student,
                if (_allowStaff) UserRole.staff,
                if (_allowCounselors) UserRole.counselor,
              ];
              if (allowedRoles.isEmpty) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Select at least one allowed role.'),
                  ),
                );
                return;
              }
              setModalState(() => _creating = true);
              try {
                final live = await ref
                    .read(liveRepositoryProvider)
                    .createLiveSession(
                      title: title,
                      description: _descriptionController.text,
                      allowedRoles: allowedRoles,
                    );
                if (!sheetContext.mounted) {
                  return;
                }
                Navigator.of(sheetContext).pop();
                if (!mounted) {
                  return;
                }
                this.context.push('${AppRoute.liveRoom}?sessionId=${live.id}');
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString().replaceFirst('Exception: ', ''),
                    ),
                  ),
                );
              } finally {
                if (sheetContext.mounted) {
                  setModalState(() => _creating = false);
                }
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Start Live Audio',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      maxLength: 70,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.mic_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 220,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Role Access',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF334155),
                      ),
                    ),
                    CheckboxListTile(
                      value: _allowStudents,
                      onChanged: (value) =>
                          setModalState(() => _allowStudents = value ?? false),
                      title: const Text('Allow Students'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _allowStaff,
                      onChanged: (value) =>
                          setModalState(() => _allowStaff = value ?? false),
                      title: const Text('Allow Staff'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _allowCounselors,
                      onChanged: (value) => setModalState(
                        () => _allowCounselors = value ?? false,
                      ),
                      title: const Text('Allow Counselors'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 6),
                    ElevatedButton.icon(
                      onPressed: _creating ? null : submit,
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      label: Text(
                        _creating ? 'Creating...' : 'Start Live Session',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final useDesktopShell = widget.embeddedInDesktopShell && isDesktop;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final canUse = profile != null && _canUseLive(profile);

    if (widget.autoOpenCreate && !_autoCreateHandled && profile != null) {
      _autoCreateHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (!canUse || institutionId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You cannot start a live session from this account right now.',
              ),
            ),
          );
          return;
        }
        _openCreateLiveDialog(profile);
      });
    }

    final hubContent = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 1240 : 760),
              child: DesktopSectionBody(
                isDesktop: isDesktop && !useDesktopShell,
                hasInstitution: institutionId.isNotEmpty,
                canAccessLive: canUse,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        useDesktopShell ? 12 : kToolbarHeight + 2,
                        20,
                        22,
                      ),
                      child: profile == null
                          ? const Center(child: CircularProgressIndicator())
                          : !canUse
                          ? _LiveHubInfoMessageCard(
                              isDark: isDark,
                              message:
                                  'Live Audio Hub is available for students, staff, and counselors.',
                            )
                          : institutionId.isEmpty
                          ? _LiveHubInfoMessageCard(
                              isDark: isDark,
                              message:
                                  'Join an institution to access live sessions.',
                            )
                          : StreamBuilder<List<LiveSession>>(
                              stream: ref
                                  .read(liveRepositoryProvider)
                                  .watchInstitutionLives(
                                    institutionId: institutionId,
                                  ),
                              builder: (context, snapshot) {
                                final sessions =
                                    snapshot.data ?? const <LiveSession>[];
                                if (snapshot.connectionState ==
                                        ConnectionState.waiting &&
                                    sessions.isEmpty) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF0E9B90),
                                      strokeWidth: 2.5,
                                    ),
                                  );
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            _openCreateLiveDialog(profile),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF0E9B90,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: const StadiumBorder(),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 12,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.podcasts_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Go Live',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    _LiveHubInfoCard(isDark: isDark),
                                    const SizedBox(height: 18),
                                    Expanded(
                                      child: sessions.isEmpty
                                          ? Center(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: SizedBox(
                                                  width: 420,
                                                  child: _LiveHubEmptyState(
                                                    isDark: isDark,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : ListView.separated(
                                              physics:
                                                  const BouncingScrollPhysics(),
                                              padding: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              itemCount: sessions.length,
                                              separatorBuilder:
                                                  (context, index) =>
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                              itemBuilder: (context, index) {
                                                final session = sessions[index];
                                                final statusColor =
                                                    _statusColor(
                                                      session.status,
                                                    );
                                                return _LiveSessionCard(
                                                  session: session,
                                                  statusLabel: _statusLabel(
                                                    session.status,
                                                  ),
                                                  statusColor: statusColor,
                                                );
                                              },
                                            ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    final hubBody = useDesktopShell
        ? Container(color: Colors.white, child: hubContent)
        : Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF0B1220), Color(0xFF0E1A2E)]
                    : const [Color(0xFFF4F7FB), Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _LiveHubHomeBlobs(isDark: isDark)),
                hubContent,
              ],
            ),
          );

    if (useDesktopShell) {
      return hubBody;
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B1220)
          : const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      body: hubBody,
    );
  }
}

class _LiveHubInfoCard extends StatelessWidget {
  const _LiveHubInfoCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F31) : Colors.white,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFDDE6F1),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0x120F172A)).withValues(
              alpha: isDark ? 0.28 : 0.07,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E9B90),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.podcasts_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'What is Live Hub?',
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF1E293B),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Join institution-only live audio sessions. Listen in, request mic access, comment, and react in real-time with your community.',
            style: TextStyle(
              color: isDark ? const Color(0xFF9FB2CC) : const Color(0xFF516784),
              fontSize: 33 / 2,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveHubInfoMessageCard extends StatelessWidget {
  const _LiveHubInfoMessageCard({required this.isDark, required this.message});

  final bool isDark;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F31) : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFDDE6F1),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isDark ? const Color(0xFF9FB2CC) : const Color(0xFF516784),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LiveHubEmptyState extends StatelessWidget {
  const _LiveHubEmptyState({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 164,
          height: 164,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF152338) : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0x120F172A))
                    .withValues(alpha: isDark ? 0.24 : 0.07),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.podcasts_rounded,
            color: Color(0xFF0E9B90),
            size: 56,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Quiet in the Hub',
          style: TextStyle(
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F2744),
            fontSize: 43 / 2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'No active lives right now. Be\nthe first to start a conversation!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? const Color(0xFF9FB2CC) : const Color(0xFF516784),
            fontSize: 18,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LiveSessionCard extends ConsumerWidget {
  const _LiveSessionCard({
    required this.session,
    required this.statusLabel,
    required this.statusColor,
  });

  final LiveSession session;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () =>
            context.push('${AppRoute.liveRoom}?sessionId=${session.id}'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151F31) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFDDE6F1),
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0x120F172A))
                    .withValues(alpha: isDark ? 0.25 : 0.07),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark
                        ? const Color(0xFF9FB2CC)
                        : const Color(0xFF64748B),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                session.title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: isDark
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF0F172A),
                ),
              ),
              if (session.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  session.description,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF9FB2CC)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Host: ${session.hostName} (${session.hostRole.label})',
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFFC2D2E8)
                      : const Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StreamBuilder<List<LiveParticipant>>(
                    stream: ref
                        .read(liveRepositoryProvider)
                        .watchParticipants(session.id),
                    builder: (context, participantSnap) {
                      final listeners = participantSnap.data?.length ?? 0;
                      return _MetricChip(
                        icon: Icons.headphones_rounded,
                        text: '$listeners listening',
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon: Icons.favorite_rounded,
                    text: '${session.likeCount} likes',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D2B41) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? const Color(0xFFB7C6DA) : const Color(0xFF475569),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: isDark ? const Color(0xFFB7C6DA) : const Color(0xFF475569),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveHubHomeBlobs extends StatefulWidget {
  const _LiveHubHomeBlobs({required this.isDark});

  final bool isDark;

  @override
  State<_LiveHubHomeBlobs> createState() => _LiveHubHomeBlobsState();
}

class _LiveHubHomeBlobsState extends State<_LiveHubHomeBlobs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _blob(double size, List<Color> colors) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.45),
            blurRadius: 64,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blobA = widget.isDark
        ? const [Color(0x2E38BDF8), Color(0x0038BDF8)]
        : const [Color(0x300BA4FF), Color(0x000BA4FF)];
    final blobB = widget.isDark
        ? const [Color(0x2E14B8A6), Color(0x0014B8A6)]
        : const [Color(0x2A15A39A), Color(0x0015A39A)];
    final blobC = widget.isDark
        ? const [Color(0x2E22D3EE), Color(0x0022D3EE)]
        : const [Color(0x2418A89D), Color(0x0018A89D)];

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;
          return Stack(
            children: [
              Positioned(
                left: -70 + math.sin(t) * 28,
                top: -10 + math.cos(t * 1.2) * 20,
                child: _blob(320, blobA),
              ),
              Positioned(
                right: -70 + math.cos(t * 0.9) * 24,
                top: 150 + math.sin(t * 1.3) * 18,
                child: _blob(340, blobB),
              ),
              Positioned(
                left: 70 + math.cos(t * 1.1) * 18,
                bottom: -90 + math.sin(t * 0.75) * 22,
                child: _blob(280, blobC),
              ),
            ],
          );
        },
      ),
    );
  }
}

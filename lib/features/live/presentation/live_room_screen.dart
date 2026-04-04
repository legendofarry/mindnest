import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/live/data/live_providers.dart';
import 'package:mindnest/features/live/models/live_comment.dart';
import 'package:mindnest/features/live/models/live_mic_request.dart';
import 'package:mindnest/features/live/models/live_participant.dart';
import 'package:mindnest/features/live/models/live_reaction_event.dart';
import 'package:mindnest/features/live/models/live_session.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  final _commentController = TextEditingController();
  final _rand = Random();

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  StreamSubscription<LiveParticipant?>? _myParticipantSub;
  Timer? _presenceTimer;

  bool _joining = true;
  bool _leaving = false;
  bool _audioConnected = false;
  bool _canPublishWithToken = false;
  bool _refreshingAudioGrant = false;
  bool _micEnabled = false;
  bool _handledLiveEnded = false;
  String? _joinError;

  LiveParticipant? _myParticipant;
  final Set<String> _seenReactions = <String>{};
  final List<_Burst> _bursts = <_Burst>[];

  bool get _isHost => _myParticipant?.kind == LiveParticipantKind.host;
  bool get _canSpeak =>
      _myParticipant?.kind == LiveParticipantKind.host ||
      (_myParticipant?.kind == LiveParticipantKind.guest &&
          _myParticipant?.canSpeak == true &&
          _myParticipant?.mutedByHost != true);

  @override
  void initState() {
    super.initState();
    _join();
    _myParticipantSub = ref
        .read(liveRepositoryProvider)
        .watchMyParticipant(widget.sessionId)
        .listen((participant) async {
          if (!mounted || participant == null) {
            return;
          }
          setState(() => _myParticipant = participant);
          if (participant.canSpeak &&
              !participant.mutedByHost &&
              !_canPublishWithToken &&
              _audioConnected) {
            await _refreshAudioGrant();
          }
          if (participant.removed) {
            await _setMic(false, syncDb: false);
            if (!mounted) {
              return;
            }
            showModernBannerFromSnackBar(
              context,
              const SnackBar(content: Text('You were removed from this live.')),
            );
            await _leave(goHome: true);
          } else if (participant.mutedByHost && _micEnabled) {
            await _setMic(false);
            if (mounted) {
              showModernBannerFromSnackBar(
                context,
                const SnackBar(content: Text('Host muted your microphone.')),
              );
            }
          }
        });
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _myParticipantSub?.cancel();
    _roomListener?.dispose();
    _room?.disconnect();
    _room?.dispose();
    _commentController.dispose();
    super.dispose();
  }

  lk.EventsListener<lk.RoomEvent> _attachRoomListener(lk.Room room) {
    final listener = room.createListener();
    listener.on<lk.RoomDisconnectedEvent>((_) {
      if (!mounted || _leaving) {
        return;
      }
      setState(() => _audioConnected = false);
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Audio disconnected.')),
      );
    });
    return listener;
  }

  Future<void> _refreshAudioGrant() async {
    if (_refreshingAudioGrant || _leaving) {
      return;
    }
    _refreshingAudioGrant = true;
    try {
      final repo = ref.read(liveRepositoryProvider);
      final creds = await repo.createLiveKitJoinCredentials(
        sessionId: widget.sessionId,
      );

      final shouldEnableMic = _micEnabled && creds.canPublishAudio;

      _roomListener?.dispose();
      await _room?.disconnect();
      _room?.dispose();

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      final listener = _attachRoomListener(room);
      await room.connect(
        creds.serverUrl,
        creds.token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: true),
      );

      _room = room;
      _roomListener = listener;
      _audioConnected = true;
      _canPublishWithToken = creds.canPublishAudio;
      _micEnabled = shouldEnableMic;
      await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
      await repo.setMyMicEnabled(
        sessionId: widget.sessionId,
        enabled: _micEnabled,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _audioConnected = false;
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Failed to refresh audio permissions: '
            '${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      _refreshingAudioGrant = false;
    }
  }

  Future<void> _join() async {
    try {
      final repo = ref.read(liveRepositoryProvider);
      final session = await repo.joinLiveSession(widget.sessionId);
      final creds = await repo.createLiveKitJoinCredentials(
        sessionId: widget.sessionId,
      );

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      final listener = _attachRoomListener(room);

      await room.connect(
        creds.serverUrl,
        creds.token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: true),
      );

      _room = room;
      _roomListener = listener;
      _audioConnected = true;
      _canPublishWithToken = creds.canPublishAudio;
      if (session.createdBy ==
          ref.read(appAuthClientProvider).currentUser?.uid) {
        await _setMic(_canPublishWithToken);
      } else {
        await _setMic(false);
      }
      _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        ref.read(liveRepositoryProvider).touchPresence(widget.sessionId);
      });
      if (mounted) {
        setState(() {
          _joining = false;
          _joinError = null;
        });
      }
    } catch (error) {
      _roomListener?.dispose();
      _room?.dispose();
      _room = null;
      _audioConnected = false;
      _canPublishWithToken = false;
      if (mounted) {
        setState(() {
          _joining = false;
          _joinError = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _setMic(bool enabled, {bool syncDb = true}) async {
    try {
      if (enabled && !_audioConnected) {
        throw Exception('Audio is not connected yet.');
      }
      if (enabled && !_canPublishWithToken) {
        throw Exception(
          'Mic access is not granted yet. Request mic and wait for host approval.',
        );
      }
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      _micEnabled = enabled;
      if (syncDb) {
        await ref
            .read(liveRepositoryProvider)
            .setMyMicEnabled(sessionId: widget.sessionId, enabled: enabled);
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _leave({bool goHome = false}) async {
    if (_leaving) {
      return;
    }
    _leaving = true;
    _presenceTimer?.cancel();
    try {
      await _setMic(false, syncDb: false);
      await _room?.disconnect();
      await ref.read(liveRepositoryProvider).leaveLiveSession(widget.sessionId);
    } catch (_) {
      // Ignore leave failures.
    } finally {
      _roomListener?.dispose();
      _room?.dispose();
      _room = null;
      _audioConnected = false;
      _canPublishWithToken = false;
      _leaving = false;
      if (mounted && goHome) {
        context.go(AppRoute.home);
      }
    }
  }

  Future<void> _handleHostEndedLive() async {
    if (_handledLiveEnded || _leaving || !mounted) {
      return;
    }
    _handledLiveEnded = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Live Ended'),
        content: const Text('Host has ended this live session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }
    await _leave(goHome: true);
  }

  void _syncBursts(List<LiveReactionEvent> reactions) {
    for (final reaction in reactions.take(12)) {
      if (_seenReactions.add(reaction.id)) {
        _bursts.add(
          _Burst(
            id: reaction.id,
            emoji: reaction.emoji,
            right: 20 + _rand.nextDouble() * 120,
          ),
        );
      }
    }
  }

  Future<void> _onCommentTap(LiveComment comment) async {
    final reasonController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Comment Actions',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.person_search_rounded),
                  title: const Text('View Profile'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await ref
                        .read(liveRepositoryProvider)
                        .fetchMemberPublicProfile(
                          sessionId: widget.sessionId,
                          userId: comment.userId,
                        )
                        .then((profile) {
                          if (!mounted) {
                            return;
                          }
                          showDialog<void>(
                            context: this.context,
                            builder: (context) => AlertDialog(
                              title: const Text('Member Profile'),
                              content: Text(
                                profile == null
                                    ? 'Profile unavailable.'
                                    : '${profile.displayName}\n${profile.role}\n${profile.email}',
                              ),
                            ),
                          );
                        });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flag_rounded),
                  title: const Text('Report Comment'),
                  onTap: () async {
                    final reason = await showDialog<String>(
                      context: this.context,
                      builder: (context) => AlertDialog(
                        title: const Text('Report Comment'),
                        content: TextField(
                          controller: reasonController,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(reasonController.text.trim()),
                            child: const Text('Report'),
                          ),
                        ],
                      ),
                    );
                    if (reason == null || reason.isEmpty) {
                      return;
                    }
                    await ref
                        .read(liveRepositoryProvider)
                        .reportComment(
                          sessionId: widget.sessionId,
                          comment: comment,
                          reason: reason,
                        );
                    if (mounted) {
                      Navigator.of(this.context).pop();
                    }
                  },
                ),
                if (_isHost && comment.userId != _myParticipant?.userId)
                  ListTile(
                    leading: const Icon(Icons.volume_off_rounded),
                    title: const Text('Mute User'),
                    onTap: () async {
                      await ref
                          .read(liveRepositoryProvider)
                          .muteParticipant(
                            sessionId: widget.sessionId,
                            targetUserId: comment.userId,
                            muted: true,
                          );
                      if (mounted) {
                        Navigator.of(this.context).pop();
                      }
                    },
                  ),
                if (_isHost && comment.userId != _myParticipant?.userId)
                  ListTile(
                    leading: const Icon(
                      Icons.person_remove_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    title: const Text(
                      'Remove User',
                      style: TextStyle(color: Color(0xFFDC2626)),
                    ),
                    onTap: () async {
                      await ref
                          .read(liveRepositoryProvider)
                          .removeParticipant(
                            sessionId: widget.sessionId,
                            targetUserId: comment.userId,
                          );
                      if (mounted) {
                        Navigator.of(this.context).pop();
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
    reasonController.dispose();
  }

  Future<void> _showMicRequests(List<LiveMicRequest> requests) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Mic Requests',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 10),
                if (requests.isEmpty)
                  const Text('No pending requests.')
                else
                  ...requests.map((request) {
                    return ListTile(
                      title: Text(request.displayName),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => ref
                                .read(liveRepositoryProvider)
                                .denyMicRequest(
                                  sessionId: widget.sessionId,
                                  targetUserId: request.userId,
                                ),
                            child: const Text('Deny'),
                          ),
                          ElevatedButton(
                            onPressed: () => ref
                                .read(liveRepositoryProvider)
                                .approveMicRequest(
                                  sessionId: widget.sessionId,
                                  targetUserId: request.userId,
                                ),
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      return;
    }
    try {
      await ref
          .read(liveRepositoryProvider)
          .sendComment(sessionId: widget.sessionId, text: text);
      _commentController.clear();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _sendQuickReaction(String emoji) async {
    try {
      await ref
          .read(liveRepositoryProvider)
          .sendReaction(sessionId: widget.sessionId, emoji: emoji);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  String _initialsFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'MN';
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return trimmed.length >= 2
          ? trimmed.substring(0, 2).toUpperCase()
          : trimmed.toUpperCase();
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    return '$first$last'.toUpperCase();
  }

  List<Color> _avatarPalette(String seed) {
    const palettes = <List<Color>>[
      [Color(0xFF14B8A6), Color(0xFF2563EB)],
      [Color(0xFF0EA5E9), Color(0xFF8B5CF6)],
      [Color(0xFFF97316), Color(0xFFEF4444)],
      [Color(0xFF22C55E), Color(0xFF0891B2)],
      [Color(0xFFEAB308), Color(0xFFF97316)],
      [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    ];
    final code = seed.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return palettes[code % palettes.length];
  }

  String _hostStatus(LiveSession session) {
    if (session.status == LiveSessionStatus.paused) {
      return 'Paused';
    }
    if (_isHost && _micEnabled) {
      return 'Speaking';
    }
    return 'Live now';
  }

  String _speakerStatus(LiveParticipant participant) {
    if (participant.mutedByHost) {
      return 'Muted';
    }
    if (participant.canSpeak && participant.micEnabled) {
      return 'Speaking';
    }
    if (participant.canSpeak) {
      return 'On stage';
    }
    return 'Pending mic';
  }

  String _formatShortTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Widget _buildImmersiveDesktopRoom({
    required LiveSession session,
    required List<LiveParticipant> participants,
    required List<LiveMicRequest> requests,
    required List<LiveComment> comments,
  }) {
    final size = MediaQuery.sizeOf(context);
    final listeners = participants
        .where((entry) => entry.kind == LiveParticipantKind.listener)
        .toList(growable: false);
    final speakers =
        participants
            .where((entry) => entry.kind == LiveParticipantKind.guest)
            .toList()
          ..sort((a, b) {
            final aScore = (a.canSpeak ? 2 : 0) + (a.micEnabled ? 1 : 0);
            final bScore = (b.canSpeak ? 2 : 0) + (b.micEnabled ? 1 : 0);
            return bScore.compareTo(aScore);
          });
    final spotlightSpeakers = speakers.take(3).toList(growable: false);
    LiveParticipant? hostParticipant;
    for (final participant in participants) {
      if (participant.kind == LiveParticipantKind.host) {
        hostParticipant = participant;
        break;
      }
    }
    final currentKind = _myParticipant?.kind ?? LiveParticipantKind.listener;
    final myPendingRequest = requests.any(
      (request) => request.userId == _myParticipant?.userId,
    );
    final showRequests = _isHost;
    final stageHeight = (size.height - 92).clamp(720.0, 980.0).toDouble();
    final hostPalette = _avatarPalette(session.hostName);

    return SizedBox(
      height: stageHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x160EA5A0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x120F172A),
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        children: [
                          _LiveMetric(
                            icon: Icons.people_outline_rounded,
                            value: '${listeners.length}',
                          ),
                          _LiveMetric(
                            icon: Icons.favorite_border_rounded,
                            value: '${session.likeCount}',
                          ),
                          _LiveMetric(
                            icon: Icons.mic_none_rounded,
                            value: '${speakers.length}/${session.maxGuests}',
                          ),
                          _LiveMetric(
                            icon: _audioConnected
                                ? Icons.graphic_eq_rounded
                                : Icons.wifi_off_rounded,
                            value: _audioConnected
                                ? 'Audio connected'
                                : 'Audio offline',
                          ),
                          if (session.status == LiveSessionStatus.paused)
                            const _LiveStatusChip(
                              label: 'Paused',
                              color: Color(0xFFF59E0B),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_isHost) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(liveRepositoryProvider)
                        .endLiveSession(widget.sessionId),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End live'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(color: const Color(0x260EA5A0)),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEFFCF9), Color(0xFFF2FBFF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: -100,
                              top: 90,
                              child: Container(
                                width: 230,
                                height: 230,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0x220EA5A0),
                                ),
                              ),
                            ),
                            Positioned(
                              right: -70,
                              top: 48,
                              child: Container(
                                width: 190,
                                height: 190,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0x183B82F6),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 90,
                              bottom: -80,
                              child: Container(
                                width: 280,
                                height: 280,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0x120EA5A0),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                28,
                                26,
                                28,
                                24,
                              ),
                              child: Column(
                                children: [
                                  _LivePersonaCard(
                                    name:
                                        hostParticipant
                                                ?.displayName
                                                .isNotEmpty ==
                                            true
                                        ? hostParticipant!.displayName
                                        : session.hostName,
                                    badge: 'Host',
                                    status: _hostStatus(session),
                                    palette: hostPalette,
                                    initials: _initialsFor(session.hostName),
                                    isPrimary: true,
                                    muted:
                                        session.status ==
                                        LiveSessionStatus.paused,
                                  ),
                                  const SizedBox(height: 42),
                                  Expanded(
                                    child: Center(
                                      child: spotlightSpeakers.isEmpty
                                          ? const SizedBox.shrink()
                                          : Wrap(
                                              alignment: WrapAlignment.center,
                                              spacing: 34,
                                              runSpacing: 28,
                                              children: [
                                                for (final speaker
                                                    in spotlightSpeakers)
                                                  _LivePersonaCard(
                                                    name: speaker.displayName,
                                                    badge: 'Speaker',
                                                    status: _speakerStatus(
                                                      speaker,
                                                    ),
                                                    palette: _avatarPalette(
                                                      speaker.displayName,
                                                    ),
                                                    initials: _initialsFor(
                                                      speaker.displayName,
                                                    ),
                                                    muted:
                                                        speaker.mutedByHost ||
                                                        !speaker.micEnabled,
                                                  ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  _LiveControlDock(
                                    isHost: _isHost,
                                    isSpeaker:
                                        currentKind ==
                                        LiveParticipantKind.guest,
                                    isListener:
                                        currentKind ==
                                        LiveParticipantKind.listener,
                                    micEnabled: _micEnabled,
                                    paused:
                                        session.status ==
                                        LiveSessionStatus.paused,
                                    requestPending: myPendingRequest,
                                    onToggleMic:
                                        (_audioConnected &&
                                            _canSpeak &&
                                            session.status ==
                                                LiveSessionStatus.live)
                                        ? () => _setMic(!_micEnabled)
                                        : null,
                                    onPauseResume: _isHost
                                        ? () => ref
                                              .read(liveRepositoryProvider)
                                              .togglePause(
                                                sessionId: widget.sessionId,
                                                pause:
                                                    session.status ==
                                                    LiveSessionStatus.live,
                                              )
                                        : null,
                                    onRequestMic:
                                        currentKind ==
                                                LiveParticipantKind.listener &&
                                            _audioConnected &&
                                            !myPendingRequest
                                        ? () => ref
                                              .read(liveRepositoryProvider)
                                              .requestMic(widget.sessionId)
                                        : null,
                                    onReact: () => _sendQuickReaction('❤️'),
                                    onLeave: () => _leave(goHome: true),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._bursts.map(
                        (burst) => Positioned(
                          right: burst.right,
                          bottom: 118,
                          child: _BurstWidget(
                            key: ValueKey('burst_${burst.id}'),
                            emoji: burst.emoji,
                            onDone: () {
                              _bursts.removeWhere(
                                (entry) => entry.id == burst.id,
                              );
                              if (mounted) {
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 340,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: const Color(0x220EA5A0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showRequests) ...[
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Requests',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                Text(
                                  requests.length.toString().padLeft(2, '0'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (requests.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  color: const Color(0xFFF8FAFC),
                                ),
                                child: const Text(
                                  'No mic requests yet.',
                                  style: TextStyle(color: Color(0xFF64748B)),
                                ),
                              )
                            else
                              ...requests
                                  .take(4)
                                  .map(
                                    (request) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          color: const Color(0xFFF8FAFC),
                                          border: Border.all(
                                            color: const Color(0x120EA5A0),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              request.displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Requested at ${_formatShortTime(request.createdAt)}',
                                              style: const TextStyle(
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton(
                                                    onPressed: () => ref
                                                        .read(
                                                          liveRepositoryProvider,
                                                        )
                                                        .denyMicRequest(
                                                          sessionId:
                                                              widget.sessionId,
                                                          targetUserId:
                                                              request.userId,
                                                        ),
                                                    child: const Text(
                                                      'Decline',
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: FilledButton(
                                                    onPressed: () => ref
                                                        .read(
                                                          liveRepositoryProvider,
                                                        )
                                                        .approveMicRequest(
                                                          sessionId:
                                                              widget.sessionId,
                                                          targetUserId:
                                                              request.userId,
                                                        ),
                                                    style:
                                                        FilledButton.styleFrom(
                                                          backgroundColor:
                                                              const Color(
                                                                0xFF0E9B90,
                                                              ),
                                                        ),
                                                    child: const Text(
                                                      'Approve',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                            const SizedBox(height: 8),
                            const Divider(color: Color(0x120EA5A0)),
                            const SizedBox(height: 12),
                          ],
                          const Text(
                            'Live chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: comments.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No comments yet. Start the conversation.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 15,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: comments.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 14),
                                    itemBuilder: (context, index) {
                                      final comment = comments[index];
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () => _onCommentTap(comment),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            color: const Color(0xFFF7FBFC),
                                            border: Border.all(
                                              color: const Color(0x140EA5A0),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                comment.displayName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF14B8A6),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                comment.text,
                                                style: const TextStyle(
                                                  height: 1.45,
                                                  color: Color(0xFF334155),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            children: const ['🔥', '👏', '❤️', '💯', '😂', '🙌']
                                .map(
                                  (emoji) => _ReactionBubble(
                                    emoji: emoji,
                                    onTap: () => _sendQuickReaction(emoji),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  maxLength: 250,
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    hintText: 'Message...',
                                  ),
                                  onSubmitted: (_) => _sendComment(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: _sendComment,
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF0E9B90),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.send_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(liveRepositoryProvider);
    final isImmersiveDesktop = MediaQuery.sizeOf(context).width >= 1200;

    return MindNestShell(
      maxWidth: isImmersiveDesktop ? 1700 : 1080,
      appBar: null,
      padding: isImmersiveDesktop
          ? const EdgeInsets.fromLTRB(12, 12, 12, 18)
          : const EdgeInsets.all(20),
      backgroundMode: isImmersiveDesktop
          ? MindNestBackgroundMode.homeStyle
          : MindNestBackgroundMode.defaultShell,
      child: _joining
          ? const Center(child: CircularProgressIndicator())
          : _joinError != null
          ? GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_joinError!),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _join,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : StreamBuilder<LiveSession?>(
              stream: repo.watchLiveSession(widget.sessionId),
              builder: (context, sessionSnap) {
                final session = sessionSnap.data;
                if (session == null) {
                  return const GlassCard(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Live session not found.'),
                    ),
                  );
                }
                if (session.status == LiveSessionStatus.ended) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _handleHostEndedLive(),
                  );
                }
                if (session.status == LiveSessionStatus.paused && _micEnabled) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _setMic(false),
                  );
                }

                return StreamBuilder<List<LiveParticipant>>(
                  stream: repo.watchParticipants(widget.sessionId),
                  builder: (context, participantSnap) {
                    final participants =
                        participantSnap.data ?? const <LiveParticipant>[];
                    final guests = participants
                        .where(
                          (entry) => entry.kind == LiveParticipantKind.guest,
                        )
                        .length;
                    return StreamBuilder<List<LiveMicRequest>>(
                      stream: repo.watchPendingMicRequests(widget.sessionId),
                      builder: (context, reqSnap) {
                        final requests =
                            reqSnap.data ?? const <LiveMicRequest>[];
                        return StreamBuilder<List<LiveComment>>(
                          stream: repo.watchComments(widget.sessionId),
                          builder: (context, commentSnap) {
                            final comments =
                                commentSnap.data ?? const <LiveComment>[];
                            return StreamBuilder<List<LiveReactionEvent>>(
                              stream: repo.watchReactions(widget.sessionId),
                              builder: (context, reactionSnap) {
                                _syncBursts(
                                  reactionSnap.data ??
                                      const <LiveReactionEvent>[],
                                );
                                if (isImmersiveDesktop) {
                                  return _buildImmersiveDesktopRoom(
                                    session: session,
                                    participants: participants,
                                    requests: requests,
                                    comments: comments,
                                  );
                                }
                                final commentsPanelHeight =
                                    (MediaQuery.sizeOf(context).height * 0.52)
                                        .clamp(320.0, 560.0)
                                        .toDouble();
                                return Stack(
                                  children: [
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        GlassCard(
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  session.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 20,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _Pill(
                                                      text:
                                                          'Host: ${session.hostName}',
                                                      icon: Icons.person,
                                                    ),
                                                    _Pill(
                                                      text:
                                                          '${participants.length} listening',
                                                      icon: Icons
                                                          .headphones_rounded,
                                                    ),
                                                    _Pill(
                                                      text:
                                                          '$guests/${session.maxGuests} podium',
                                                      icon: Icons.mic_rounded,
                                                    ),
                                                    _Pill(
                                                      text:
                                                          '${session.likeCount} likes',
                                                      icon: Icons
                                                          .favorite_rounded,
                                                    ),
                                                    _Pill(
                                                      text: _audioConnected
                                                          ? 'Audio connected'
                                                          : 'Audio offline',
                                                      icon: _audioConnected
                                                          ? Icons
                                                                .graphic_eq_rounded
                                                          : Icons
                                                                .warning_amber_rounded,
                                                    ),
                                                  ],
                                                ),
                                                if (session.status ==
                                                    LiveSessionStatus
                                                        .paused) ...[
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Paused by host.',
                                                    style: TextStyle(
                                                      color: Color(0xFFD97706),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 10),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    ElevatedButton.icon(
                                                      onPressed:
                                                          (_audioConnected &&
                                                              _canSpeak &&
                                                              session.status ==
                                                                  LiveSessionStatus
                                                                      .live)
                                                          ? () => _setMic(
                                                              !_micEnabled,
                                                            )
                                                          : null,
                                                      icon: Icon(
                                                        _micEnabled
                                                            ? Icons.mic_rounded
                                                            : Icons
                                                                  .mic_off_rounded,
                                                      ),
                                                      label: Text(
                                                        _micEnabled
                                                            ? 'Mute Mic'
                                                            : 'Enable Mic',
                                                      ),
                                                    ),
                                                    if (_myParticipant?.kind ==
                                                        LiveParticipantKind
                                                            .listener)
                                                      OutlinedButton.icon(
                                                        onPressed:
                                                            _audioConnected
                                                            ? () => repo
                                                                  .requestMic(
                                                                    widget
                                                                        .sessionId,
                                                                  )
                                                            : null,
                                                        icon: const Icon(
                                                          Icons
                                                              .record_voice_over_rounded,
                                                        ),
                                                        label: const Text(
                                                          'Request Mic',
                                                        ),
                                                      ),
                                                    if (_isHost)
                                                      OutlinedButton.icon(
                                                        onPressed: () =>
                                                            repo.togglePause(
                                                              sessionId: widget
                                                                  .sessionId,
                                                              pause:
                                                                  session
                                                                      .status ==
                                                                  LiveSessionStatus
                                                                      .live,
                                                            ),
                                                        icon: Icon(
                                                          session.status ==
                                                                  LiveSessionStatus
                                                                      .live
                                                              ? Icons
                                                                    .pause_circle_outline_rounded
                                                              : Icons
                                                                    .play_circle_outline_rounded,
                                                        ),
                                                        label: Text(
                                                          session.status ==
                                                                  LiveSessionStatus
                                                                      .live
                                                              ? 'Pause'
                                                              : 'Resume',
                                                        ),
                                                      ),
                                                    if (_isHost)
                                                      OutlinedButton.icon(
                                                        onPressed: () =>
                                                            _showMicRequests(
                                                              requests,
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .manage_accounts_rounded,
                                                        ),
                                                        label: Text(
                                                          'Requests (${requests.length})',
                                                        ),
                                                      ),
                                                    if (_isHost)
                                                      ElevatedButton.icon(
                                                        onPressed: () =>
                                                            repo.endLiveSession(
                                                              widget.sessionId,
                                                            ),
                                                        style:
                                                            ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                    0xFFDC2626,
                                                                  ),
                                                              foregroundColor:
                                                                  Colors.white,
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .stop_circle_outlined,
                                                        ),
                                                        label: const Text(
                                                          'End Live',
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          height: commentsPanelHeight,
                                          child: GlassCard(
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  const Text(
                                                    'Live Comments',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Expanded(
                                                    child: ListView.builder(
                                                      reverse: true,
                                                      itemCount:
                                                          comments.length,
                                                      itemBuilder: (context, index) {
                                                        final comment =
                                                            comments[index];
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 8,
                                                              ),
                                                          child: InkWell(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            onTap: () =>
                                                                _onCommentTap(
                                                                  comment,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    10,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    const Color(
                                                                      0xFFF8FAFC,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                              ),
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  InkWell(
                                                                    onTap: () async {
                                                                      final profile = await repo.fetchMemberPublicProfile(
                                                                        sessionId:
                                                                            widget.sessionId,
                                                                        userId:
                                                                            comment.userId,
                                                                      );
                                                                      if (!mounted) {
                                                                        return;
                                                                      }
                                                                      showDialog<
                                                                        void
                                                                      >(
                                                                        context:
                                                                            this.context,
                                                                        builder:
                                                                            (
                                                                              context,
                                                                            ) => AlertDialog(
                                                                              title: const Text(
                                                                                'Member Profile',
                                                                              ),
                                                                              content: Text(
                                                                                profile ==
                                                                                        null
                                                                                    ? 'Profile unavailable.'
                                                                                    : '${profile.displayName}\n${profile.role}\n${profile.email}',
                                                                              ),
                                                                            ),
                                                                      );
                                                                    },
                                                                    child: Text(
                                                                      comment
                                                                          .displayName,
                                                                      style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w800,
                                                                        color: Color(
                                                                          0xFF0D9488,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 2,
                                                                  ),
                                                                  Text(
                                                                    comment
                                                                        .text,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextField(
                                                          controller:
                                                              _commentController,
                                                          maxLength: 250,
                                                          decoration:
                                                              const InputDecoration(
                                                                counterText: '',
                                                                hintText:
                                                                    'Comment...',
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      IconButton.filled(
                                                        onPressed: () async {
                                                          await repo.sendComment(
                                                            sessionId: widget
                                                                .sessionId,
                                                            text:
                                                                _commentController
                                                                    .text,
                                                          );
                                                          _commentController
                                                              .clear();
                                                        },
                                                        style:
                                                            IconButton.styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                    0xFF0D9488,
                                                                  ),
                                                            ),
                                                        icon: const Icon(
                                                          Icons.send_rounded,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 8,
                                                    children:
                                                        const [
                                                              '\u2764\ufe0f',
                                                              '\u{1F525}',
                                                              '\u{1F44F}',
                                                              '\u{1F499}',
                                                              '\u{1F389}',
                                                              '\u{1F64C}',
                                                            ]
                                                            .map(
                                                              (
                                                                emoji,
                                                              ) => OutlinedButton(
                                                                onPressed: () async {
                                                                  try {
                                                                    await repo.sendReaction(
                                                                      sessionId:
                                                                          widget
                                                                              .sessionId,
                                                                      emoji:
                                                                          emoji,
                                                                    );
                                                                  } catch (
                                                                    error
                                                                  ) {
                                                                    if (!mounted) {
                                                                      return;
                                                                    }
                                                                    showModernBannerFromSnackBar(
                                                                      this.context,
                                                                      SnackBar(
                                                                        content: Text(
                                                                          error.toString().replaceFirst(
                                                                            'Exception: ',
                                                                            '',
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    );
                                                                  }
                                                                },
                                                                child: Text(
                                                                  emoji,
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            18,
                                                                      ),
                                                                ),
                                                              ),
                                                            )
                                                            .toList(
                                                              growable: false,
                                                            ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    ..._bursts.map(
                                      (burst) => Positioned(
                                        right: burst.right,
                                        bottom: 24,
                                        child: _BurstWidget(
                                          key: ValueKey('burst_${burst.id}'),
                                          emoji: burst.emoji,
                                          onDone: () {
                                            _bursts.removeWhere(
                                              (entry) => entry.id == burst.id,
                                            );
                                            if (mounted) {
                                              setState(() {});
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF14B8A6)),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _LiveStatusChip extends StatelessWidget {
  const _LiveStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LivePersonaCard extends StatelessWidget {
  const _LivePersonaCard({
    required this.name,
    required this.badge,
    required this.status,
    required this.palette,
    required this.initials,
    this.isPrimary = false,
    this.muted = false,
  });

  final String name;
  final String badge;
  final String status;
  final List<Color> palette;
  final String initials;
  final bool isPrimary;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final avatarSize = isPrimary ? 132.0 : 96.0;
    final nameSize = isPrimary ? 26.0 : 16.0;
    return SizedBox(
      width: isPrimary ? 260 : 170,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: avatarSize + 18,
            height: avatarSize + 18,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: avatarSize + 18,
                  height: avatarSize + 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.first.withValues(alpha: 0.14),
                    boxShadow: [
                      BoxShadow(
                        color: palette.first.withValues(alpha: 0.22),
                        blurRadius: 38,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: palette,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: 5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isPrimary ? 36 : 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (muted)
                  Positioned(
                    right: 12,
                    bottom: 14,
                    child: Container(
                      width: isPrimary ? 34 : 28,
                      height: isPrimary ? 34 : 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: Icon(
                        Icons.mic_off_rounded,
                        size: isPrimary ? 18 : 16,
                        color: const Color(0xFF0E9B90),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E9B90),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x320E9B90),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Text(
                      badge.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: nameSize,
              fontWeight: isPrimary ? FontWeight.w300 : FontWeight.w700,
              color: const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 4.2,
              color: Color(0xFF67D3D0),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveControlDock extends StatelessWidget {
  const _LiveControlDock({
    required this.isHost,
    required this.isSpeaker,
    required this.isListener,
    required this.micEnabled,
    required this.paused,
    required this.requestPending,
    required this.onToggleMic,
    required this.onPauseResume,
    required this.onRequestMic,
    required this.onReact,
    required this.onLeave,
  });

  final bool isHost;
  final bool isSpeaker;
  final bool isListener;
  final bool micEnabled;
  final bool paused;
  final bool requestPending;
  final VoidCallback? onToggleMic;
  final VoidCallback? onPauseResume;
  final VoidCallback? onRequestMic;
  final VoidCallback onReact;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    void addDivider() {
      if (items.isNotEmpty) {
        items.add(
          Container(width: 1, height: 28, color: const Color(0x140F172A)),
        );
      }
    }

    if (isHost || isSpeaker) {
      addDivider();
      items.add(
        _LiveDockButton(
          icon: micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
          onTap: onToggleMic,
          active: micEnabled,
          tooltip: micEnabled ? 'Mute mic' : 'Enable mic',
        ),
      );
    }

    if (isHost) {
      addDivider();
      items.add(
        _LiveDockButton(
          icon: paused
              ? Icons.play_arrow_rounded
              : Icons.pause_circle_outline_rounded,
          onTap: onPauseResume,
          tooltip: paused ? 'Resume live' : 'Pause live',
        ),
      );
    }

    if (isListener) {
      addDivider();
      items.add(
        _LiveDockButton(
          icon: requestPending
              ? Icons.hourglass_top_rounded
              : Icons.front_hand_outlined,
          onTap: requestPending ? null : onRequestMic,
          tooltip: requestPending ? 'Mic requested' : 'Request mic',
        ),
      );
    }

    addDivider();
    items.add(
      _LiveDockButton(
        icon: Icons.favorite_border_rounded,
        onTap: onReact,
        tooltip: 'Send reaction',
      ),
    );

    addDivider();
    items.add(
      _LiveDockButton(
        icon: Icons.logout_rounded,
        onTap: onLeave,
        tooltip: 'Leave room',
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

class _LiveDockButton extends StatelessWidget {
  const _LiveDockButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? const Color(0x1F0E9B90)
                : onTap == null
                ? const Color(0xFFF1F5F9)
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            color: onTap == null
                ? const Color(0xFFB6C3D4)
                : const Color(0xFF58C8C4),
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _ReactionBubble extends StatelessWidget {
  const _ReactionBubble({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0x140EA5A0)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        backgroundColor: Colors.white.withValues(alpha: 0.8),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 20)),
    );
  }
}

class _Burst {
  const _Burst({required this.id, required this.emoji, required this.right});
  final String id;
  final String emoji;
  final double right;
}

class _BurstWidget extends StatefulWidget {
  const _BurstWidget({super.key, required this.emoji, required this.onDone});
  final String emoji;
  final VoidCallback onDone;

  @override
  State<_BurstWidget> createState() => _BurstWidgetState();
}

class _BurstWidgetState extends State<_BurstWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();
  late final Animation<double> _rise = Tween<double>(
    begin: 0,
    end: -220,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, _rise.value),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

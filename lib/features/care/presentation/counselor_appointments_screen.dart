import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class CounselorAppointmentsScreen extends ConsumerWidget {
  const CounselorAppointmentsScreen({super.key});

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return const Color(0xFFD97706);
      case AppointmentStatus.confirmed:
        return const Color(0xFF0369A1);
      case AppointmentStatus.completed:
        return const Color(0xFF059669);
      case AppointmentStatus.cancelled:
        return const Color(0xFFDC2626);
      case AppointmentStatus.noShow:
        return const Color(0xFF7C3AED);
    }
  }

  Future<Map<String, dynamic>?> _promptCompletionDetails(
    BuildContext context,
  ) async {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => const _CompletionDetailsDialog(),
    );
  }

  Future<Map<String, dynamic>?> _promptNoShowDetails(BuildContext context) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Mark No-show'),
          content: const Text('Who missed this session?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Back'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop({'attendanceStatus': 'student_no_show'}),
              child: const Text('Student No-show'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop({'attendanceStatus': 'counselor_no_show'}),
              child: const Text('Counselor No-show'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptCancellationReason(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Appointment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Optionally share a short reason with the student.'),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'Example: I have an urgent conflict this morning.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Cancel Session'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    AppointmentRecord appointment,
    AppointmentStatus status,
  ) async {
    String? cancellationMessage;
    String? attendanceStatus;
    String? sessionNote;
    List<String> actionItems = const <String>[];
    List<String> goals = const <String>[];
    if (status == AppointmentStatus.cancelled) {
      final decision = await _promptCancellationReason(context);
      if (!context.mounted || decision == null) {
        return;
      }
      cancellationMessage = decision;
    }
    if (status == AppointmentStatus.noShow) {
      final details = await _promptNoShowDetails(context);
      if (!context.mounted || details == null) {
        return;
      }
      attendanceStatus = details['attendanceStatus'] as String?;
    }
    if (status == AppointmentStatus.completed) {
      final details = await _promptCompletionDetails(context);
      if (!context.mounted || details == null) {
        return;
      }
      sessionNote = details['sessionNote'] as String?;
      actionItems = (details['actionItems'] as List<dynamic>)
          .map((entry) => entry.toString())
          .toList(growable: false);
      goals = (details['recommendedGoals'] as List<dynamic>)
          .map((entry) => entry.toString())
          .toList(growable: false);
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .updateAppointmentByCounselor(
            appointment: appointment,
            newStatus: status,
            counselorCancelMessage: cancellationMessage,
            attendanceStatus: attendanceStatus,
            counselorSessionNote: sessionNote,
            counselorActionItems: actionItems,
            recommendedGoals: goals,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AppointmentStatus.cancelled
                ? 'Appointment cancelled and student notified.'
                : status == AppointmentStatus.noShow
                ? 'No-show status saved.'
                : 'Appointment marked as ${status.name}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final counselorId = profile?.id ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('Counselor Appointments'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackToHomeButton(),
      ),
      child: profile == null || profile.role != UserRole.counselor
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('This page is available only for counselors.'),
              ),
            )
          : StreamBuilder<List<AppointmentRecord>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselorAppointments(
                    institutionId: institutionId,
                    counselorId: counselorId,
                  ),
              builder: (context, snapshot) {
                final appointments = snapshot.data ?? const [];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    appointments.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (appointments.isEmpty) {
                  return const GlassCard(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No appointments yet.'),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: appointments
                      .map(
                        (appointment) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          appointment.studentName ??
                                              appointment.studentId,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusColor(
                                            appointment.status,
                                          ).withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          appointment.status.name,
                                          style: TextStyle(
                                            color: _statusColor(
                                              appointment.status,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Start: ${_formatDate(appointment.startAt)}',
                                  ),
                                  Text(
                                    'End: ${_formatDate(appointment.endAt)}',
                                  ),
                                  if (appointment.status ==
                                          AppointmentStatus.noShow &&
                                      (appointment.attendanceStatus ?? '')
                                          .trim()
                                          .isNotEmpty)
                                    Text(
                                      'Attendance: ${appointment.attendanceStatus}',
                                    ),
                                  if (appointment.status ==
                                          AppointmentStatus.cancelled &&
                                      (appointment.counselorCancelMessage ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF7ED),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Message sent: ${appointment.counselorCancelMessage!.trim()}',
                                        style: const TextStyle(
                                          color: Color(0xFF9A3412),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (appointment.status ==
                                          AppointmentStatus.completed &&
                                      (appointment.counselorSessionNote ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Session note: ${appointment.counselorSessionNote!.trim()}',
                                        style: const TextStyle(
                                          color: Color(0xFF0C4A6E),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (appointment.status ==
                                          AppointmentStatus.completed &&
                                      appointment
                                          .counselorActionItems
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Action items: ${appointment.counselorActionItems.join(', ')}',
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (appointment.status ==
                                          AppointmentStatus.pending)
                                        OutlinedButton(
                                          onPressed: () => _updateStatus(
                                            context,
                                            ref,
                                            appointment,
                                            AppointmentStatus.confirmed,
                                          ),
                                          child: const Text('Confirm'),
                                        ),
                                      if (appointment.status ==
                                              AppointmentStatus.pending ||
                                          appointment.status ==
                                              AppointmentStatus.confirmed)
                                        OutlinedButton(
                                          onPressed: () => _updateStatus(
                                            context,
                                            ref,
                                            appointment,
                                            AppointmentStatus.cancelled,
                                          ),
                                          child: const Text('Cancel'),
                                        ),
                                      if (appointment.status ==
                                          AppointmentStatus.confirmed)
                                        OutlinedButton(
                                          onPressed: () => _updateStatus(
                                            context,
                                            ref,
                                            appointment,
                                            AppointmentStatus.noShow,
                                          ),
                                          child: const Text('Mark No-show'),
                                        ),
                                      if (appointment.status ==
                                          AppointmentStatus.confirmed)
                                        ElevatedButton(
                                          onPressed: () => _updateStatus(
                                            context,
                                            ref,
                                            appointment,
                                            AppointmentStatus.completed,
                                          ),
                                          child: const Text('Mark Completed'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
    );
  }
}

enum _VoiceInputField { sessionNote, actionItems, careGoals }

class _CompletionDetailsDialog extends StatefulWidget {
  const _CompletionDetailsDialog();

  @override
  State<_CompletionDetailsDialog> createState() =>
      _CompletionDetailsDialogState();
}

class _CompletionDetailsDialogState extends State<_CompletionDetailsDialog> {
  final _noteController = TextEditingController();
  final _actionItemsController = TextEditingController();
  final _goalsController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _isListening = false;
  bool _isInitializingVoice = false;
  _VoiceInputField? _activeField;
  String _baselineText = '';
  String? _voiceError;
  bool _permissionPromptShown = false;

  @override
  void initState() {
    super.initState();
    _initializeVoice(promptIfUnavailable: true);
  }

  @override
  void dispose() {
    _speech.stop();
    _noteController.dispose();
    _actionItemsController.dispose();
    _goalsController.dispose();
    super.dispose();
  }

  Future<void> _initializeVoice({bool promptIfUnavailable = false}) async {
    if (mounted) {
      setState(() {
        _isInitializingVoice = true;
      });
    }
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) {
            return;
          }
          if (status == 'notListening' || status == 'done') {
            setState(() {
              _isListening = false;
              _activeField = null;
            });
          }
        },
        onError: (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isListening = false;
            _activeField = null;
            _voiceError = _friendlyVoiceError(error.errorMsg);
          });
        },
      );
      if (!mounted) {
        return;
      }
      final rawError = _speech.lastError?.errorMsg;
      setState(() {
        _speechReady = ready;
        if (!ready) {
          _voiceError = _friendlyVoiceError(rawError);
        } else {
          _voiceError = null;
        }
        _isInitializingVoice = false;
      });
      if (!ready && promptIfUnavailable && _shouldPromptPermission(rawError)) {
        _showPermissionPromptOnce();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = false;
        _voiceError = _friendlyVoiceError(null);
        _isInitializingVoice = false;
      });
      if (promptIfUnavailable && _shouldPromptPermission(null)) {
        _showPermissionPromptOnce();
      }
    }
  }

  bool _isUnsupportedError(String? rawError) {
    final normalized = (rawError ?? '').toLowerCase();
    return normalized.contains('not supported') ||
        normalized.contains('speech_not_supported') ||
        normalized.contains('unsupported');
  }

  bool _isPermissionError(String? rawError) {
    final normalized = (rawError ?? '').toLowerCase();
    return normalized.contains('not-allowed') ||
        normalized.contains('service-not-allowed') ||
        normalized.contains('permission');
  }

  bool _shouldPromptPermission(String? rawError) {
    if (_isUnsupportedError(rawError)) {
      return false;
    }
    return true;
  }

  String _friendlyVoiceError(String? rawError) {
    if (_isUnsupportedError(rawError)) {
      if (kIsWeb) {
        return 'Voice dictation is not supported in this browser. Use latest Chrome or Edge.';
      }
      return 'Voice dictation is not supported on this device.';
    }
    if (_isPermissionError(rawError)) {
      if (kIsWeb) {
        return 'Microphone is blocked for this site. Allow mic in browser settings and reload this tab.';
      }
      return 'Microphone permission is required for voice dictation.';
    }
    if (rawError != null && rawError.trim().isNotEmpty) {
      return 'Voice input error: $rawError';
    }
    if (kIsWeb) {
      return 'Voice input is unavailable on web right now. Check browser support and microphone access.';
    }
    return 'Voice input could not start on this device.';
  }

  void _showPermissionPromptOnce() {
    if (_permissionPromptShown || !mounted) {
      return;
    }
    _permissionPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final shouldRetry = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Enable Microphone'),
            content: const Text(
              'To auto-fill text while you speak, allow microphone access for MindNest.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Enable Mic'),
              ),
            ],
          );
        },
      );
      if (!mounted || shouldRetry != true) {
        return;
      }
      await _initializeVoice();
      if (!mounted || _speechReady) {
        return;
      }
      setState(() {
        _voiceError =
            'Microphone still unavailable. Enable it in system app settings and try again.';
      });
    });
  }

  TextEditingController _controllerFor(_VoiceInputField field) {
    switch (field) {
      case _VoiceInputField.sessionNote:
        return _noteController;
      case _VoiceInputField.actionItems:
        return _actionItemsController;
      case _VoiceInputField.careGoals:
        return _goalsController;
    }
  }

  Future<void> _toggleListening(_VoiceInputField field) async {
    if (!_speechReady) {
      await _initializeVoice();
      if (!mounted || _speechReady) {
        return;
      }
      setState(() {
        _voiceError = _friendlyVoiceError(_speech.lastError?.errorMsg);
      });
      return;
    }
    if (_isListening && _activeField == field) {
      await _speech.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _activeField = null;
      });
      return;
    }

    if (_isListening) {
      await _speech.stop();
    }

    final controller = _controllerFor(field);
    _baselineText = controller.text.trim();
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceError = null;
      _isListening = true;
      _activeField = field;
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) {
          return;
        }
        final transcript = result.recognizedWords.trim();
        final combined = transcript.isEmpty
            ? _baselineText
            : _baselineText.isEmpty
            ? transcript
            : '$_baselineText $transcript';

        final activeField = _activeField;
        if (activeField == null) {
          return;
        }
        final activeController = _controllerFor(activeField);
        activeController.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );

        if (result.finalResult) {
          setState(() {
            _isListening = false;
            _activeField = null;
          });
        }
      },
      listenFor: const Duration(minutes: 3),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  List<String> _splitListInput(String rawValue) {
    return rawValue
        .split(RegExp(r'[,\n;]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  String _voiceButtonLabel(_VoiceInputField field) {
    final isActive = _isListening && _activeField == field;
    return isActive ? 'Stop Recording' : 'Use Voice';
  }

  IconData _voiceButtonIcon(_VoiceInputField field) {
    final isActive = _isListening && _activeField == field;
    return isActive ? Icons.stop_circle_rounded : Icons.mic_rounded;
  }

  Widget _buildVoiceField({
    required _VoiceInputField field,
    required String label,
    required String hint,
    required TextEditingController controller,
    int minLines = 1,
    int maxLines = 2,
    int? maxLength,
  }) {
    final isActive = _isListening && _activeField == field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _toggleListening(field),
              icon: Icon(_voiceButtonIcon(field), size: 18),
              label: Text(_voiceButtonLabel(field)),
              style: TextButton.styleFrom(
                foregroundColor: isActive
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0D9488),
              ),
            ),
          ],
        ),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Complete Session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add post-session notes and action items. Use the microphone to dictate live.',
            ),
            const SizedBox(height: 10),
            if (_voiceError != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  _voiceError!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_isInitializingVoice) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 10),
            ],
            _buildVoiceField(
              field: _VoiceInputField.sessionNote,
              label: 'Session note',
              hint: 'Summary and recommendations for the student.',
              controller: _noteController,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
            ),
            const SizedBox(height: 8),
            _buildVoiceField(
              field: _VoiceInputField.actionItems,
              label: 'Action items',
              hint: 'Comma/newline separated. Example: Breathing exercise',
              controller: _actionItemsController,
              minLines: 2,
              maxLines: 4,
              maxLength: 400,
            ),
            const SizedBox(height: 8),
            _buildVoiceField(
              field: _VoiceInputField.careGoals,
              label: 'Care goals',
              hint: 'Comma/newline separated. Example: Improve sleep schedule',
              controller: _goalsController,
              minLines: 2,
              maxLines: 4,
              maxLength: 400,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Back'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop({
            'sessionNote': _noteController.text.trim(),
            'actionItems': _splitListInput(_actionItemsController.text),
            'recommendedGoals': _splitListInput(_goalsController.text),
          }),
          child: const Text('Complete'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/config/school_catalog.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class InstitutionPendingScreen extends ConsumerStatefulWidget {
  const InstitutionPendingScreen({super.key});

  @override
  ConsumerState<InstitutionPendingScreen> createState() =>
      _InstitutionPendingScreenState();
}

class _InstitutionPendingScreenState
    extends ConsumerState<InstitutionPendingScreen>
    with SingleTickerProviderStateMixin {
  bool _isResubmitting = false;
  bool _isSubmittingSchoolRequest = false;
  String? _selectedSchool;
  final _schoolRequestNameController = TextEditingController();
  final _schoolRequestMobileController = TextEditingController();
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    _schoolRequestNameController.dispose();
    _schoolRequestMobileController.dispose();
    super.dispose();
  }

  Future<void> _resubmit() async {
    final school = _selectedSchool?.trim() ?? '';
    if (school.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select your school to resubmit.')),
      );
      return;
    }
    setState(() => _isResubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .resubmitCurrentAdminInstitutionRequest(institutionName: school);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Request resubmitted. Approval usually takes about 30 minutes.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isResubmitting = false);
      }
    }
  }

  Future<void> _requestSchool() async {
    final schoolName = _schoolRequestNameController.text.trim();
    final mobile = _schoolRequestMobileController.text.trim();
    if (schoolName.length < 2 || mobile.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter school name and mobile number.')),
      );
      return;
    }
    setState(() => _isSubmittingSchoolRequest = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .submitSchoolRequest(schoolName: schoolName, mobileNumber: mobile);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('School request sent to owner.')),
      );
      _schoolRequestNameController.clear();
      _schoolRequestMobileController.clear();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingSchoolRequest = false);
      }
    }
  }

  Future<void> _openSchoolRequestSheet() async {
    _schoolRequestNameController.clear();
    _schoolRequestMobileController.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 14,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Material(
              color: const Color(0xFFF7FCFF),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.add_business_rounded,
                            color: Color(0xFF0369A1),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'School Not Listed',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Share your school details and we will review quickly.',
                      style: TextStyle(
                        color: Color(0xFF516784),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _schoolRequestNameController,
                      decoration: const InputDecoration(
                        labelText: 'School name',
                        prefixIcon: Icon(Icons.school_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _schoolRequestMobileController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmittingSchoolRequest
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSubmittingSchoolRequest
                                ? null
                                : _requestSchool,
                            icon: Icon(
                              _isSubmittingSchoolRequest
                                  ? Icons.hourglass_top_rounded
                                  : Icons.send_rounded,
                            ),
                            label: Text(
                              _isSubmittingSchoolRequest
                                  ? 'Sending...'
                                  : 'Send Request',
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
        );
      },
    );
  }

  String _statusTitle(String status) {
    if (status == 'declined') {
      return 'Action Needed';
    }
    if (status == 'approved') {
      return 'Approved';
    }
    return 'Pending Review';
  }

  String _statusHeadline(String status) {
    if (status == 'declined') {
      return 'Institution request declined';
    }
    if (status == 'approved') {
      return 'Institution approved';
    }
    return 'Institution request submitted';
  }

  List<Color> _statusGradient(String status) {
    if (status == 'declined') {
      return const [Color(0xFFFFE4E6), Color(0xFFFFF1F2)];
    }
    if (status == 'approved') {
      return const [Color(0xFFD1FAE5), Color(0xFFECFDF5)];
    }
    return const [Color(0xFFDBEAFE), Color(0xFFEFF6FF)];
  }

  Color _statusAccent(String status) {
    if (status == 'declined') {
      return const Color(0xFFBE123C);
    }
    if (status == 'approved') {
      return const Color(0xFF047857);
    }
    return const Color(0xFF0C4A6E);
  }

  @override
  Widget build(BuildContext context) {
    final institutionAsync = ref.watch(currentAdminInstitutionRequestProvider);
    return MindNestShell(
      maxWidth: 920,
      appBar: AppBar(
        title: const Text('Institution Approval'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go(AppRoute.home),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => confirmAndLogout(context: context, ref: ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
        ],
      ),
      child: institutionAsync.when(
        data: (institution) {
          final status = (institution?['status'] as String?) ?? 'pending';
          final isDeclined = status == 'declined';
          final review = institution?['review'];
          final declineReason = review is Map
              ? (review['declineReason'] as String?)
              : null;
          final institutionName =
              (institution?['name'] as String?) ?? 'Your institution';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _statusGradient(status),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            FadeTransition(
                              opacity: Tween<double>(begin: 0.7, end: 1)
                                  .animate(
                                    CurvedAnimation(
                                      parent: _pulseController,
                                      curve: Curves.easeInOut,
                                    ),
                                  ),
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.94, end: 1.06)
                                    .animate(
                                      CurvedAnimation(
                                        parent: _pulseController,
                                        curve: Curves.easeInOut,
                                      ),
                                    ),
                                child: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    isDeclined
                                        ? Icons.report_problem_rounded
                                        : Icons.verified_user_rounded,
                                    color: _statusAccent(status),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _statusTitle(status),
                                      style: TextStyle(
                                        color: _statusAccent(status),
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
                                      color: const Color(0x99FFFFFF),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'ETA: ~30 min',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          child: Text(
                            _statusHeadline(status),
                            key: ValueKey('status-headline-$status'),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$institutionName is under review. You can stay signed in while we process this request.',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _StatusStepChip(
                        title: 'Submitted',
                        icon: Icons.check_circle_rounded,
                        active: true,
                      ),
                      _StatusStepChip(
                        title: 'In Review',
                        icon: Icons.hourglass_top_rounded,
                        active: status != 'approved' && status != 'declined',
                      ),
                      _StatusStepChip(
                        title: isDeclined ? 'Needs Update' : 'Approved',
                        icon: isDeclined
                            ? Icons.refresh_rounded
                            : Icons.verified_rounded,
                        active: status == 'approved' || isDeclined,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: isDeclined
                    ? GlassCard(
                        key: const ValueKey('declined-flow'),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fix and Resubmit',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if ((declineReason ?? '').trim().isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F2),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFFECDD3),
                                    ),
                                  ),
                                  child: Text(
                                    'Reason: ${declineReason!.trim()}',
                                    style: const TextStyle(
                                      color: Color(0xFF9F1239),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedSchool,
                                decoration: const InputDecoration(
                                  hintText: 'Select school from approved list',
                                  prefixIcon: Icon(Icons.apartment_rounded),
                                ),
                                items: kHardcodedSchools
                                    .map(
                                      (school) => DropdownMenuItem<String>(
                                        value: school,
                                        child: Text(school),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: _isResubmitting
                                    ? null
                                    : (value) => setState(
                                        () => _selectedSchool = value,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _isResubmitting
                                        ? null
                                        : _openSchoolRequestSheet,
                                    icon: const Icon(
                                      Icons.add_business_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('School not listed?'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _isResubmitting
                                        ? null
                                        : _resubmit,
                                    icon: Icon(
                                      _isResubmitting
                                          ? Icons.hourglass_top_rounded
                                          : Icons.refresh_rounded,
                                    ),
                                    label: Text(
                                      _isResubmitting
                                          ? 'Resubmitting...'
                                          : 'Resubmit Request',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : GlassCard(
                        key: const ValueKey('pending-flow'),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.schedule_rounded,
                                  color: Color(0xFF0369A1),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'What happens next?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Your request is being verified. Once approved, your dashboard unlocks automatically and join codes become available.',
                                      style: TextStyle(
                                        color: Color(0xFF516784),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(error.toString()),
          ),
        ),
      ),
    );
  }
}

class _StatusStepChip extends StatelessWidget {
  const _StatusStepChip({
    required this.title,
    required this.icon,
    required this.active,
  });

  final String title;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? const Color(0xFFE0F2FE)
        : const Color(0xFFF8FAFC);
    final border = active ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0);
    final textColor = active
        ? const Color(0xFF0C4A6E)
        : const Color(0xFF64748B);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

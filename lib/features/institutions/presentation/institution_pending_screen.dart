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
    extends ConsumerState<InstitutionPendingScreen> {
  bool _isResubmitting = false;
  String? _selectedSchool;
  final _schoolRequestNameController = TextEditingController();
  final _schoolRequestMobileController = TextEditingController();

  @override
  void dispose() {
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
    }
  }

  Future<void> _openSchoolRequestDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('School not listed?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _schoolRequestNameController,
              decoration: const InputDecoration(labelText: 'School name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _schoolRequestMobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _requestSchool, child: const Text('Send')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final institutionAsync = ref.watch(currentAdminInstitutionRequestProvider);
    return MindNestShell(
      maxWidth: 780,
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
          final review = institution?['review'];
          final declineReason = review is Map
              ? (review['declineReason'] as String?)
              : null;
          final institutionName =
              (institution?['name'] as String?) ?? 'Your institution';
          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status == 'declined'
                        ? 'Institution request declined'
                        : 'Institution request pending',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: status == 'declined'
                          ? Colors.red.shade700
                          : const Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$institutionName is under review. Approval usually takes about 30 minutes.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF516784),
                    ),
                  ),
                  if (status == 'declined' &&
                      (declineReason ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFECDD3)),
                      ),
                      child: Text(
                        'Decline reason: ${declineReason!.trim()}',
                        style: const TextStyle(
                          color: Color(0xFF9F1239),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Edit and Resubmit',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedSchool,
                      decoration: const InputDecoration(
                        hintText: 'Select school',
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
                          : (value) => setState(() => _selectedSchool = value),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _isResubmitting
                          ? null
                          : _openSchoolRequestDialog,
                      icon: const Icon(Icons.add_business_rounded, size: 18),
                      label: const Text('School not listed?'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _isResubmitting ? null : _resubmit,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        _isResubmitting
                            ? 'Resubmitting...'
                            : 'Resubmit Request',
                      ),
                    ),
                  ],
                ],
              ),
            ),
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

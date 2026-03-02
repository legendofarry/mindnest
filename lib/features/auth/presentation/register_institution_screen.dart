// features/auth/presentation/register_institution_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/config/school_catalog.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class RegisterInstitutionScreen extends ConsumerStatefulWidget {
  const RegisterInstitutionScreen({super.key});

  @override
  ConsumerState<RegisterInstitutionScreen> createState() =>
      _RegisterInstitutionScreenState();
}

class _RegisterInstitutionScreenState
    extends ConsumerState<RegisterInstitutionScreen> {
  static const _desktopBreakpoint = 1100.0;
  static const _stepCount = 3;
  final _formKey = GlobalKey<FormState>();
  final _adminNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _schoolRequestNameController = TextEditingController();
  final _schoolRequestMobileController = TextEditingController();
  String? _selectedSchoolName;
  int? _currentStep = 0;
  bool _isSubmitting = false;
  bool _isSubmittingSchoolRequest = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  int get _activeStep {
    final current = _currentStep ?? 0;
    if (current < 0) {
      return 0;
    }
    if (current >= _stepCount) {
      return _stepCount - 1;
    }
    return current;
  }

  @override
  void dispose() {
    _adminNameController.dispose();
    _emailController.dispose();
    _adminPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _schoolRequestNameController.dispose();
    _schoolRequestMobileController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final payloadError = _validateSubmissionPayload();
    if (payloadError != null) {
      _showMessage(payloadError.message);
      if (mounted && _activeStep != payloadError.step) {
        setState(() => _currentStep = payloadError.step);
      }
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .createInstitutionAdminAccount(
            adminName: _adminNameController.text.trim(),
            adminEmail: _emailController.text.trim(),
            adminPhoneNumber: _adminPhoneController.text.trim(),
            password: _passwordController.text,
            institutionName: (_selectedSchoolName ?? '').trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Institution request submitted. Approval usually takes about 30 minutes.',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (mounted) {
        context.go(AppRoute.verifyEmail);
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(error.message ?? 'Institution registration failed.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  _StepValidationError? _validateSubmissionPayload() {
    if ((_selectedSchoolName ?? '').trim().isEmpty) {
      return const _StepValidationError(
        step: 0,
        message: 'Select your school from the list.',
      );
    }
    if (_adminNameController.text.trim().length < 2) {
      return const _StepValidationError(step: 1, message: 'Enter admin name.');
    }
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return const _StepValidationError(
        step: 1,
        message: 'Enter a valid email.',
      );
    }
    if (_adminPhoneController.text.trim().length < 6) {
      return const _StepValidationError(
        step: 1,
        message: 'Enter a valid phone number.',
      );
    }
    if (_passwordController.text.length < 8) {
      return const _StepValidationError(
        step: 2,
        message: 'Use at least 8 characters.',
      );
    }
    if (_confirmPasswordController.text != _passwordController.text) {
      return const _StepValidationError(
        step: 2,
        message: 'Passwords do not match.',
      );
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSchoolNotListedDialog() async {
    if (_isSubmittingSchoolRequest) {
      return;
    }
    _schoolRequestNameController.text = _schoolRequestNameController.text
        .trim();
    _schoolRequestMobileController.text = _schoolRequestMobileController.text
        .trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('School not listed?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _schoolRequestNameController,
                decoration: const InputDecoration(
                  labelText: 'School name',
                  hintText: 'Example High School',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _schoolRequestMobileController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '+254...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isSubmittingSchoolRequest
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isSubmittingSchoolRequest
                  ? null
                  : _submitSchoolRequest,
              child: Text(
                _isSubmittingSchoolRequest ? 'Sending...' : 'Send request',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitSchoolRequest() async {
    final schoolName = _schoolRequestNameController.text.trim();
    final mobileNumber = _schoolRequestMobileController.text.trim();
    if (schoolName.length < 2 || mobileNumber.length < 6) {
      _showMessage('Enter school name and mobile number.');
      return;
    }
    setState(() => _isSubmittingSchoolRequest = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .submitSchoolRequest(
            schoolName: schoolName,
            mobileNumber: mobileNumber,
            requesterName: _adminNameController.text,
            requesterEmail: _emailController.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
        _showMessage(
          'School request sent. We will review and contact you shortly.',
        );
        _schoolRequestNameController.clear();
        _schoolRequestMobileController.clear();
      }
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingSchoolRequest = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: 'Build your institution',
        heroBaseText: 'wellness workspace.',
        heroDescription:
            'Create your admin account, generate join access, and onboard '
            'counselors and members in one secure flow.',
        metrics: const [
          AuthDesktopMetric(value: '1+', label: 'INSTITUTIONS'),
          AuthDesktopMetric(value: '24/7', label: 'SUPPORT READY'),
        ],
        formChild: _buildFormContent(context),
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      child: _buildFormCard(context),
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_isSubmitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_activeStep < _stepCount - 1) {
      setState(() => _currentStep = _activeStep + 1);
      return;
    }
    await _submit();
  }

  void _handleBackAction() {
    if (_isSubmitting) {
      return;
    }
    if (_activeStep == 0) {
      context.go(AppRoute.login);
      return;
    }
    setState(() => _currentStep = _activeStep - 1);
  }

  Widget _buildStepIndicator() {
    final currentStep = _activeStep;
    return Row(
      children: List<Widget>.generate(_stepCount, (index) {
        final isActive = index == currentStep;
        final isCompleted = index < currentStep;
        final fillColor = isCompleted || isActive
            ? const Color(0xFF0E9B90)
            : const Color(0xFFD7E3EF);
        final textColor = isCompleted || isActive
            ? Colors.white
            : const Color(0xFF8EA3BB);
        return Expanded(
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              if (index < _stepCount - 1)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    height: 2,
                    color: index < currentStep
                        ? const Color(0xFF0E9B90)
                        : const Color(0xFFD7E3EF),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  String _stepTitle() {
    switch (_activeStep) {
      case 0:
        return 'Step 1 of 3 - Institution';
      case 1:
        return 'Step 2 of 3 - Admin Details';
      default:
        return 'Step 3 of 3 - Security';
    }
  }

  String _stepDescription() {
    switch (_activeStep) {
      case 0:
        return 'Choose your institution from the approved catalog.';
      case 1:
        return 'Add administrator contact details for approval and onboarding.';
      default:
        return 'Create a secure password and confirm it to continue.';
    }
  }

  Widget _buildStepFields() {
    switch (_activeStep) {
      case 0:
        return _buildInstitutionStep();
      case 1:
        return _buildAdminDetailsStep();
      default:
        return _buildSecurityStep();
    }
  }

  Widget _buildInstitutionStep() {
    return Column(
      key: const ValueKey('institution-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'INSTITUTION NAME'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedSchoolName,
          decoration: const InputDecoration(
            hintText: 'Select school',
            prefixIcon: Icon(Icons.apartment_rounded),
          ),
          isExpanded: true,
          items: kHardcodedSchools
              .map(
                (school) => DropdownMenuItem<String>(
                  value: school,
                  child: Text(school, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: _isSubmitting
              ? null
              : (value) => setState(() => _selectedSchoolName = value),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return 'Select your school from the list.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isSubmitting ? null : _openSchoolNotListedDialog,
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: const Text('School not listed?'),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminDetailsStep() {
    return Column(
      key: const ValueKey('admin-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'ADMIN FULL NAME'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: TextFormField(
            controller: _adminNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Alex Rivera',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (value) {
              if ((value ?? '').trim().length < 2) {
                return 'Enter admin name.';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel(text: 'ADMIN EMAIL ADDRESS'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'alex@example.com',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty || !trimmed.contains('@')) {
                return 'Enter a valid email.';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel(text: 'ADMIN PHONE NUMBER'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: TextFormField(
            controller: _adminPhoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '+254...',
              prefixIcon: Icon(Icons.phone_rounded),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.length < 6) {
                return 'Enter a valid phone number.';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This number may be called to help confirm institution eligibility.',
          style: TextStyle(
            color: Color(0xFF6A7D96),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityStep() {
    return Column(
      key: const ValueKey('security-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'PASSWORD'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_confirmPasswordController.text.isNotEmpty) {
                _formKey.currentState?.validate();
              }
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Minimum 8 characters',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
                icon: Icon(
                  _isPasswordVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
            ),
            validator: (value) {
              if ((value ?? '').length < 8) {
                return 'Use at least 8 characters.';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel(text: 'CONFIRM PASSWORD'),
        const SizedBox(height: 8),
        _RoundedInput(
          child: TextFormField(
            controller: _confirmPasswordController,
            obscureText: !_isConfirmPasswordVisible,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handlePrimaryAction(),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Re-enter password',
              prefixIcon: const Icon(Icons.verified_user_outlined),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                  });
                },
                icon: Icon(
                  _isConfirmPasswordVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
            ),
            validator: (value) {
              if ((value ?? '').isEmpty) {
                return 'Confirm your password.';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match.';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Use 8+ characters with a mix of letters and numbers.',
          style: TextStyle(
            color: Color(0xFF6A7D96),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFormContent(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Register Institution',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF071937),
              fontSize: 24,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _stepTitle(),
            style: const TextStyle(
              color: Color(0xFF0E9B90),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _stepDescription(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF516784),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _buildStepIndicator(),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _buildStepFields(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : _handleBackAction,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    side: const BorderSide(color: Color(0xFFBED0E4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _activeStep == 0 ? 'Back to Login' : 'Back',
                    style: const TextStyle(
                      color: Color(0xFF4E627A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0E9B90), Color(0xFF18A89D)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x3C72ECDC),
                        blurRadius: 22,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handlePrimaryAction,
                    style: ElevatedButton.styleFrom(
                      shadowColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _isSubmitting
                            ? 'Creating institution...'
                            : (_activeStep < _stepCount - 1
                                  ? 'Continue  ->'
                                  : 'Create Institution  ->'),
                        key: ValueKey('$_isSubmitting-$_activeStep'),
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFCFFFFFF),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: _buildFormContent(context),
    );
  }
}

class _StepValidationError {
  const _StepValidationError({required this.step, required this.message});

  final int step;
  final String message;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9AAAC0),
        letterSpacing: 1.6,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }
}

class _RoundedInput extends StatelessWidget {
  const _RoundedInput({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD2DCE9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

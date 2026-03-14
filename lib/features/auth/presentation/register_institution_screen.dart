// features/auth/presentation/register_institution_screen.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/config/school_catalog.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class RegisterInstitutionScreen extends ConsumerStatefulWidget {
  const RegisterInstitutionScreen({super.key});

  @override
  ConsumerState<RegisterInstitutionScreen> createState() =>
      _RegisterInstitutionScreenState();
}

class _RegisterInstitutionScreenState
    extends ConsumerState<RegisterInstitutionScreen>
    with SingleTickerProviderStateMixin {
  static const _kenyaPrefix = '+254';
  static const _desktopBreakpoint = 1100.0;
  static const _stepCount = 3;
  final _formKey = GlobalKey<FormState>();
  final _adminNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _additionalAdminPhoneController = TextEditingController();
  final _adminPhoneFocusNode = FocusNode();
  final _additionalAdminPhoneFocusNode = FocusNode();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _selectedSchoolId;
  int? _currentStep = 0;
  bool _isSubmitting = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _schoolFieldError = false;
  bool _adminNameFieldError = false;
  bool _adminEmailFieldError = false;
  bool _adminPhoneFieldError = false;
  bool _additionalAdminPhoneFieldError = false;
  String? _adminPhoneDuplicateError;
  String? _additionalAdminPhoneDuplicateError;
  bool _passwordFieldError = false;
  bool _confirmPasswordFieldError = false;
  String? _formError;
  int _adminPhoneCheckToken = 0;
  int _additionalAdminPhoneCheckToken = 0;

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 8, end: -4), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 2),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

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

  bool get _isPrimaryActionEnabled {
    if (_isSubmitting) {
      return false;
    }
    switch (_activeStep) {
      case 0:
        return (_selectedSchoolId ?? '').trim().isNotEmpty;
      case 1:
        final hasName = _adminNameController.text.trim().length >= 2;
        final email = _emailController.text.trim();
        final hasEmail = email.isNotEmpty && email.contains('@');
        final primaryPhone = _normalizeKenyaPhoneInput(
          _adminPhoneController.text,
        );
        final hasPhone = _isValidKenyaPhone(primaryPhone);
        final optionalPhone = _optionalPhoneValue(
          _additionalAdminPhoneController.text,
        );
        final hasValidOptionalPhone =
            optionalPhone == null || _isValidKenyaPhone(optionalPhone);
        final hasDistinctOptionalPhone =
            optionalPhone == null || optionalPhone != primaryPhone;
        return hasName &&
            hasEmail &&
            hasPhone &&
            hasValidOptionalPhone &&
            hasDistinctOptionalPhone &&
            _adminPhoneDuplicateError == null &&
            _additionalAdminPhoneDuplicateError == null;
      default:
        return _passwordController.text.length >= 8 &&
            _confirmPasswordController.text.isNotEmpty &&
            _confirmPasswordController.text == _passwordController.text;
    }
  }

  @override
  void initState() {
    super.initState();
    _adminPhoneController.text = _kenyaPrefix;
    _adminPhoneController.addListener(_enforceAdminPhonePrefix);
    _additionalAdminPhoneController.addListener(_enforceAdditionalAdminPhone);
    _adminPhoneFocusNode.addListener(_onAdminPhoneFocusChange);
    _additionalAdminPhoneFocusNode.addListener(
      _onAdditionalAdminPhoneFocusChange,
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _adminPhoneController.removeListener(_enforceAdminPhonePrefix);
    _additionalAdminPhoneController.removeListener(
      _enforceAdditionalAdminPhone,
    );
    _adminPhoneFocusNode.removeListener(_onAdminPhoneFocusChange);
    _additionalAdminPhoneFocusNode.removeListener(
      _onAdditionalAdminPhoneFocusChange,
    );
    _adminNameController.dispose();
    _emailController.dispose();
    _adminPhoneController.dispose();
    _additionalAdminPhoneController.dispose();
    _adminPhoneFocusNode.dispose();
    _additionalAdminPhoneFocusNode.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _enforceAdminPhonePrefix() {
    _enforceKenyaPrefix(_adminPhoneController);
  }

  void _enforceAdditionalAdminPhone() {
    final trimmed = _additionalAdminPhoneController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _enforceKenyaPrefix(_additionalAdminPhoneController);
  }

  void _enforceKenyaPrefix(TextEditingController controller) {
    final normalized = _normalizeKenyaPhoneInput(controller.text);
    if (controller.text == normalized) {
      return;
    }
    controller.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  String _normalizeKenyaPhoneInput(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('254')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '$_kenyaPrefix$digits';
  }

  bool _isValidKenyaPhone(String value) {
    return RegExp(r'^\+254\d{9}$').hasMatch(value);
  }

  void _onAdminPhoneFocusChange() {
    if (_adminPhoneFocusNode.hasFocus) {
      return;
    }
    unawaited(_checkAdminPhoneDuplicate());
  }

  void _onAdditionalAdminPhoneFocusChange() {
    if (_additionalAdminPhoneFocusNode.hasFocus) {
      return;
    }
    unawaited(_checkAdditionalAdminPhoneDuplicate());
  }

  Future<void> _checkAdminPhoneDuplicate() async {
    final normalized = _normalizeKenyaPhoneInput(_adminPhoneController.text);
    if (!_isValidKenyaPhone(normalized)) {
      if (_adminPhoneDuplicateError != null) {
        setState(() => _adminPhoneDuplicateError = null);
      }
      return;
    }

    final token = ++_adminPhoneCheckToken;
    try {
      final isAvailable = await ref
          .read(authRepositoryProvider)
          .isPhoneNumberAvailableForRegistration(normalized);
      if (!mounted || token != _adminPhoneCheckToken) {
        return;
      }
      setState(() {
        _adminPhoneDuplicateError = isAvailable
            ? null
            : 'This mobile number is already linked to another account.';
        if (_adminPhoneDuplicateError != null) {
          _formError = _adminPhoneDuplicateError;
        } else if (_formError ==
            'This mobile number is already linked to another account.') {
          _formError = null;
        }
      });
    } catch (_) {
      if (!mounted || token != _adminPhoneCheckToken) {
        return;
      }
      setState(() => _adminPhoneDuplicateError = null);
    }
  }

  Future<void> _checkAdditionalAdminPhoneDuplicate() async {
    final optionalPhone = _optionalPhoneValue(
      _additionalAdminPhoneController.text,
    );
    if (optionalPhone == null) {
      if (_additionalAdminPhoneDuplicateError != null) {
        setState(() => _additionalAdminPhoneDuplicateError = null);
      }
      return;
    }
    final normalized = _normalizeKenyaPhoneInput(optionalPhone);
    if (!_isValidKenyaPhone(normalized) ||
        normalized == _adminPhoneController.text.trim()) {
      if (_additionalAdminPhoneDuplicateError != null) {
        setState(() => _additionalAdminPhoneDuplicateError = null);
      }
      return;
    }

    final token = ++_additionalAdminPhoneCheckToken;
    try {
      final isAvailable = await ref
          .read(authRepositoryProvider)
          .isPhoneNumberAvailableForRegistration(normalized);
      if (!mounted || token != _additionalAdminPhoneCheckToken) {
        return;
      }
      setState(() {
        _additionalAdminPhoneDuplicateError = isAvailable
            ? null
            : 'This additional mobile is already linked to another account.';
        if (_additionalAdminPhoneDuplicateError != null) {
          _formError = _additionalAdminPhoneDuplicateError;
        } else if (_formError ==
            'This additional mobile is already linked to another account.') {
          _formError = null;
        }
      });
    } catch (_) {
      if (!mounted || token != _additionalAdminPhoneCheckToken) {
        return;
      }
      setState(() => _additionalAdminPhoneDuplicateError = null);
    }
  }

  Future<bool> _runAdminPhoneDuplicationChecks() async {
    await _checkAdminPhoneDuplicate();
    await _checkAdditionalAdminPhoneDuplicate();
    return _adminPhoneDuplicateError != null ||
        _additionalAdminPhoneDuplicateError != null;
  }

  String? _optionalPhoneValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _kenyaPrefix) {
      return null;
    }
    return trimmed;
  }

  Future<void> _openCatalogSchoolPicker() async {
    if (_isSubmitting) {
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CatalogSchoolPickerSheet(
        schools: kCatalogSchools,
        selectedSchoolId: _selectedSchoolId,
      ),
    );
    if (!mounted || selectedId == null) {
      return;
    }
    setState(() {
      _selectedSchoolId = selectedId;
      _schoolFieldError = false;
      _formError = null;
    });
  }

  Future<void> _submit() async {
    final stepError = _validateCurrentStep();
    if (stepError != null) {
      await _showFormError(stepError);
      return;
    }
    final selectedSchool = catalogSchoolById(_selectedSchoolId);
    if (selectedSchool == null) {
      setState(() => _schoolFieldError = true);
      await _showFormError('Please select your institution first.');
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
            additionalAdminPhoneNumber: _optionalPhoneValue(
              _additionalAdminPhoneController.text,
            ),
            password: _passwordController.text,
            institutionCatalogId: selectedSchool.id,
            institutionName: selectedSchool.name,
          );
      if (mounted) {
        context.go(
          Uri(
            path: AppRoute.verifyEmail,
            queryParameters: <String, String>{
              AppRoute.institutionNameQuery: selectedSchool.name,
            },
          ).toString(),
        );
      }
    } on FirebaseAuthException catch (error) {
      await _showFormError(error.message ?? 'Institution registration failed.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      if (message.toLowerCase().contains('already exists') ||
          message.toLowerCase().contains('pending approval')) {
        setState(() {
          _currentStep = 0;
          _schoolFieldError = true;
        });
      }
      await _showFormError(message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showFormError(String message) async {
    if (!mounted) {
      return;
    }
    setState(() => _formError = message);
    await _triggerShake();
  }

  Future<void> _triggerShake() async {
    if (!mounted) {
      return;
    }
    await _shakeController.forward(from: 0);
  }

  String? _validateCurrentStep() {
    switch (_activeStep) {
      case 0:
        final hasSchool = (_selectedSchoolId ?? '').trim().isNotEmpty;
        setState(() => _schoolFieldError = !hasSchool);
        if (!hasSchool) {
          return 'Please select your institution first.';
        }
        return null;
      case 1:
        final hasName = _adminNameController.text.trim().length >= 2;
        final email = _emailController.text.trim();
        final hasEmail = email.isNotEmpty && email.contains('@');
        final hasPhone = _isValidKenyaPhone(_adminPhoneController.text.trim());
        final optionalPhone = _optionalPhoneValue(
          _additionalAdminPhoneController.text,
        );
        final hasValidOptionalPhone =
            optionalPhone == null || _isValidKenyaPhone(optionalPhone);
        final hasDistinctOptionalPhone =
            optionalPhone == null ||
            optionalPhone != _adminPhoneController.text.trim();
        final hasDuplicateAdminPhone = _adminPhoneDuplicateError != null;
        final hasDuplicateAdditionalPhone =
            _additionalAdminPhoneDuplicateError != null;
        setState(() {
          _adminNameFieldError = !hasName;
          _adminEmailFieldError = !hasEmail;
          _adminPhoneFieldError = !hasPhone || hasDuplicateAdminPhone;
          _additionalAdminPhoneFieldError =
              !hasValidOptionalPhone ||
              !hasDistinctOptionalPhone ||
              hasDuplicateAdditionalPhone;
        });
        if (!hasName ||
            !hasEmail ||
            !hasPhone ||
            !hasValidOptionalPhone ||
            !hasDistinctOptionalPhone ||
            hasDuplicateAdminPhone ||
            hasDuplicateAdditionalPhone) {
          return 'Please correct the highlighted fields.';
        }
        return null;
      default:
        final hasPassword = _passwordController.text.length >= 8;
        final hasConfirm = _confirmPasswordController.text.isNotEmpty;
        final matches =
            _confirmPasswordController.text == _passwordController.text;
        setState(() {
          _passwordFieldError = !hasPassword;
          _confirmPasswordFieldError = !hasConfirm || !matches;
        });
        if (!hasPassword || !hasConfirm) {
          return 'Please correct the highlighted fields.';
        }
        if (!matches) {
          return 'Passwords do not match.';
        }
        return null;
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
          AuthDesktopMetric(value: '3+', label: 'INSTITUTIONS'),
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
    var stepError = _validateCurrentStep();
    if (stepError != null) {
      await _showFormError(stepError);
      return;
    }

    if (_activeStep == 1) {
      await _runAdminPhoneDuplicationChecks();
      stepError = _validateCurrentStep();
      if (stepError != null) {
        await _showFormError(stepError);
        return;
      }
    }

    if (_activeStep == 0) {
      try {
        final schoolId = (_selectedSchoolId ?? '').trim();
        final isAvailable = await ref
            .read(institutionRepositoryProvider)
            .isInstitutionCatalogIdAvailable(schoolId);
        if (!mounted) {
          return;
        }
        if (!isAvailable) {
          setState(() => _schoolFieldError = true);
          await _showFormError(
            'This institution already exists or is pending approval.',
          );
          return;
        }
      } catch (_) {
        await _showFormError(
          'We could not validate institution availability right now. Please try again.',
        );
        return;
      }
    }

    if (_activeStep < _stepCount - 1) {
      setState(() {
        _currentStep = _activeStep + 1;
        _formError = null;
      });
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
    setState(() {
      _currentStep = _activeStep - 1;
      _formError = null;
    });
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
    final selectedSchool = catalogSchoolById(_selectedSchoolId);
    return Column(
      key: const ValueKey('institution-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel(text: 'INSTITUTION NAME'),
        const SizedBox(height: 8),
        _CatalogSchoolPickerField(
          hasError: _schoolFieldError,
          selectedSchoolName: selectedSchool?.name,
          onTap: _openCatalogSchoolPicker,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isSubmitting
                ? null
                : () => context.go(AppRoute.registerInstitutionSchoolRequest),
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
          hasError: _adminNameFieldError,
          child: TextFormField(
            controller: _adminNameController,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {
              _adminNameFieldError = false;
              _formError = null;
            }),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Alex Rivera',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel(text: 'ADMIN EMAIL ADDRESS'),
        const SizedBox(height: 8),
        _RoundedInput(
          hasError: _adminEmailFieldError,
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {
              _adminEmailFieldError = false;
              _formError = null;
            }),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'alex@example.com',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel(text: 'ADMIN PHONE'),
                  const SizedBox(height: 8),
                  _RoundedInput(
                    hasError:
                        _adminPhoneFieldError ||
                        _adminPhoneDuplicateError != null,
                    child: TextFormField(
                      controller: _adminPhoneController,
                      focusNode: _adminPhoneFocusNode,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {
                        _adminPhoneFieldError = false;
                        _adminPhoneDuplicateError = null;
                        _formError = null;
                      }),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '+254...',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel(text: 'OTHER PHONE'),
                  const SizedBox(height: 8),
                  _RoundedInput(
                    hasError:
                        _additionalAdminPhoneFieldError ||
                        _additionalAdminPhoneDuplicateError != null,
                    child: TextFormField(
                      controller: _additionalAdminPhoneController,
                      focusNode: _additionalAdminPhoneFocusNode,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {
                        _additionalAdminPhoneFieldError = false;
                        _additionalAdminPhoneDuplicateError = null;
                        _formError = null;
                      }),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '+254...',
                        prefixIcon: Icon(Icons.phone_android_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel(text: 'PASSWORD'),
                  const SizedBox(height: 8),
                  _RoundedInput(
                    hasError: _passwordFieldError,
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        setState(() {
                          _passwordFieldError = false;
                          _formError = null;
                          if (_confirmPasswordController.text.isNotEmpty &&
                              _confirmPasswordController.text !=
                                  _passwordController.text) {
                            _confirmPasswordFieldError = true;
                          } else {
                            _confirmPasswordFieldError = false;
                          }
                        });
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
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel(text: 'CONFIRM PASSWORD'),
                  const SizedBox(height: 8),
                  _RoundedInput(
                    hasError: _confirmPasswordFieldError,
                    child: TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {
                        _confirmPasswordFieldError = false;
                        _formError = null;
                      }),
                      onFieldSubmitted: (_) {
                        if (_isPrimaryActionEnabled) {
                          unawaited(_handlePrimaryAction());
                        }
                      },
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Re-enter password',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible =
                                  !_isConfirmPasswordVisible;
                            });
                          },
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeOffset.value, 0),
          child: child,
        );
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _isSubmitting
                    ? null
                    : () => context.go(AppRoute.register),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 17,
                        color: Color(0xFF93A3BA),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Back to Register',
                        style: TextStyle(
                          color: Color(0xFF93A3BA),
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: (_formError == null || _formError!.trim().isEmpty)
                  ? const SizedBox(height: 18)
                  : Container(
                      key: ValueKey(_formError),
                      margin: const EdgeInsets.only(top: 14, bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECDD3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFBE123C),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: const TextStyle(
                                color: Color(0xFF9F1239),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
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
                if (_activeStep > 0) ...[
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
                      child: const Text(
                        'Back',
                        style: TextStyle(
                          color: Color(0xFF4E627A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: _activeStep > 0 ? 2 : 1,
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: _isPrimaryActionEnabled
                            ? const [Color(0xFF0E9B90), Color(0xFF18A89D)]
                            : const [Color(0xFFB8C5D6), Color(0xFFAAB8CB)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: _isPrimaryActionEnabled
                          ? const [
                              BoxShadow(
                                color: Color(0x3C72ECDC),
                                blurRadius: 22,
                                offset: Offset(0, 12),
                              ),
                            ]
                          : const [],
                    ),
                    child: ElevatedButton(
                      onPressed: _isPrimaryActionEnabled
                          ? _handlePrimaryAction
                          : null,
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
  const _RoundedInput({required this.child, this.hasError = false});

  final Widget child;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError ? const Color(0xFFFECDD3) : const Color(0xFFD2DCE9),
          width: hasError ? 1.2 : 1.0,
        ),
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

class _CatalogSchoolPickerField extends StatelessWidget {
  const _CatalogSchoolPickerField({
    required this.hasError,
    required this.selectedSchoolName,
    required this.onTap,
  });

  final bool hasError;
  final String? selectedSchoolName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? const Color(0xFFE11D48)
        : const Color(0xFF0E9B90);
    final placeholder = (selectedSchoolName ?? '').trim().isEmpty
        ? 'Select institution'
        : selectedSchoolName!.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: hasError ? 1.4 : 1.1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.apartment_rounded,
              color: hasError
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF475569),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedSchoolName == null
                        ? 'Approved catalog'
                        : 'Selected institution',
                    style: const TextStyle(
                      color: Color(0xFF9AAAC0),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selectedSchoolName == null
                          ? const Color(0xFF7B8CA4)
                          : const Color(0xFF071937),
                      fontSize: 17,
                      fontWeight: selectedSchoolName == null
                          ? FontWeight.w500
                          : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEFFFFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF0E9B90),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogSchoolPickerSheet extends StatefulWidget {
  const _CatalogSchoolPickerSheet({
    required this.schools,
    required this.selectedSchoolId,
  });

  final List<CatalogSchool> schools;
  final String? selectedSchoolId;

  @override
  State<_CatalogSchoolPickerSheet> createState() =>
      _CatalogSchoolPickerSheetState();
}

class _CatalogSchoolPickerSheetState extends State<_CatalogSchoolPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredSchools = widget.schools
        .where((school) => school.name.toLowerCase().contains(query))
        .toList(growable: false);

    return SafeArea(
      top: false,
      child: Container(
        height: 640,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD2DCE9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Select institution',
                style: TextStyle(
                  color: Color(0xFF071937),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Search the approved institution catalog and choose your school from the list below.',
                style: TextStyle(
                  color: Color(0xFF516784),
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD2DCE9)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search institution',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFDDE6F1)),
                  ),
                  child: filteredSchools.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No institution matches your search.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredSchools.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final school = filteredSchools[index];
                            final isSelected =
                                school.id == widget.selectedSchoolId;
                            return InkWell(
                              onTap: () => Navigator.of(context).pop(school.id),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFEFFFFC)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF0E9B90)
                                        : const Color(0xFFDCE6F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(
                                                0xFF0E9B90,
                                              ).withValues(alpha: 0.14)
                                            : const Color(0xFFE2E8F0),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.account_balance_rounded,
                                        color: isSelected
                                            ? const Color(0xFF0E9B90)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        school.name,
                                        style: const TextStyle(
                                          color: Color(0xFF071937),
                                          fontWeight: FontWeight.w700,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle_rounded
                                          : Icons.arrow_outward_rounded,
                                      color: isSelected
                                          ? const Color(0xFF0E9B90)
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

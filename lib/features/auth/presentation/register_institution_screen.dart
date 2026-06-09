// features/auth/presentation/register_institution_screen.dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
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
  static const _desktopBreakpoint = 1100.0;
  static const _stepCount = 3;
  final _formKey = GlobalKey<FormState>();
  final _adminNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _selectedSchoolId;
  int? _currentStep = 0;
  bool _isSubmitting = false;
  bool _isCheckingInstitutionAvailability = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _schoolFieldError = false;
  bool _adminNameFieldError = false;
  bool _adminEmailFieldError = false;
  bool _passwordFieldError = false;
  bool _confirmPasswordFieldError = false;
  String? _formError;

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

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _isFormBusy => _isSubmitting || _isCheckingInstitutionAvailability;

  bool get _isPrimaryActionEnabled {
    final authUser = ref.read(authStateChangesProvider).valueOrNull;
    final isLoggedIn = authUser != null;
    if (_isFormBusy) {
      return false;
    }
    switch (_activeStep) {
      case 0:
        return (_selectedSchoolId ?? '').trim().isNotEmpty;
      case 1:
        final hasName = _adminNameController.text.trim().length >= 2;
        final email = _emailController.text.trim();
        final hasEmail = email.isNotEmpty && email.contains('@');
        return isLoggedIn ? hasName : (hasName && hasEmail);
      default:
        if (isLoggedIn) {
          return true;
        }
        return _passwordController.text.length >= 8 &&
            _confirmPasswordController.text.isNotEmpty &&
            _confirmPasswordController.text == _passwordController.text;
    }
  }

  @override
  void initState() => super.initState();

  @override
  void dispose() {
    _shakeController.dispose();
    _adminNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _openCatalogSchoolPicker() async {
    if (_isFormBusy) {
      return;
    }
    Map<String, String> claimedInstitutionIdsBySchoolId =
        const <String, String>{};
    try {
      claimedInstitutionIdsBySchoolId = await ref
          .read(institutionRepositoryProvider)
          .getInstitutionCatalogClaims();
    } catch (_) {
      claimedInstitutionIdsBySchoolId = const <String, String>{};
    }

    if (!mounted) {
      return;
    }

    final useFloatingDialog =
        kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
    String? selectedId;
    if (useFloatingDialog) {
      selectedId = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierColor: const Color(0x73071A33),
        builder: (dialogContext) {
          final size = MediaQuery.sizeOf(dialogContext);
          final maxWidth = size.width >= 1280 ? 820.0 : 760.0;
          final maxHeight = (size.height - 72).clamp(480.0, 760.0);
          return Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Center(
                child: SizedBox(
                  width: maxWidth,
                  height: maxHeight.toDouble(),
                  child: _CatalogSchoolPickerSheet(
                    schools: kCatalogSchools,
                    selectedSchoolId: _selectedSchoolId,
                    claimedInstitutionIdsBySchoolId:
                        claimedInstitutionIdsBySchoolId,
                    desktopMode: true,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      selectedId = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _CatalogSchoolPickerSheet(
          schools: kCatalogSchools,
          selectedSchoolId: _selectedSchoolId,
          claimedInstitutionIdsBySchoolId: claimedInstitutionIdsBySchoolId,
          desktopMode: false,
        ),
      );
    }
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
            password: _passwordController.text,
            institutionCatalogId: selectedSchool.id,
            institutionName: selectedSchool.name,
          );
      await syncAuthSessionState(ref);
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
        final authUser = ref.read(authStateChangesProvider).valueOrNull;
        final isLoggedIn = authUser != null;
        final hasName = _adminNameController.text.trim().length >= 2;
        final email = _emailController.text.trim();
        final hasEmail = email.isNotEmpty && email.contains('@');
        setState(() {
          _adminNameFieldError = !hasName;
          _adminEmailFieldError = !isLoggedIn && !hasEmail;
        });
        if (!hasName || (!isLoggedIn && !hasEmail)) {
          return 'Please correct the highlighted fields.';
        }
        return null;
      default:
        final authUser = ref.watch(authStateChangesProvider).valueOrNull;
        final isLoggedIn = authUser != null;
        if (isLoggedIn) {
          // No password required when using an existing authenticated account.
          setState(() {
            _passwordFieldError = false;
            _confirmPasswordFieldError = false;
          });
          return null;
        }
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
        heroBaseText: '',
        heroHighlightText: '',
        heroDescription:
            'Create your admin account, generate join access, and onboard '
            'counselors and members in one secure, auditable flow.',
        heroHighlightAfterBase: true,
        heroSupplement: const _RegisterHeroSupplement(),
        formChild: _buildFormContent(context),
        disableScroll: true,
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      child: _buildFormCard(context),
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_isFormBusy) {
      return;
    }
    var stepError = _validateCurrentStep();
    if (stepError != null) {
      await _showFormError(stepError);
      return;
    }

    if (_activeStep == 0) {
      if (_isWindowsDesktop) {
        setState(() => _isCheckingInstitutionAvailability = true);
      }
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
      } finally {
        if (mounted && _isCheckingInstitutionAvailability) {
          setState(() => _isCheckingInstitutionAvailability = false);
        }
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
    if (_isFormBusy) {
      return;
    }
    if (_activeStep == 0) {
      // Navigate to the regular register screen instead of login to avoid
      // triggering router redirects that force this screen back into view.
      context.go(AppRoute.register);
      return;
    }
    setState(() {
      _currentStep = _activeStep - 1;
      _formError = null;
    });
  }

  Widget _buildStepIndicator() {
    final currentStep = _activeStep;
    final children = <Widget>[];
    for (var index = 0; index < _stepCount; index++) {
      final isActive = index == currentStep;
      final isCompleted = index < currentStep;
      final fillColor = isCompleted || isActive
          ? const Color(0xFF0E9B90)
          : const Color(0xFFD7E3EF);
      final textColor = isCompleted || isActive
          ? Colors.white
          : const Color(0xFF8EA3BB);

      children.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: fillColor, shape: BoxShape.circle),
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
      );

      if (index < _stepCount - 1) {
        children.add(
          Container(
            width: 54,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: index < currentStep
                ? const Color(0xFF0E9B90)
                : const Color(0xFFD7E3EF),
          ),
        );
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: children,
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
        return 'Add administrator identity details for approval and onboarding.';
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
          isChecking: _isCheckingInstitutionAvailability,
          selectedSchoolName: selectedSchool?.name,
          onTap: _openCatalogSchoolPicker,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: !_isWindowsDesktop || !_isCheckingInstitutionAvailability
              ? const SizedBox(height: 8)
              : Container(
                  key: const ValueKey('institution-checking-banner'),
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFFFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB7EFE8)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFF0E9B90),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Checking whether this institution is already registered...',
                          style: TextStyle(
                            color: Color(0xFF0A6E66),
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isFormBusy
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
    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    final isLoggedIn = authUser != null;
    if (isLoggedIn) {
      final currentEmail = (authUser!.email ?? '').trim();
      if (currentEmail.isNotEmpty &&
          _emailController.text.trim().toLowerCase() !=
              currentEmail.toLowerCase()) {
        _emailController.text = currentEmail;
      }
    }

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
          hasError: _adminEmailFieldError && !isLoggedIn,
          child: isLoggedIn
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mail_outline_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          authUser!.email ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                )
              : TextFormField(
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
      ],
    );
  }

  Widget _buildSecurityStep() {
    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    final isLoggedIn = authUser != null;
    if (isLoggedIn) {
      return Column(
        key: const ValueKey('security-step-logged-in'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          const Text(
            'You are signed in and will register this institution using your existing account. No password is required.',
            style: TextStyle(
              color: Color(0xFF516784),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

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
                        hintText: '***',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
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
                  const _FieldLabel(text: 'CONFIRM'),
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
                        hintText: '***',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
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
          mainAxisSize: MainAxisSize.min,
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
                      onPressed: _isFormBusy ? null : _handleBackAction,
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
                        child: _isCheckingInstitutionAvailability
                            ? const Row(
                                key: ValueKey('checking-institution'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Checking...',
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                _isSubmitting
                                    ? 'Creating...'
                                    : (_activeStep < _stepCount - 1
                                          ? 'Continue'
                                          : 'Create'),
                                key: ValueKey(
                                  '$_isSubmitting-$_isCheckingInstitutionAvailability-$_activeStep',
                                ),
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
            const SizedBox(height: 12),
            // Allow a signed-in admin to intentionally skip institution setup
            // and continue into the app. The router will honor the
            // `skipSetup=1` query parameter (see app_router.dart) so this
            // navigation doesn't immediately redirect back to this screen.
            if (ref.read(authStateChangesProvider).valueOrNull != null)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: _isFormBusy
                      ? null
                      : () {
                          context.go(
                            Uri(
                              path: AppRoute.home,
                              queryParameters: const {'skipSetup': '1'},
                            ).toString(),
                          );
                        },
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: Color(0xFF516784),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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
    required this.isChecking,
    required this.selectedSchoolName,
    required this.onTap,
  });

  final bool hasError;
  final bool isChecking;
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
      onTap: isChecking ? null : onTap,
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
              child: isChecking
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF0E9B90),
                      ),
                    )
                  : const Icon(
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
    this.claimedInstitutionIdsBySchoolId = const <String, String>{},
    this.desktopMode = false,
  });

  final List<CatalogSchool> schools;
  final String? selectedSchoolId;
  final Map<String, String> claimedInstitutionIdsBySchoolId;
  final bool desktopMode;

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

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: !widget.desktopMode,
        child: Container(
          height: widget.desktopMode ? double.infinity : 640,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: widget.desktopMode
                ? BorderRadius.circular(30)
                : const BorderRadius.vertical(top: Radius.circular(30)),
            border: widget.desktopMode
                ? Border.all(color: const Color(0xFFDDE6F1))
                : null,
            boxShadow: widget.desktopMode
                ? const [
                    BoxShadow(
                      color: Color(0x26071A33),
                      blurRadius: 34,
                      offset: Offset(0, 20),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              widget.desktopMode ? 18 : 12,
              18,
              18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.desktopMode)
                  Center(
                    child: Container(
                      width: 54,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD2DCE9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF64748B),
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
                              final isClaimed = widget
                                  .claimedInstitutionIdsBySchoolId
                                  .containsKey(school.id);
                              return InkWell(
                                onTap: isClaimed
                                    ? null
                                    : () =>
                                          Navigator.of(context).pop(school.id),
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isClaimed
                                        ? const Color(0xFFF3F4F6)
                                        : isSelected
                                        ? const Color(0xFFEFFFFC)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: isClaimed
                                          ? const Color(0xFFE2E8F0)
                                          : isSelected
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
                                          color: isClaimed
                                              ? const Color(0xFFE5E7EB)
                                              : isSelected
                                              ? const Color(
                                                  0xFF0E9B90,
                                                ).withValues(alpha: 0.14)
                                              : const Color(0xFFE2E8F0),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.account_balance_rounded,
                                          color: isClaimed
                                              ? const Color(0xFF94A3B8)
                                              : isSelected
                                              ? const Color(0xFF0E9B90)
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              school.name,
                                              style: TextStyle(
                                                color: isClaimed
                                                    ? const Color(0xFF94A3B8)
                                                    : const Color(0xFF071937),
                                                fontWeight: FontWeight.w700,
                                                height: 1.35,
                                              ),
                                            ),
                                            if (isClaimed) ...[
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFE5E7EB,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFD1D5DB,
                                                    ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Institution exists',
                                                  style: TextStyle(
                                                    color: Color(0xFF475569),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        isClaimed
                                            ? Icons.block_rounded
                                            : isSelected
                                            ? Icons.check_circle_rounded
                                            : Icons.arrow_outward_rounded,
                                        color: isClaimed
                                            ? const Color(0xFF94A3B8)
                                            : isSelected
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
      ),
    );
  }
}

class _RegisterHintCard extends StatefulWidget {
  const _RegisterHintCard({super.key});

  @override
  State<_RegisterHintCard> createState() => _RegisterHintCardState();
}

class _RegisterHeroSupplement extends StatelessWidget {
  const _RegisterHeroSupplement({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(height: 18),
        _FeatureRow(),
        SizedBox(height: 18),
        _RegisterHintCard(),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _FeatureCard(
            icon: Icons.shield_outlined,
            title: 'FERPA-ready',
            subtitle: 'Encrypted at rest',
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _FeatureCard(
            icon: Icons.vpn_key_outlined,
            title: 'Join codes',
            subtitle: 'Rotate anytime',
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _FeatureCard(
            icon: Icons.group_outlined,
            title: 'Role-based',
            subtitle: 'Admins · Counselors',
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF9FFFE), Color(0xFFF5FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD6EBE8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0E9B90).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF0E9B90)),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF071937),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF7B8CA4),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterHintCardState extends State<_RegisterHintCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.05),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          margin: const EdgeInsets.only(top: 28),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF6FFFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBEEDE3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
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
                  color: const Color(0xFF0E9B90).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFF0E9B90),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Quick tip',
                      style: TextStyle(
                        color: Color(0xFF0E9B90),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'If your school is not listed, request it using "School not listed?" — you\'ll be notified when it\'s added. After registration you will receive a join code to share with counselors.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

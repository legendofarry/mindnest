// features/auth/presentation/login_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const _lastEmailKey = 'auth.last_email';
  static const _desktopBreakpoint = 1100.0;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = true;
  bool _isSubmitting = false;
  bool _submittedAttempt = false;
  String? _lastEmail;
  String? _formError;

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -14), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -14, end: 14), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 14, end: -10), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 2),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _restoreLastEmail();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _triggerShake() async {
    if (!mounted) {
      return;
    }
    await _shakeController.forward(from: 0);
  }

  Future<void> _submit() async {
    setState(() {
      _submittedAttempt = true;
      _formError = null;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _formError = 'Please correct the highlighted fields.';
      });
      await _triggerShake();
      return;
    }

    final normalizedEmail = _emailController.text.trim().toLowerCase();
    setState(() => _isSubmitting = true);

    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            email: normalizedEmail,
            password: _passwordController.text,
            rememberMe: _rememberMe,
          );
      await _saveLastEmail(normalizedEmail);
    } on FirebaseAuthException catch (error) {
      setState(() {
        _formError = error.message ?? 'Login failed.';
      });
      await _triggerShake();
    } catch (error) {
      setState(() {
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
      await _triggerShake();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _restoreLastEmail() async {
    final preferences = await SharedPreferences.getInstance();
    final storedEmail = preferences.getString(_lastEmailKey)?.trim();

    if (!mounted || storedEmail == null || storedEmail.isEmpty) {
      return;
    }

    setState(() => _lastEmail = storedEmail);
    if (_emailController.text.trim().isEmpty) {
      _emailController.text = storedEmail;
    }
  }

  Future<void> _saveLastEmail(String email) async {
    if (email.isEmpty) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastEmailKey, email);

    if (!mounted) {
      return;
    }

    setState(() => _lastEmail = email);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7FBFC),
        body: Stack(
          children: [
            const Positioned.fill(child: _DesktopAmbientBackground()),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 52,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          flex: 6,
                          child: _DesktopMarketingPanel(),
                        ),
                        const SizedBox(width: 54),
                        Expanded(
                          flex: 5,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 500),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: const Color(0xFFBEE9E4),
                                    width: 1.1,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x140F172A),
                                      blurRadius: 36,
                                      offset: Offset(0, 18),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    34,
                                    28,
                                    34,
                                    26,
                                  ),
                                  child: _buildFormContent(
                                    context,
                                    showBrand: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      child: _buildFormContent(context, showBrand: true),
    );
  }

  Widget _buildFormContent(BuildContext context, {required bool showBrand}) {
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
        autovalidateMode: _submittedAttempt
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBrand) ...[
              const SizedBox(height: 16),
              const BrandMark(),
              const SizedBox(height: 38),
            ] else ...[
              const SizedBox(height: 8),
            ],
            Text(
              'Welcome Back',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF071937),
                letterSpacing: -0.7,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Continue your journey to wellness.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF5E728D),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: (_formError == null || _formError!.trim().isEmpty)
                  ? const SizedBox(height: 24)
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
            const _FieldLabel(text: 'EMAIL ADDRESS'),
            const SizedBox(height: 8),
            _RoundedInput(
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {
                  _formError = null;
                }),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'alex@example.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty || !trimmed.contains('@')) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
            ),
            if ((_lastEmail ?? '').isNotEmpty &&
                _emailController.text.trim().toLowerCase() != _lastEmail)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () {
                      final lastEmail = _lastEmail;
                      if (lastEmail == null || lastEmail.isEmpty) {
                        return;
                      }
                      setState(() {
                        _emailController.text = lastEmail;
                        _emailController.selection = TextSelection.collapsed(
                          offset: lastEmail.length,
                        );
                        _formError = null;
                      });
                    },
                    child: Text(
                      'Use saved email: $_lastEmail',
                      style: const TextStyle(
                        color: Color(0xFF0E9B90),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                const _FieldLabel(text: 'PASSWORD'),
                const Spacer(),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => context.go(AppRoute.forgotPassword),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: Color(0xFF0E9B90),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _RoundedInput(
              child: TextFormField(
                controller: _passwordController,
                obscureText: true,
                onChanged: (_) {
                  if (_formError != null) {
                    setState(() => _formError = null);
                  }
                },
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '********',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) {
                    return 'Password is required.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              setState(() => _rememberMe = value ?? false);
                            },
                    ),
                    const Text(
                      'Remember Me',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'Keep me signed in for 14 days on this device.',
                    style: TextStyle(
                      color: Color(0xFF0E9B90),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E9B90), Color(0xFF18A89D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D72ECDC),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  shadowColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _isSubmitting ? 'Signing in...' : 'Log In  ->',
                    key: ValueKey(_isSubmitting),
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'New to MindNest? ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF4A607C),
                  ),
                ),
                GestureDetector(
                  onTap: _isSubmitting
                      ? null
                      : () => context.go(AppRoute.register),
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      color: Color(0xFF0E9B90),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => context.go(AppRoute.registerInstitution),
                child: const Text(
                  'Institution Admin? Register Institution',
                  style: TextStyle(color: Color(0xFF6A7D96)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopMarketingPanel extends StatelessWidget {
  const _DesktopMarketingPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _DesktopBrandIcon(),
              SizedBox(width: 14),
              Text(
                'MindNest',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 41,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 42),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Your safe space\n',
                  style: TextStyle(
                    color: Color(0xFF0E9B90),
                    fontSize: 74,
                    fontWeight: FontWeight.w800,
                    height: 0.98,
                    letterSpacing: -1.9,
                  ),
                ),
                TextSpan(
                  text: 'for mental wellness.',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 74,
                    fontWeight: FontWeight.w800,
                    height: 0.98,
                    letterSpacing: -1.9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 700),
            child: Text(
              'Join thousands of individuals and institutions committed to better '
              'mental health outcomes through empathy and expert care.',
              style: TextStyle(
                color: Color(0xFF4C607A),
                fontSize: 31,
                height: 1.38,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 54),
          const Row(
            children: [
              _MetricItem(value: '3+', label: 'USERS HELPED'),
              SizedBox(width: 54),
              _MetricItem(value: '1+', label: 'INSTITUTIONS'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopBrandIcon extends StatelessWidget {
  const _DesktopBrandIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF15CFC2),
      ),
      child: const Icon(
        Icons.psychology_alt_rounded,
        color: Color(0xFF0A3B37),
        size: 25,
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 49,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0E9B90),
            fontSize: 15,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DesktopAmbientBackground extends StatelessWidget {
  const _DesktopAmbientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF8FCFD),
                  const Color(0xFFF6FAFC),
                  const Color(0xFFF4F9FB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Positioned(
          left: -150,
          top: -210,
          child: _GlowBlob(
            size: 680,
            color: const Color(0xFF82E9E0).withValues(alpha: 0.35),
          ),
        ),
        Positioned(
          right: -160,
          top: 130,
          child: _GlowBlob(
            size: 560,
            color: const Color(0xFFB8F4EF).withValues(alpha: 0.34),
          ),
        ),
        Positioned(
          right: 150,
          bottom: -220,
          child: _GlowBlob(
            size: 640,
            color: const Color(0xFF8DE8DF).withValues(alpha: 0.26),
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.44),
              blurRadius: size * 0.28,
              spreadRadius: size * 0.02,
            ),
          ],
        ),
      ),
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

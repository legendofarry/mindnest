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

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _lastEmailKey = 'auth.last_email';
  static const _desktopBreakpoint = 1100.0;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = true;
  bool _isSubmitting = false;
  String? _lastEmail;

  @override
  void initState() {
    super.initState();
    _restoreLastEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
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
      _showMessage(error.message ?? 'Login failed.');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            Container(
              height: 52,
              color: const Color(0xFF171717),
              alignment: Alignment.center,
              child: const Text(
                'MindNest V1 - Mental Wellness Platform',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  const Expanded(child: _DesktopMarketingPanel()),
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF8FAFC),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 24,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: _buildFormContent(context, showBrand: false),
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
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      child: _buildFormContent(context, showBrand: true),
    );
  }

  Widget _buildFormContent(BuildContext context, {required bool showBrand}) {
    return Form(
      key: _formKey,
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
          const SizedBox(height: 24),
          const _FieldLabel(text: 'EMAIL ADDRESS'),
          const SizedBox(height: 8),
          _RoundedInput(
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
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
    );
  }
}

class _DesktopMarketingPanel extends StatelessWidget {
  const _DesktopMarketingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(76, 74, 76, 68),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF118F88), Color(0xFF0D6E6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _DesktopBrandIcon(),
              SizedBox(width: 16),
              Text(
                'MindNest',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Your safe space for\nmental wellness.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 43,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            'Join thousands of individuals and institutions\ncommitted to better mental health outcomes through\nempathy and expert care.',
            style: TextStyle(
              color: Color(0xFFA9EFE8),
              fontSize: 23,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const Row(
            children: [
              _MetricItem(value: '120k+', label: 'USERS HELPED'),
              SizedBox(width: 48),
              _MetricItem(value: '450+', label: 'INSTITUTIONS'),
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
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFECFDF5),
      ),
      child: const Icon(Icons.psychology_alt_rounded, color: Color(0xFF0E9B90)),
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
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFA9EFE8),
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/config/school_catalog.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

class RegisterInstitutionSchoolRequestScreen extends ConsumerStatefulWidget {
  const RegisterInstitutionSchoolRequestScreen({super.key});

  @override
  ConsumerState<RegisterInstitutionSchoolRequestScreen> createState() =>
      _RegisterInstitutionSchoolRequestScreenState();
}

class _RegisterInstitutionSchoolRequestScreenState
    extends ConsumerState<RegisterInstitutionSchoolRequestScreen> {
  static const _desktopBreakpoint = 1100.0;

  final _searchController = TextEditingController();
  final _institutionNameController = TextEditingController();
  bool _isSubmitting = false;
  bool _hasConfirmedNotListed = false;
  bool _institutionFieldError = false;
  bool _confirmationError = false;
  String? _formError;
  int _currentStep = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _institutionNameController.dispose();
    super.dispose();
  }

  static const _requestStepCount = 2;

  int get _activeStep {
    if (_currentStep < 0) {
      return 0;
    }
    if (_currentStep >= _requestStepCount) {
      return _requestStepCount - 1;
    }
    return _currentStep;
  }

  bool get _isCatalogStep => _activeStep == 0;

  bool get _isRequestStep => _activeStep == 1;

  void _goToCatalogStep() {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _currentStep = 0;
      _formError = null;
      _institutionFieldError = false;
      _confirmationError = false;
    });
  }

  void _goToRequestStep() {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _currentStep = 1;
      _formError = null;
    });
  }

  List<CatalogSchool> get _filteredSchools {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return kCatalogSchools;
    }
    return kCatalogSchools
        .where((school) => school.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  bool _alreadyExists(String institutionName) {
    final normalized = institutionName.trim().toLowerCase();
    return kCatalogSchools.any(
      (school) => school.name.trim().toLowerCase() == normalized,
    );
  }

  Future<void> _submit() async {
    if (_isCatalogStep) {
      _goToRequestStep();
      return;
    }

    final schoolName = _institutionNameController.text.trim();
    final hasName = schoolName.length >= 2;
    final alreadyExists = hasName && _alreadyExists(schoolName);

    setState(() {
      _institutionFieldError = !hasName || alreadyExists;
      _confirmationError = !_hasConfirmedNotListed;
      if (!hasName) {
        _formError = 'Enter the institution name you want reviewed.';
      } else if (alreadyExists) {
        _formError =
            'That institution already exists in the approved catalog. Search the list above and go back to select it.';
      } else if (!_hasConfirmedNotListed) {
        _formError =
            'Confirm that you searched the approved catalog before sending a request.';
      } else {
        _formError = null;
      }
    });

    if (!hasName || alreadyExists || !_hasConfirmedNotListed) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .submitSchoolRequest(schoolName: schoolName);
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        const SnackBar(
          content: Text("Institution request sent. We'll review your request"),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) {
        return;
      }
      context.go(AppRoute.registerInstitution);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    final content = _buildContent(context, isDesktop: isDesktop);

    if (isDesktop) {
      return AuthDesktopShell(
        // Hide the small top-left duplicate hero text which crowds the layout
        showTopHeroOverlay: false,
        heroHighlightText: 'Request your institution',
        heroBaseText: 'for review.',
        heroDescription:
            'Search the approved catalog first. If your institution is truly not listed, submit the name and we will review it for onboarding.',
        formMaxWidth: 660,
        formChild: content,
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      maxWidth: double.infinity,
      alignTop: true,
      child: content,
    );
  }

  Widget _buildContent(BuildContext context, {required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isSubmitting
                ? null
                : () => context.go(AppRoute.registerInstitution),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to registration'),
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(height: 6),
          _buildStepRail(),
          const SizedBox(height: 14),
        ] else ...[
          const SizedBox(height: 8),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: (_formError == null || _formError!.trim().isEmpty)
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(_formError),
                  margin: const EdgeInsets.only(bottom: 12),
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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                ...previousChildren,
                ...(currentChild == null
                    ? const <Widget>[]
                    : <Widget>[currentChild]),
              ],
            );
          },
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: _isCatalogStep
              ? _buildCatalogStep(context, isDesktop: isDesktop)
              : _buildRequestStep(context, isDesktop: isDesktop),
        ),
      ],
    );
  }

  Widget _buildStepRail() {
    final activeColor = const Color(0xFF0E9B90);
    final inactiveColor = const Color(0xFFB7C5D8);
    final lineColor = _isRequestStep ? activeColor : const Color(0xFFD9E4EE);

    Widget stepTile({
      required String number,
      required String label,
      required bool isActive,
      required bool isComplete,
    }) {
      final highlight = isActive || isComplete;
      final background = highlight
          ? const Color(0xFFEFFFFC)
          : const Color(0xFFF4F7FB);
      final textColor = highlight
          ? const Color(0xFF0D6F69)
          : const Color(0xFF8EA3BB);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlight
                    ? activeColor.withValues(alpha: 0.18)
                    : inactiveColor.withValues(alpha: 0.22),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                color: highlight ? activeColor : inactiveColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        stepTile(
          number: '1',
          label: 'Search catalog',
          isActive: _isCatalogStep,
          isComplete: _isRequestStep,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: lineColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 12),
        stepTile(
          number: '2',
          label: 'Send request',
          isActive: _isRequestStep,
          isComplete: false,
        ),
      ],
    );
  }

  Widget _buildCatalogStep(BuildContext context, {required bool isDesktop}) {
    final schools = _filteredSchools;
    final listHeight = _catalogListHeight(context, isDesktop: isDesktop);

    return Column(
      key: const ValueKey('catalog-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SchoolRequestSectionLabel(text: 'SEARCH APPROVED CATALOG'),
        const SizedBox(height: 8),
        _SchoolRequestInputShell(
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Search institution name',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: listHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDDE6F1)),
          ),
          child: schools.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No approved institution matches that search.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: schools.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final school = schools[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCE6F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFFFFC),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.account_balance_rounded,
                              color: Color(0xFF0E9B90),
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
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'If you see your institution above, go back and choose the approved entry instead.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF516784),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 208,
                child: _buildPrimaryActionButton(
                  label: 'I did not find it',
                  onPressed: _isSubmitting ? null : _goToRequestStep,
                  isBusy: false,
                  height: 54,
                ),
              ),
            ],
          )
        else ...[
          Text(
            'If you see your institution above, go back and choose the approved entry instead.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF516784),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildPrimaryActionButton(
            label: 'I did not find it',
            onPressed: _isSubmitting ? null : _goToRequestStep,
            isBusy: false,
            height: 54,
          ),
        ],
      ],
    );
  }

  Widget _buildRequestStep(BuildContext context, {required bool isDesktop}) {
    return Column(
      key: const ValueKey('request-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SchoolRequestSectionLabel(text: 'CONFIRM NOT LISTED'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _confirmationError
                ? const Color(0xFFFFF1F2)
                : const Color(0xFFEFFFFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _confirmationError
                  ? const Color(0xFFFECDD3)
                  : const Color(0xFFB3ECDD),
            ),
          ),
          child: CheckboxListTile(
            value: _hasConfirmedNotListed,
            onChanged: _isSubmitting
                ? null
                : (value) => setState(() {
                    _hasConfirmedNotListed = value ?? false;
                    _confirmationError = false;
                    _formError = null;
                  }),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I searched the approved catalog and confirmed my institution is not listed.',
              style: TextStyle(
                color: Color(0xFF0D6F69),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SchoolRequestSectionLabel(text: 'INSTITUTION NAME TO REVIEW'),
        const SizedBox(height: 8),
        _SchoolRequestInputShell(
          hasError: _institutionFieldError,
          child: TextField(
            controller: _institutionNameController,
            onChanged: (_) => setState(() {
              _institutionFieldError = false;
              _formError = null;
            }),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Enter institution name',
              prefixIcon: Icon(Icons.school_rounded),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (isDesktop)
          Row(
            children: [
              TextButton.icon(
                onPressed: _isSubmitting ? null : _goToCatalogStep,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to catalog'),
              ),
              const Spacer(),
              SizedBox(
                width: 240,
                child: _buildPrimaryActionButton(
                  label: 'Send institution request',
                  onPressed: _isSubmitting ? null : _submit,
                  isBusy: _isSubmitting,
                  height: 56,
                ),
              ),
            ],
          )
        else ...[
          _buildPrimaryActionButton(
            label: 'Send institution request',
            onPressed: _isSubmitting ? null : _submit,
            isBusy: _isSubmitting,
            height: 56,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isSubmitting ? null : _goToCatalogStep,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to catalog'),
          ),
        ],
      ],
    );
  }

  Widget _buildPrimaryActionButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isBusy,
    required double height,
  }) {
    final enabled = onPressed != null;
    final colors = enabled
        ? const [Color(0xFF0E9B90), Color(0xFF18A89D)]
        : const [Color(0xFFB8C5D6), Color(0xFFAAB8CB)];

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          shadowColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isBusy
              ? Row(
                  key: const ValueKey('busy'),
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Sending request...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16.5,
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  key: const ValueKey('idle'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16.5,
                  ),
                ),
        ),
      ),
    );
  }

  double _catalogListHeight(BuildContext context, {required bool isDesktop}) {
    final height = MediaQuery.sizeOf(context).height;
    final target = height * (isDesktop ? 0.27 : 0.34);
    final minHeight = isDesktop ? 210.0 : 280.0;
    final maxHeight = isDesktop ? 255.0 : 340.0;
    return target.clamp(minHeight, maxHeight).toDouble();
  }
}

class _SchoolRequestSectionLabel extends StatelessWidget {
  const _SchoolRequestSectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9AAAC0),
        letterSpacing: 1.5,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }
}

class _SchoolRequestInputShell extends StatelessWidget {
  const _SchoolRequestInputShell({required this.child, this.hasError = false});

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

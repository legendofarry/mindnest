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

  @override
  void dispose() {
    _searchController.dispose();
    _institutionNameController.dispose();
    super.dispose();
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
          content: Text(
            'Institution request sent. We will review the name and add it if approved.',
          ),
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

    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: 'Request your institution',
        heroBaseText: 'for review.',
        heroDescription:
            'Search the approved catalog first. If your institution is truly not listed, submit the name and we will review it for onboarding.',
        formMaxWidth: 660,
        formChild: _buildContent(context),
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      maxWidth: 680,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        Text(
          'School not listed?',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071937),
            letterSpacing: -0.5,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Search the approved catalog below first. If your institution is really not present, confirm that and send the institution name for review.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF516784),
            fontWeight: FontWeight.w500,
            height: 1.4,
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
        const SizedBox(height: 14),
        Container(
          height: 320,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDDE6F1)),
          ),
          child: _filteredSchools.isEmpty
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
                  itemCount: _filteredSchools.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final school = _filteredSchools[index];
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
        const SizedBox(height: 18),
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
        const SizedBox(height: 18),
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
        const SizedBox(height: 22),
        Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: _isSubmitting
                  ? const [Color(0xFFB8C5D6), Color(0xFFAAB8CB)]
                  : const [Color(0xFF0E9B90), Color(0xFF18A89D)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              shadowColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(
              _isSubmitting ? 'Sending request...' : 'Send institution request',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16.5,
              ),
            ),
          ),
        ),
      ],
    );
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

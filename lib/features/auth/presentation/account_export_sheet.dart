import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';

Future<void> showAccountExportSheet({
  required BuildContext context,
  required WidgetRef ref,
  String title = 'Export Your Data',
  String subtitle =
      'Download a polished PDF summary, spreadsheet-ready CSV tables, or the advanced raw JSON package.',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close export',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: const Color(0xB30B1220).withValues(alpha: 0.28),
                ),
              ),
            ),
            _AccountExportSheet(
              parentContext: context,
              ref: ref,
              title: title,
              subtitle: subtitle,
            ),
          ],
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.96,
            end: 1,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AccountExportSheet extends StatefulWidget {
  const _AccountExportSheet({
    required this.parentContext,
    required this.ref,
    required this.title,
    required this.subtitle,
  });

  final BuildContext parentContext;
  final WidgetRef ref;
  final String title;
  final String subtitle;

  @override
  State<_AccountExportSheet> createState() => _AccountExportSheetState();
}

class _AccountExportSheetState extends State<_AccountExportSheet> {
  Map<String, dynamic>? _cachedExport;
  _ExportAction? _busyAction;

  bool get _isBusy => _busyAction != null;

  Future<Map<String, dynamic>> _loadExport() async {
    if (_cachedExport != null) {
      return _cachedExport!;
    }
    final export = await widget.ref
        .read(authRepositoryProvider)
        .exportCurrentUserData();
    _cachedExport = export;
    return export;
  }

  Future<void> _runAction(_ExportAction action) async {
    if (_isBusy) {
      return;
    }
    setState(() => _busyAction = action);
    try {
      final export = await _loadExport();
      final service = widget.ref.read(accountExportServiceProvider);
      switch (action) {
        case _ExportAction.downloadPdf:
          final result = await service.downloadPdfSummary(export);
          await _showFeedbackDialog(
            title: 'PDF ready',
            message: result.message,
            icon: Icons.picture_as_pdf_rounded,
          );
        case _ExportAction.downloadCsv:
          final result = await service.downloadCsvTables(export);
          await _showFeedbackDialog(
            title: 'CSV export ready',
            message: result.message,
            icon: Icons.table_chart_rounded,
          );
        case _ExportAction.downloadJson:
          final result = await service.downloadJson(export);
          await _showFeedbackDialog(
            title: 'JSON export ready',
            message: result.message,
            icon: Icons.data_object_rounded,
          );
        case _ExportAction.copyJson:
          await service.copyJson(export);
          await _showFeedbackDialog(
            title: 'JSON copied',
            message: 'Raw JSON export was copied to your clipboard.',
            icon: Icons.copy_all_rounded,
          );
      }
    } catch (error) {
      await _showFeedbackDialog(
        title: 'Export failed',
        message: error.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline_rounded,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _showFeedbackDialog({
    required String title,
    required String message,
    required IconData icon,
    bool isError = false,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A0F172A),
                  blurRadius: 30,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isError
                            ? const [Color(0xFFDC2626), Color(0xFFF97316)]
                            : const [Color(0xFF0E9B90), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF10243F),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF5A6E87),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: isError
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0E9B90),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final floatingLayout = kIsWeb || screenSize.width >= 720;
    final maxSheetHeight = math.min(
      screenSize.height * (floatingLayout ? 0.82 : 0.88),
      floatingLayout ? 720.0 : 760.0,
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          floatingLayout ? 16 : 24,
          16,
          16 + bottomInset,
        ),
        child: Align(
          alignment: floatingLayout ? Alignment.center : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: maxSheetHeight,
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A0F172A),
                      blurRadius: 30,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 48,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD5E0EB),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Color(0xFF10243F),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.subtitle,
                              style: const TextStyle(
                                color: Color(0xFF5A6E87),
                                fontWeight: FontWeight.w500,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Recommended formats',
                              style: TextStyle(
                                color: Color(0xFF10243F),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _ExportOptionsGrid(
                              children: [
                                _ExportOptionCard(
                                  icon: Icons.picture_as_pdf_rounded,
                                  title: 'Download PDF',
                                  subtitle:
                                      'Readable summary for people and support conversations.',
                                  badge: 'Recommended',
                                  busy:
                                      _busyAction == _ExportAction.downloadPdf,
                                  onTap: () =>
                                      _runAction(_ExportAction.downloadPdf),
                                ),
                                _ExportOptionCard(
                                  icon: Icons.table_chart_rounded,
                                  title: 'Download CSV tables',
                                  subtitle:
                                      'Spreadsheet-ready tables saved as separate CSV files.',
                                  badge: 'Recommended',
                                  busy:
                                      _busyAction == _ExportAction.downloadCsv,
                                  onTap: () =>
                                      _runAction(_ExportAction.downloadCsv),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Advanced',
                              style: TextStyle(
                                color: Color(0xFF10243F),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _ExportOptionsGrid(
                              children: [
                                _ExportOptionCard(
                                  icon: Icons.data_object_rounded,
                                  title: 'Download raw JSON',
                                  subtitle:
                                      'Full structured export for migration, troubleshooting, or backup.',
                                  badge: 'Advanced',
                                  busy:
                                      _busyAction == _ExportAction.downloadJson,
                                  onTap: () =>
                                      _runAction(_ExportAction.downloadJson),
                                ),
                                _ExportOptionCard(
                                  icon: Icons.copy_all_rounded,
                                  title: 'Copy raw JSON',
                                  subtitle:
                                      'Quick developer-style copy for debugging or support.',
                                  badge: 'Advanced',
                                  busy: _busyAction == _ExportAction.copyJson,
                                  onTap: () =>
                                      _runAction(_ExportAction.copyJson),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _isBusy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ExportAction { downloadPdf, downloadCsv, downloadJson, copyJson }

class _ExportOptionsGrid extends StatelessWidget {
  const _ExportOptionsGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 460;
        final tileWidth = useTwoColumns
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: children
              .map((child) => SizedBox(width: tileWidth, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ExportOptionCard extends StatelessWidget {
  const _ExportOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFE),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDDE6EE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: SizedBox(
            height: 168,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0E9B90), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Icon(icon, color: Colors.white),
                    ),
                    const Spacer(),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7FBF8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Color(0xFF0B7D73),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF10243F),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF5A6E87),
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

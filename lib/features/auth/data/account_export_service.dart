import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'account_export_storage.dart';

class AccountExportService {
  const AccountExportService();

  Future<AccountExportSaveResult> downloadPdfSummary(
    Map<String, dynamic> export,
  ) async {
    final normalized = _jsonReady(export) as Map<String, dynamic>;
    final user = _map(normalized['user']);
    final document = pw.Document(
      title: 'MindNest data export',
      author: 'MindNest',
      creator: 'MindNest 1.0.1',
    );

    final summaryRows = <List<String>>[
      <String>['Exported at', '${normalized['exportedAt'] ?? '-'}'],
      <String>['Name', '${user['name'] ?? '-'}'],
      <String>['Email', '${user['email'] ?? '-'}'],
      <String>['Role', '${user['role'] ?? '-'}'],
      <String>['Institution', '${user['institutionName'] ?? '-'}'],
    ];

    final datasetRows = <List<String>>[
      <String>['Profile', user.isEmpty ? '0' : '1'],
      <String>[
        'Onboarding responses',
        '${_rows(normalized['onboardingResponses']).length}',
      ],
      <String>[
        'Student appointments',
        '${_rows(normalized['studentAppointments']).length}',
      ],
      <String>[
        'Counselor appointments',
        '${_rows(normalized['counselorAppointments']).length}',
      ],
      <String>['Notifications', '${_rows(normalized['notifications']).length}'],
      <String>['Care goals', '${_rows(normalized['careGoals']).length}'],
      <String>[
        'Privacy settings',
        _map(normalized['privacySettings']).isEmpty ? '0' : '1',
      ],
    ];

    document.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ),
        build: (context) => <pw.Widget>[
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0E9B90'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MindNest Data Export',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Human-friendly summary for your account export package.',
                  style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFFE7FBF8),
                    fontSize: 11,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Version 1.0.1',
                  style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFFD9F7F3),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Account summary',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#10243F'),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Field', 'Value'],
            data: summaryRows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#173B69'),
            ),
            cellStyle: const pw.TextStyle(fontSize: 11),
            cellPadding: const pw.EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 10,
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Included datasets',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#10243F'),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Dataset', 'Records'],
            data: datasetRows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0A1C35'),
            ),
            cellStyle: const pw.TextStyle(fontSize: 11),
            cellPadding: const pw.EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 10,
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F3F8FF'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
              border: pw.Border.all(color: PdfColor.fromHex('#D7E6F5')),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'What this package contains',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF10243F),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Bullet(
                  text:
                      'PDF summary for quick reading and support-friendly sharing.',
                ),
                pw.Bullet(
                  text:
                      'CSV tables for spreadsheet work and record inspection.',
                ),
                pw.Bullet(
                  text:
                      'Raw JSON for full-fidelity structured export and future portability.',
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return saveExportArtifacts(
      folderName: _folderName(),
      artifacts: <AccountExportArtifact>[
        AccountExportArtifact(
          fileName: 'mindnest_export_summary.pdf',
          bytes: Uint8List.fromList(await document.save()),
          mimeType: 'application/pdf',
        ),
      ],
    );
  }

  Future<AccountExportSaveResult> downloadCsvTables(
    Map<String, dynamic> export,
  ) async {
    final normalized = _jsonReady(export) as Map<String, dynamic>;
    final artifacts = <AccountExportArtifact>[
      _csvArtifact('profile.csv', _singleRow(_map(normalized['user']))),
      _csvArtifact(
        'privacy_settings.csv',
        _singleRow(_map(normalized['privacySettings'])),
      ),
      _csvArtifact(
        'onboarding_responses.csv',
        _rows(normalized['onboardingResponses']),
      ),
      _csvArtifact(
        'student_appointments.csv',
        _rows(normalized['studentAppointments']),
      ),
      _csvArtifact(
        'counselor_appointments.csv',
        _rows(normalized['counselorAppointments']),
      ),
      _csvArtifact('notifications.csv', _rows(normalized['notifications'])),
      _csvArtifact('care_goals.csv', _rows(normalized['careGoals'])),
    ];

    return saveExportArtifacts(folderName: _folderName(), artifacts: artifacts);
  }

  Future<AccountExportSaveResult> downloadJson(
    Map<String, dynamic> export,
  ) async {
    final normalized = _jsonReady(export);
    final pretty = const JsonEncoder.withIndent('  ').convert(normalized);
    return saveExportArtifacts(
      folderName: _folderName(),
      artifacts: <AccountExportArtifact>[
        AccountExportArtifact(
          fileName: 'mindnest_export_raw.json',
          bytes: Uint8List.fromList(utf8.encode(pretty)),
          mimeType: 'application/json',
        ),
      ],
    );
  }

  Future<void> copyJson(Map<String, dynamic> export) async {
    final normalized = _jsonReady(export);
    final pretty = const JsonEncoder.withIndent('  ').convert(normalized);
    await Clipboard.setData(ClipboardData(text: pretty));
  }

  AccountExportArtifact _csvArtifact(
    String fileName,
    List<Map<String, dynamic>> rows,
  ) {
    final bytes = Uint8List.fromList(utf8.encode(_toCsv(rows)));
    return AccountExportArtifact(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'text/csv',
    );
  }

  List<Map<String, dynamic>> _singleRow(Map<String, dynamic> row) {
    if (row.isEmpty) {
      return <Map<String, dynamic>>[
        const <String, dynamic>{
          'status': 'empty',
          'message': 'No records available in this dataset.',
        },
      ];
    }
    return <Map<String, dynamic>>[row];
  }

  List<Map<String, dynamic>> _rows(dynamic raw) {
    if (raw is! List) {
      return <Map<String, dynamic>>[
        const <String, dynamic>{
          'status': 'empty',
          'message': 'No records available in this dataset.',
        },
      ];
    }
    final mapped = raw
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), _jsonReady(value)),
          ),
        )
        .toList(growable: false);
    if (mapped.isEmpty) {
      return <Map<String, dynamic>>[
        const <String, dynamic>{
          'status': 'empty',
          'message': 'No records available in this dataset.',
        },
      ];
    }
    return mapped;
  }

  Map<String, dynamic> _map(dynamic raw) {
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    return raw.map((key, value) => MapEntry(key.toString(), _jsonReady(value)));
  }

  String _toCsv(List<Map<String, dynamic>> rows) {
    final headers = <String>{};
    for (final row in rows) {
      headers.addAll(row.keys);
    }
    final orderedHeaders = headers.toList(growable: false);
    final buffer = StringBuffer()
      ..writeln(orderedHeaders.map(_csvEscape).join(','));

    for (final row in rows) {
      buffer.writeln(
        orderedHeaders
            .map((header) => _csvEscape(_stringValue(row[header])))
            .join(','),
      );
    }

    return buffer.toString();
  }

  String _stringValue(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }
    if (value is Map || value is Iterable) {
      return jsonEncode(value);
    }
    return '$value';
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _folderName() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return 'mindnest_export_${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}-${twoDigits(now.minute)}-${twoDigits(now.second)}';
  }

  dynamic _jsonReady(dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), _jsonReady(nested)),
      );
    }
    if (value is Iterable) {
      return value.map(_jsonReady).toList(growable: false);
    }
    return value;
  }
}

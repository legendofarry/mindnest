import 'dart:typed_data';

import 'account_export_storage_stub.dart'
    if (dart.library.html) 'account_export_storage_web.dart'
    if (dart.library.io) 'account_export_storage_io.dart'
    as impl;

class AccountExportArtifact {
  const AccountExportArtifact({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
}

class AccountExportSaveResult {
  const AccountExportSaveResult({
    required this.message,
    this.location,
    this.fileNames = const <String>[],
  });

  final String message;
  final String? location;
  final List<String> fileNames;
}

Future<AccountExportSaveResult> saveExportArtifacts({
  required String folderName,
  required List<AccountExportArtifact> artifacts,
}) {
  return impl.saveExportArtifactsImpl(
    folderName: folderName,
    artifacts: artifacts,
  );
}

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'account_export_storage.dart';

Future<AccountExportSaveResult> saveExportArtifactsImpl({
  required String folderName,
  required List<AccountExportArtifact> artifacts,
}) async {
  final writableBase = await _resolveWritableBaseDirectory();
  final exportRoot = Directory(
    '${writableBase.path}${Platform.pathSeparator}MindNest Exports',
  );
  await exportRoot.create(recursive: true);

  final exportDirectory = Directory(
    '${exportRoot.path}${Platform.pathSeparator}$folderName',
  );
  await exportDirectory.create(recursive: true);

  final fileNames = <String>[];
  for (final artifact in artifacts) {
    final target = File(
      '${exportDirectory.path}${Platform.pathSeparator}${artifact.fileName}',
    );
    await target.writeAsBytes(artifact.bytes, flush: true);
    fileNames.add(artifact.fileName);
  }

  final noun = artifacts.length == 1 ? 'file' : 'files';
  return AccountExportSaveResult(
    message:
        'Saved ${artifacts.length} export $noun to ${exportDirectory.path}',
    location: exportDirectory.path,
    fileNames: fileNames,
  );
}

Future<Directory> _resolveWritableBaseDirectory() async {
  try {
    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      return downloadsDirectory;
    }
  } catch (_) {}

  return getApplicationDocumentsDirectory();
}

import 'dart:html' as html;

import 'account_export_storage.dart';

Future<AccountExportSaveResult> saveExportArtifactsImpl({
  required String folderName,
  required List<AccountExportArtifact> artifacts,
}) async {
  final fileNames = <String>[];
  for (final artifact in artifacts) {
    final blob = html.Blob(<Object>[artifact.bytes], artifact.mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = artifact.fileName
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    fileNames.add(artifact.fileName);
  }

  final noun = artifacts.length == 1 ? 'download' : 'downloads';
  return AccountExportSaveResult(
    message: 'Started ${artifacts.length} browser $noun for $folderName.',
    fileNames: fileNames,
  );
}

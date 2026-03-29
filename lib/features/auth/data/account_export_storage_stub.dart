import 'account_export_storage.dart';

Future<AccountExportSaveResult> saveExportArtifactsImpl({
  required String folderName,
  required List<AccountExportArtifact> artifacts,
}) async {
  throw UnsupportedError(
    'Export downloads are not supported on this platform yet.',
  );
}

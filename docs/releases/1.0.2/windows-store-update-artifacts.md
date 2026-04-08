# MindNest 1.0.2 Windows Store Update Artifacts

## Build Date

- 2026-04-07

## Version

- `pubspec.yaml`: `1.0.2+3`
- `msix_config.msix_version`: `1.0.2.0`

## Store Submission Artifact

- Partner Center upload file:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.msixupload`
  - SHA-256: `E4E054C3356FD329791305E2C8CFA7F1A088FFF1B5479A858B37B72820E819D5`

## Other Windows Release Artifacts

- MSIX installer:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.msix`
  - SHA-256: `D68B11588C8D6D25951B7BFACBCA3362BB4CAE5FEBEB36A651D3B0BF6D4787F1`

- Portable Windows bundle:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows-portable.zip`
  - SHA-256: `93C3C144C56366F046CC94AC54579F5D8CA00CE898E48A0CD294E65815DFD5DD`

- Raw launcher only:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.exe`
  - SHA-256: `40BEA6FF7B7833DADAAEFB41CE7F3811C9668FE90ED643F7F3DD49D5216DFF93`

## What Was Run

- `flutter build windows --release`
- `dart run msix:create`
- Repacked `MindNest-v1.0.2-windows.msixupload` from the fresh `mindnest.msix`
- Refreshed the portable Windows ZIP from the latest release directory

## Partner Center Steps

1. Open the existing `MindNest` app in Microsoft Partner Center.
2. Start a new update submission.
3. Open the `Packages` section.
4. Upload `MindNest-v1.0.2-windows.msixupload`.
5. Wait for validation to finish.
6. Review the submission and send it for certification.

## Important Notes

- If the current live Store package version is below `1.0.2.0`, this package is ready to upload.
- The current `.msixupload` contains the freshly rebuilt `mindnest.msix` package.
- The package does not need to install locally without warnings for Store submission; Partner Center handles Store distribution.
- For public website downloads, the portable ZIP is still the safer Windows file than the raw EXE.

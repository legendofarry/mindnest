# MindNest 1.0.2 Windows Store Update Artifacts

## Build Date

- 2026-04-07

## Version

- `pubspec.yaml`: `1.0.2+3`
- `msix_config.msix_version`: `1.0.2.0`

## Store Submission Artifact

- Partner Center upload file:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.msixupload`
  - SHA-256: `F78970E755809D0ED55026BA24C6278AA85AD7E4C77FB1E537850272667B08DB`

## Other Windows Release Artifacts

- MSIX installer:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.msix`
  - SHA-256: `35E3DBA16B9A3FA217EA064CEED5048B9B908C7ABDC17FD25B3F642C79032C7D`

- Portable Windows bundle:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows-portable.zip`
  - SHA-256: `D6093F1558679D5B910DF08375EDDA66BBCED0F4D120B73146A91C4AC7E52771`

- Raw launcher only:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.exe`
  - SHA-256: `40BEA6FF7B7833DADAAEFB41CE7F3811C9668FE90ED643F7F3DD49D5216DFF93`

## What Was Run

- `flutter build windows --release`
- `dart run msix:create`

## Partner Center Steps

1. Open the existing `MindNest` app in Microsoft Partner Center.
2. Start a new update submission.
3. Open the `Packages` section.
4. Upload `MindNest-v1.0.2-windows.msixupload`.
5. Wait for validation to finish.
6. Review the submission and send it for certification.

## Important Notes

- If the current live Store package version is below `1.0.2.0`, this package is ready to upload.
- The package does not need to install locally without warnings for Store submission; Partner Center handles Store distribution.
- For public website downloads, the portable ZIP is still the safer Windows file than the raw EXE.

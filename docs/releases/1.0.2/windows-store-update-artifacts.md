# MindNest 1.0.2 Windows Store Update Artifacts

## Build Date

- 2026-04-09

## Version

- `pubspec.yaml`: `1.0.2+3`
- `msix_config.msix_version`: `1.0.2.0`

## Store Submission Artifact

- Partner Center upload file:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.msixupload`
  - SHA-256: `6690FCAC2993A42540F1554CA6D3414C29B9AA897BB7AAF46C0D6AE53110CDCF`

## Other Windows Release Artifacts

- MSIX installer:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows.msix`
  - SHA-256: `FB16C1B9CBE4858A9339345C9BE14BE111587D287B4C95A88A64BF2B0A3FF2D6`

- Portable Windows bundle:
  - `build/distribution/1.0.2/MindNest-v1.0.2-windows-portable.zip`
  - SHA-256: `9416A667BE9A88A0BDEDBC2B5D2D3282B0F427E288549BC759895426D292B938`

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

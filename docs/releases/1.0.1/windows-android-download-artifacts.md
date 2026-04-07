# MindNest 1.0.1 Windows and Android Download Artifacts

## Build Date

- 2026-04-07

## Artifacts

- Android APK
  - Path: `build/distribution/1.0.1/MindNest-v1.0.1-android.apk`
  - Size: about 107 MB
  - Notes: built from `flutter build apk --release` using the configured release keystore.
  - SHA-256: `0AF94CC65BDFF4097B155254C8F827EBDE81099B7A40607115094BFDC9D6FAC8`

- Windows MSIX Installer
  - Path: `build/distribution/1.0.1/MindNest-v1.0.1-windows.msix`
  - Size: about 35.8 MB
  - Notes: one-click Windows installer package produced from the existing `msix_config`.
  - SHA-256: `A2E098B57F4250BA39938868E5AE1A7302BD31AB85921FF190886E8CBC1BCAD9`

- Windows Store Upload Package
  - Path: `build/distribution/1.0.1/MindNest-v1.0.1-windows.msixupload`
  - Size: about 35.6 MB
  - Notes: the Partner Center upload artifact prepared from the generated MSIX package for Microsoft Store submission.
  - SHA-256: `B717B03DA2D6C643ACE6FD1BD82A2C6FCEE08D69C62E07C1F1838A64519D3839`

- Windows EXE
  - Path: `build/distribution/1.0.1/MindNest-v1.0.1-windows.exe`
  - Size: about 13.5 MB
  - Notes: this is the launcher executable only. A Flutter Windows app also needs the sibling DLLs and the `data` folder from the release bundle.
  - SHA-256: `70A7CF00C1C7B085A396895C12A86B3819D7FB157E94616A8A313F75D5040993`

- Windows Portable Bundle
  - Path: `build/distribution/1.0.1/MindNest-v1.0.1-windows-portable.zip`
  - Size: about 31.1 MB
  - Notes: this is the website-friendly Windows download. It contains the EXE plus all required runtime files.
  - SHA-256: `D6B83B9D7BA72211E2B1E9642A47BF6884C0868906E269522013DEEFF4A9024B`

## Recommended Website Linking

- Android card: link directly to `MindNest-v1.0.1-android.apk`
- Windows card: prefer `MindNest-v1.0.1-windows.msix`
- Windows fallback card or alternate mirror: `MindNest-v1.0.1-windows-portable.zip`
- Microsoft Store submission: use `MindNest-v1.0.1-windows.msixupload`

## Signing Status

- `MindNest-v1.0.1-android.apk`
  - Built as a release APK using the configured Android keystore.

- `MindNest-v1.0.1-windows.msix`
  - Not digitally signed with a public-trust Windows code-signing certificate.

- `MindNest-v1.0.1-windows.exe`
  - Not digitally signed with a public-trust Windows code-signing certificate.

## Practical Website Guidance

- The APK is ready for direct upload.
- The Windows MSIX is the cleaner installer format, but Windows may still warn because it is not publicly code-signed.
- The Windows ZIP is the safest fallback download if you do not yet have a Windows code-signing certificate.
- For the least-friction public Windows install experience, the next real step is signing the Windows package with a trusted code-signing certificate.

## Why Not Upload Only The EXE

A standalone Flutter Windows `.exe` is not self-contained. Users also need:

- `flutter_windows.dll`
- Firebase and plugin DLLs
- `data/`

If the website links only to the raw `.exe`, the app will fail to launch on most machines.

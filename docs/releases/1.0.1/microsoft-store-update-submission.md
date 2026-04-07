# MindNest 1.0.1 Microsoft Store Update Submission

## Store Upload Artifact

- Use: `build/distribution/1.0.1/MindNest-v1.0.1-windows.msixupload`
- Current Windows package version: `1.0.1.0`

## Partner Center Flow

1. Open Partner Center and choose the existing `MindNest` app.
2. Start a new update submission.
3. Go to the packages section.
4. Upload `MindNest-v1.0.1-windows.msixupload`.
5. Wait for package validation to finish.
6. Review listing text, pricing, availability, and release notes if needed.
7. Submit for certification.

## Important Version Note

- If the version already live in Microsoft Store is `1.0.1.0` or higher, this package must be rebuilt with a higher version before Partner Center will accept it.
- In this project, the version currently maps from:
  - `pubspec.yaml` -> `version: 1.0.1+2`
  - `pubspec.yaml` -> `msix_config.msix_version: 1.0.1.0`

## Practical Notes

- The Microsoft Store signs and distributes the app for store installs, so the local `Unknown publisher` warning you saw on direct `.msix` install is not the thing that matters for Partner Center upload.
- For website downloads, keep using the portable ZIP or direct APK strategy.
- For Microsoft Store, upload the `.msixupload`.

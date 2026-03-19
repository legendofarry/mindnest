# MindNest Release Todo

## How we track fixes

- [ ] Record fixes only when you explicitly tell me to add them
- [ ] First recorded fix from you: Windows app should open as a proper desktop app without the unwanted top bar / non-fullscreen presentation

## Windows

- [x] Set up Windows build toolchain
- [x] Build first Windows release `.exe`
- [x] Create first Windows `MSIX` package
- [x] Submit first Microsoft Store package for certification
- [ ] Wait for Microsoft Store certification result
- [ ] Windows `Continue with Google` should work fully
- [ ] Windows breadcrumbs UI/UX redesign in the Create Account screen
- [ ] Replace placeholder Windows app icon in `windows/runner/resources/app_icon.ico`
- [ ] Decide Windows launch behavior: normal window, maximized, or fullscreen
- [ ] Fix Windows launch presentation so the app behaves like a true desktop app
- [ ] Add top-right in-app window controls on Windows auth screens and main dashboard screens so users can exit the app when the native top bar is removed
- [ ] Investigate and fix the Windows startup layout/content-height issue if it still appears
- [ ] Test Windows-specific auth, dashboard, counselor, and institution flows
- [ ] Prepare first Windows update workflow
- [ ] Bump Windows Store package version for every update
- [ ] Review any Microsoft feedback about `runFullTrust` if certification flags it

## Android

- [ ] Install Android Studio and Android SDK
- [ ] Make `flutter doctor` pass for Android
- [ ] Build first Android release APK
- [ ] Create Android signing keystore
- [ ] Decide Play Store vs direct APK distribution
- [ ] Test Android navigation and system back behavior
- [ ] Review Android notifications, permissions, and auth flows

## iOS

- [ ] Move project to a Mac build environment
- [ ] Install Xcode and iOS tooling
- [ ] Configure Apple Developer signing
- [ ] Build first iOS release
- [ ] Prepare App Store Connect listing
- [ ] Test iPhone navigation, safe areas, and gesture behavior
- [ ] Review iOS notifications, permissions, and auth flows

## Cross-platform

- [ ] Replace placeholder/native icons on all platforms
- [ ] Review breadcrumb behavior by platform
- [ ] Review desktop shell vs mobile shell behavior
- [ ] Fix auth flow layout issues found during device testing
- [ ] Do a dedicated accessibility pass
- [ ] Prepare better store screenshots and marketing assets
- [ ] Refine store copy and listing descriptions if needed

## Later fixes

- [ ] Windows fullscreen or maximized launch behavior
- [ ] Windows native title bar vs custom title bar decision
- [ ] Windows top-strip/content-fill issue
- [ ] Full QA pass after initial publishing setup

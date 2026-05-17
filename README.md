# perfect_flutter

DevTools-based pixel-perfect overlay for Flutter. Overlay a design image on
top of your running app — emulator, simulator, or physical device — from the
DevTools panel. **No widget wrapping. No conditional debug paths.** A
`dev_dependencies` entry plus one import line.

> Status: pre-alpha. Sprints 1–2 of 6 done — panel discoverable, VM service
> connection working, end-to-end overlay injection verified on a physical
> Android device (2026-05-17). Image upload + transforms land in S3–S4.

## Why

Existing Flutter pixel-perfect packages require wrapping the root widget
(`PixelPerfect(child: MyApp())`), which pollutes the tree and risks shipping
overlay plumbing into release builds. `perfect_flutter` leaves your widget
tree untouched: the DevTools extension uses the VM service to call into a
small runtime helper, which inserts an `OverlayEntry` into the running
isolate. In release builds, tree-shaking strips the helper.

## Install (forthcoming)

1. Add to your app's `pubspec.yaml`:

   ```yaml
   dev_dependencies:
     perfect_flutter: ^0.1.0
   ```

2. Add one import at the top of `lib/main.dart`:

   ```dart
   // ignore: unused_import, depend_on_referenced_packages
   import 'package:perfect_flutter/perfect_flutter.dart';
   ```

   The import is required so the runtime helper is linked into the debug
   build. It has no runtime effect — release builds tree-shake it away. **Do
   not let your IDE auto-remove this import** (e.g. via "Organize Imports" or
   `dart fix`) — it will silently break the tool. The `// ignore: ...`
   comment suppresses the "unused import" lint.

3. `flutter pub get`
4. Run the app in debug mode.
5. Open DevTools → "Perfect Flutter" tab appears.
6. Upload a design image → overlay renders on device.

No widget wrapping. No `runApp` changes.

## Repo layout

```
perfect-flutter/
  packages/
    perfect_flutter/                    # published — runtime + bundled extension
    perfect_flutter_devtools_extension/ # internal — Flutter web app (the panel UI)
  scripts/
    build_extension.sh                  # bundles extension into runtime package
```

See [PIXEL_PERFECT_PLAN.md](PIXEL_PERFECT_PLAN.md) for design and
[SPRINT_PLAN.md](SPRINT_PLAN.md) for the roadmap.

## Development

Requires Flutter 3.10+ (tested on 3.41).

```bash
dart pub global activate melos ^6.3.0
melos bootstrap
melos run analyze
melos run test
melos run build:extension
```

## License

MIT — see [LICENSE](LICENSE).

# perfect_flutter

DevTools-based pixel-perfect overlay for Flutter. Overlay a design image on
top of your running app — emulator, simulator, or physical device — from the
DevTools panel. **No widget wrapping. No app code changes.** Just a single
`dev_dependencies` entry.

> Status: pre-alpha. Sprint 1 of 6 (foundation) — panel discoverable, VM
> service connection working. Overlay injection lands in Sprint 2.

## Why

Existing Flutter pixel-perfect packages require wrapping the root widget
(`PixelPerfect(child: MyApp())`), which pollutes the tree and risks shipping
overlay plumbing into release builds. `perfect_flutter` keeps the app
untouched: the DevTools extension uses the VM service to inject an
`OverlayEntry` into the running isolate.

## Install (forthcoming)

```yaml
dev_dependencies:
  perfect_flutter: ^0.1.0
```

Then:

1. `flutter pub get`
2. Run the app in debug mode.
3. Open DevTools → "Perfect Flutter" tab appears.
4. Upload a design image → overlay renders on device.

No imports. No `main.dart` changes.

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

# Changelog

## 0.1.0

Initial public release.

- **One-import integration.** Add `perfect_flutter` to `dev_dependencies`
  plus a single `import 'package:perfect_flutter/perfect_flutter.dart';`
  line in your app. No widget wrapping, no `runApp` changes.
- **DevTools panel.** Discoverable as the **Perfect Flutter** tab whenever
  the consumer app declares the package in `dev_dependencies`.
- **Image upload.** Native file picker in the panel, chunked base64
  transport (256 KB per `evaluate` call), validated for 1–5 MB PNG/JPG
  designs.
- **Transform controls.** Opacity slider, scale as numeric ±5%, offset
  X/Y as numeric ±1 px, flip H/V toggles. All updates throttled via a
  latest-value-wins queue to keep the wire to one in-flight eval at a
  time.
- **Display controls.** Global show/hide; opt-in **Follow scroll** that
  re-picks the on-screen vertical scrollable every frame by visible-area
  on screen, so route changes and nested inner scrollables (dropdowns,
  tab inners) don't break tracking.
- **Hot-restart resilience.** Image bytes and transform values are
  persisted to `localStorage`; auto-restore replays them against the new
  isolate within ~2s, with a manual **Restore** button as fallback.
- **Hot reload from panel.** ⚡ app-bar button calls
  `service.reloadSources`; falls back to a friendly "press `r` in your
  terminal" message when the kernel task is owned by `flutter run`.
- **Keyboard shortcuts** for offset (Arrows / Shift+Arrows), opacity
  (`[`/`]`), scale (`-`/`=`), flip (`h`/`v`), show/hide (`space`).
  Discoverable via the keyboard icon in the app bar.
- **Release safety.** Two layers: tree-shaking strips the unreachable
  `PerfectFlutter` class from release builds, and the VM service used by
  the panel doesn't exist in release builds anyway.

### Stability fixes

- **Scheduler-phase safety for evals.** `service.evaluate` can land in any
  scheduler phase, including mid-build/layout/paint. Notifier mutations
  during those phases caused `ListenableBuilder` rebuilds to throw
  "Build scheduled during frame" — `ChangeNotifier` swallowed the throw
  inside `FlutterError.reportError`, so the eval looked successful to the
  panel but the overlay never rebuilt. All setters and `OverlayState.insert`
  now route through a `_safeApply` helper that defers to the next
  post-frame callback when the current phase isn't safe.
- **Transform queue timeout + reset.** `LatestValueQueue` now timeouts a
  hung eval after 3s (e.g. paused isolate, transient disconnect) and
  releases the in-flight flag in a `finally` block. Added a `reset()`
  method so isolate swaps don't leave the queue holding a Future from a
  dead connection.

## 0.0.1

- Initial scaffold. DevTools extension panel discoverable from a consuming
  app (hello world panel showing isolate info).

# perfect_flutter

DevTools-based pixel-perfect overlay for Flutter. Overlay a design image on
top of your running app — emulator, simulator, or physical device — from the
DevTools panel. **No widget wrapping. No conditional debug paths.**

A `dev_dependencies` entry plus one import line is all the consumer app code
this tool requires. In release builds, tree-shaking removes everything.

## Install

1. Add to your app's `pubspec.yaml`:

   ```yaml
   dev_dependencies:
     perfect_flutter: ^0.1.33
   ```

2. Add one import at the top of `lib/main.dart` (anywhere in your app works,
   but the top of `main.dart` is conventional):

   ```dart
   // ignore: unused_import, depend_on_referenced_packages
   import 'package:perfect_flutter/perfect_flutter.dart';
   ```

   The import has no runtime effect — it only ensures the runtime helper
   class is linked into the debug build so the DevTools panel can call it
   via the VM service. **Do not let your IDE auto-remove this import**
   (e.g. via "Organize Imports" or `dart fix`) — it will silently break the
   tool. The `// ignore: ...` comment suppresses the "unused import" lint.

3. `flutter pub get`

4. Run the app in debug mode (`flutter run`, or `F5` in your IDE).

5. Open DevTools → click the **Perfect Flutter** tab.

6. Upload a design image → the overlay renders on the device, centered and
   half-opaque by default. Adjust opacity, offset, scale, and flip from
   the panel.

No widget wrapping. No `runApp` changes. No conditional debug branches.

## Features

### Inject an overlay and upload a design

Click **Inject** in the panel → a magenta placeholder renders on the device.
Then pick a PNG / JPG — the upload streams in 256 KB chunks with a progress
bar and the overlay replaces the placeholder at 50% opacity, centered.

![Inject overlay and upload a design](https://github.com/Hankium/perfect-flutter/blob/main/doc/gifs/startup.gif?raw=true)

### Follow scroll

Opt-in toggle (off by default). The overlay translates with the app's
currently-visible vertical scrollable. Picks the right scrollable per-frame
by visible area, so route changes and nested inner lists handle cleanly.

![Follow scroll](https://github.com/Hankium/perfect-flutter/blob/main/doc/gifs/scroll.gif?raw=true)

### Opacity

Slider from 0 to 1.

![Opacity](https://github.com/Hankium/perfect-flutter/blob/main/doc/gifs/opacity.gif?raw=true)

### Offset, scale, flip

Numeric rows with ±1 px nudges for offset; multiplicative ±5% per click for
scale (range 0.01–100); toggle chips for flip H / V.

![Transform controls](https://github.com/Hankium/perfect-flutter/blob/main/doc/gifs/controls.gif?raw=true)

### Hot-restart resilience

Image bytes + transforms persist to `localStorage` and auto-restore against
the new isolate within ~2s. Manual **Restore** button as fallback if the
DevTools iframe remounts before the auto-trigger fires.

### Hot reload from panel

The ⚡ app-bar button calls `service.reloadSources`; falls back to a
"press `r` in your terminal" message when the kernel task is owned by
`flutter run`.

### Keyboard shortcuts

Arrows = ±1 px offset, Shift+Arrows = ±10 px, `[` / `]` = opacity ±5%,
`-` / `=` = scale ±5%, `h` / `v` = flip, `space` = show/hide. Discoverable
via the keyboard icon in the app bar.

### Touch passthrough

Taps, scrolls, drags, and gestures all pass through to the app — the
overlay sits behind an `IgnorePointer`. You can interact with your app
normally while comparing against the design.

## FAQ

### Does perfect_flutter ship in release builds?

No. Two layers of defense:

1. **Tree-shaking.** Nothing in your app *calls* `PerfectFlutter.*` — the
   class and everything it references are unreachable from `main()`, so
   Flutter's release builder strips them.
2. **VM service is debug-only.** Even if the runtime code somehow survived
   tree-shaking, the DevTools extension would have nothing to talk to.

Adding to `dev_dependencies` is belt + braces.

### Why do I need the import line?

Dart's VM debug expression evaluator only accepts arrow-bodied function
literals — block bodies and IIFEs fail to parse. That makes a true
"zero app code" architecture infeasible. The import is the one-line cost
of having a normal Dart helper class that the panel can call short
expressions against (`PerfectFlutter.inject()`, `setOpacity(0.5)`, etc.)
instead of stuffing every feature into a single arrow expression.

### My IDE keeps removing the import.

Use the `// ignore: unused_import, depend_on_referenced_packages` comment
shown above. Most "Organize Imports" actions respect it. If yours doesn't,
disable that action for the file containing the import, or reference the
`PerfectFlutter` symbol once (e.g. `// ignore: unused_local_variable
final _ = PerfectFlutter;`) to mark it used.

### The DevTools tab doesn't appear.

- Confirm `perfect_flutter` is in `dev_dependencies` and `flutter pub get`
  has run.
- Reload the DevTools page. The extension is discovered via
  `.dart_tool/package_config.json`, which is rewritten by `pub get`.
- Some setups need a full DevTools restart after the first `pub get`.

### The Inject button shows "perfect_flutter runtime not loaded".

The consumer app is missing the `package:perfect_flutter/perfect_flutter.dart`
import (or your IDE removed it). Add it back.

### The overlay is clipped at the bottom on long screens.

The overlay is bounded by the viewport. Toggle on **Follow scroll** in the
Display section so the overlay translates with content as you scroll.

### Can I overlay multiple images at once?

No — single overlay only. Multi-layer was considered and scoped out as
feature creep; the pixel-perfect comparison flow works fine with one
design at a time.

### Hot restart loses the overlay.

It re-injects automatically. On `R` in `flutter run`, the panel waits ~2s
for the new isolate to finish `runApp()`, then re-injects + re-uploads
the cached image + replays transforms. If the DevTools iframe remounts
before the auto-trigger fires, a **Restore** button appears next to
Inject — click it.

## Compatibility

- Flutter 3.10+
- Debug builds only (VM service is required)
- Verified end-to-end on `MaterialApp` on physical Android.
  `CupertinoApp` and custom-root apps should work but are not yet
  exhaustively tested.

## Links

- Source: <https://github.com/Hankium/perfect-flutter>
- Issues: <https://github.com/Hankium/perfect-flutter/issues>

## License

MIT — see [LICENSE](LICENSE).

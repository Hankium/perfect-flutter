# perfect_flutter

DevTools-based pixel-perfect overlay for Flutter. Overlay a design image on
top of your running app — emulator, simulator, or physical device — from the
DevTools panel. **No widget wrapping. No conditional debug paths.** A
`dev_dependencies` entry plus one import line.

## Why

Existing Flutter pixel-perfect packages require wrapping the root widget
(`Package(child: MyApp())`), which pollutes the tree and risks shipping
overlay plumbing into release builds. `perfect_flutter` leaves your widget
tree untouched: the DevTools extension uses the VM service to call into a
small runtime helper, which inserts an `OverlayEntry` into the running
isolate. In release builds, tree-shaking strips the helper.

## Install

1. Add to your app's `pubspec.yaml`:

   ```yaml
   dev_dependencies:
     perfect_flutter: ^0.1.32
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

No widget wrapping. No `runApp` changes.

## Run and test

### 1. Start the app in debug mode

Pick whichever you normally use:

- **Terminal:** `flutter run`
- **VS Code:** press `F5` (or _Run > Start Debugging_)
- **Android Studio / IntelliJ:** click the green _Run_ arrow

Target an emulator, simulator, or physical device — perfect_flutter works
on all of them. Web targets work too, but only in debug builds (the VM
service is required).

### 2. Open DevTools and find the panel

DevTools shows up differently depending on how you launched the app:

- **`flutter run`:** the terminal prints
  `The Flutter DevTools debugger and profiler is available at: http://127.0.0.1:yyyy/?uri=...`.
  Open that URL in your browser.
- **VS Code:** open the command palette (`Ctrl/Cmd+Shift+P`) and run
  `Dart: Open DevTools` — pick the _Open in Web Browser_ option for the
  best experience. The "Open DevTools Page" picker only lists built-in
  pages and won't show extensions; use the full DevTools UI instead.
- **Android Studio / IntelliJ:** click the _Open DevTools_ button in the
  Flutter Inspector toolbar.

Once DevTools loads, click the **Perfect Flutter** tab at the top. If it
isn't there:

- Confirm `perfect_flutter` is in `dev_dependencies` and `flutter pub get`
  has run.
- Reload the DevTools page — the extension is discovered via
  `.dart_tool/package_config.json`, which is rewritten by `pub get`.

### 3. Inject the overlay and upload a design

1. Click **Inject overlay** in the panel — a magenta placeholder renders
   on the device. This confirms the runtime helper is reachable.
2. Click **Choose image** and pick the PNG / JPG you want to compare
   against. The upload streams in 256 KB chunks with a progress bar.
   Tested cleanly on 1–5 MB images.
3. The overlay replaces the placeholder, centered and at 50% opacity by
   default.

### 4. Align the overlay

Use the panel controls:

- **Opacity** — slider, 0 to 1.
- **Scale** — numeric row with ± buttons (multiplicative ±5% per click,
  range 0.01–100).
- **Offset X / Y** — numeric rows with ±1 px nudges.
- **Flip H / V** — toggle chips.
- **Show / hide** — temporarily hide the overlay without losing state.
- **Follow scroll** — opt-in toggle that translates the overlay with the
  app's currently-visible vertical scrollable. Picks the right scrollable
  per-frame by visible area, so route changes and inner lists handle
  cleanly.

Or use keyboard shortcuts (focus the panel first):

| Key        | Action                        |
| ---------- | ----------------------------- |
| Arrow keys | Offset ±1 px (Shift = ±10 px) |
| `[` / `]`  | Opacity ±5%                   |
| `-` / `=`  | Scale ±5%                     |
| `h` / `v`  | Flip horizontal / vertical    |
| `space`    | Show / hide overlay           |

The keyboard icon in the panel's app bar opens a cheat sheet.

### 5. Hot reload and hot restart

- **`r` in `flutter run`** (or save a file in VS Code) — hot reload
  preserves the overlay and all transform values. The ⚡ button in the
  panel calls `service.reloadSources` and works for some setups; when it
  can't reach the kernel task (typical for `flutter run`-owned apps) it
  falls back to a "press `r` in your terminal" message.
- **`R` in `flutter run`** (or hot restart from your IDE) — the overlay
  is wiped along with the rest of Dart memory. perfect_flutter persists
  the image and transforms in the panel's `localStorage` and tries to
  auto-restore within ~2s of the new isolate coming up. If the DevTools
  iframe remounts before the auto-trigger fires, a **Restore** button
  appears next to _Inject_ — click it.

### Touch / gesture passthrough

The overlay sits behind an `IgnorePointer`, so taps, scrolls, drags, and
gestures all pass through to the app as if the overlay weren't there. You
can interact with your app normally while comparing against the design.

### Troubleshooting

- **`Inject` says "perfect_flutter runtime not loaded"** — the consumer
  app is missing the `package:perfect_flutter/perfect_flutter.dart`
  import, or your IDE removed it. Add it back.
- **Sliders look like they do nothing** — check the error banner in the
  panel; the throttle queue surfaces eval failures (paused isolate,
  disconnected DDS, etc.).
- **Overlay clipped at the bottom on long screens** — toggle on
  **Follow scroll** in the Display section.
- **Image upload fails on very large files** — try ≤ 5 MB. Larger images
  also fail to persist to `localStorage` (browser quota ~5–10 MB per
  origin) and degrade to in-memory only.

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

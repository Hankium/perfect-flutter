/// perfect_flutter — DevTools-based pixel-perfect overlay for Flutter.
///
/// Add `perfect_flutter` to `dev_dependencies` and add a single import of this
/// library somewhere in your app (commonly at the top of `main.dart`):
///
/// ```dart
/// import 'package:perfect_flutter/perfect_flutter.dart';
/// ```
///
/// The import has no runtime effect — it only ensures the helper class below
/// is linked into the debug build so the DevTools panel can call it via the
/// VM service. In release builds, tree-shaking removes everything.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Internal helper called by the DevTools panel through `evaluate`.
/// Not intended to be called from app code.
class PerfectFlutter {
  PerfectFlutter._();

  /// The decoded design image, or null while no upload has completed.
  static final ValueNotifier<MemoryImage?> _image =
      ValueNotifier<MemoryImage?>(null);

  /// Overlay opacity in `[0, 1]`. 0.5 by default for natural design-vs-app
  /// comparison.
  static final ValueNotifier<double> _opacity = ValueNotifier<double>(0.5);

  /// Translation in logical pixels, applied to the image as a whole.
  static final ValueNotifier<Offset> _offset =
      ValueNotifier<Offset>(Offset.zero);

  /// Uniform scale factor. 1.0 = native; <1 shrinks; >1 enlarges.
  static final ValueNotifier<double> _scale = ValueNotifier<double>(1.0);

  /// Horizontal flip (mirror around image's vertical center).
  static final ValueNotifier<bool> _flipH = ValueNotifier<bool>(false);

  /// Vertical flip (mirror around image's horizontal center).
  static final ValueNotifier<bool> _flipV = ValueNotifier<bool>(false);

  /// Global show/hide. When false, the overlay renders nothing (touches
  /// still pass through naturally because there is no widget to intercept).
  static final ValueNotifier<bool> _visible = ValueNotifier<bool>(true);

  /// "Follow scroll" feature: when true, the overlay translates with the
  /// app's primary vertical scrollable so long-screen designs stay aligned
  /// while the user scrolls. Off by default — fixed-viewport behavior is
  /// the right default for short screens / dialogs / design system pages.
  static final ValueNotifier<bool> _followScroll = ValueNotifier<bool>(false);

  /// Current Y scroll offset of the tracked scrollable. Subtracted from
  /// the user's manual Y offset so the overlay appears to scroll with the
  /// app content.
  static final ValueNotifier<double> _scrollOffsetY = ValueNotifier<double>(0);

  /// Guards against scheduling more than one post-frame tick at a time.
  /// The tick re-schedules itself while [_followScroll] is true; toggling
  /// off lets the chain decay naturally on the next frame.
  static bool _followTickScheduled = false;

  /// Buffer of base64-encoded image chunks accumulated by [appendChunk] and
  /// drained by [commitImage]. Buffered as a string rather than bytes to keep
  /// the [appendChunk] call simple (panel sends base64 directly).
  static final StringBuffer _chunkBuffer = StringBuffer();

  /// The currently injected entry, if any. Used to make [inject] idempotent
  /// across panel reloads (refreshing the DevTools tab wipes the panel's
  /// state but the app's overlay is still there). Reset on hot restart
  /// because the entire isolate restarts, taking this static with it.
  static OverlayEntry? _entry;

  /// Walks the widget tree from the root element, locates the first
  /// [OverlayState], inserts a single [OverlayEntry] that listens to all
  /// transform notifiers, and returns the entry so the panel can later
  /// remove it.
  ///
  /// Idempotent: if an entry is already injected and still mounted, the
  /// existing entry is returned and no new one is inserted.
  static OverlayEntry inject() {
    final existing = _entry;
    if (existing != null && existing.mounted) {
      return existing;
    }
    // Initialize the binding if the app hasn't yet (e.g. inject was clicked
    // immediately after hot restart, before main()/runApp() finished). This
    // is idempotent and matches what runApp() does anyway.
    WidgetsFlutterBinding.ensureInitialized();
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      throw StateError(
        'perfect_flutter: no rootElement yet — the app has not rendered '
        'its first frame. Wait a moment and try again.',
      );
    }
    OverlayState? overlay;
    void visit(Element e) {
      if (overlay != null) return;
      if (e is StatefulElement && e.state is OverlayState) {
        overlay = e.state as OverlayState;
        return;
      }
      e.visitChildren(visit);
    }

    visit(root);
    if (overlay == null) {
      throw StateError(
        'perfect_flutter: no Overlay found in the widget tree.',
      );
    }
    final entry = OverlayEntry(
      builder: (ctx) => Positioned.fill(
        child: IgnorePointer(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _image,
              _opacity,
              _offset,
              _scale,
              _flipH,
              _flipV,
              _visible,
              _scrollOffsetY,
            ]),
            builder: (_, __) {
              if (!_visible.value) return const SizedBox.shrink();
              final img = _image.value;
              if (img == null) return _placeholder();
              return _imageOverlay(img);
            },
          ),
        ),
      ),
    );
    _entry = entry;
    final captured = overlay!;
    _safeApply(() => captured.insert(entry));
    return entry;
  }

  /// Runs [fn] in a scheduler phase where `setState` is legal. `service.
  /// evaluate` calls land in arbitrary phases, including build / layout /
  /// paint; mutating a `ValueNotifier` during those phases causes the
  /// `ListenableBuilder` listener to call `setState`, which the framework
  /// rejects with "Build scheduled during frame". `ChangeNotifier` swallows
  /// the throw in `FlutterError.reportError`, so the eval looks successful
  /// to the panel — but the overlay never rebuilds. Defer to post-frame
  /// whenever we'd otherwise hit that path.
  static void _safeApply(VoidCallback fn) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      fn();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    }
  }

  /// Removes a previously injected [OverlayEntry].
  static void remove(OverlayEntry entry) {
    entry.remove();
    if (identical(_entry, entry)) _entry = null;
  }

  /// Appends a base64-encoded chunk of the design image to the internal
  /// buffer. The panel splits large images into ~256 KB chunks and calls
  /// this once per chunk via `evaluate`.
  static void appendChunk(String base64Chunk) {
    _chunkBuffer.write(base64Chunk);
  }

  /// Decodes the buffered chunks into a [MemoryImage] and publishes it to
  /// the overlay. Clears the buffer regardless of outcome.
  static void commitImage() {
    final base64Str = _chunkBuffer.toString();
    _chunkBuffer.clear();
    if (base64Str.isEmpty) {
      throw StateError('perfect_flutter: no chunks to commit.');
    }
    final Uint8List bytes = base64Decode(base64Str);
    _safeApply(() => _image.value = MemoryImage(bytes));
  }

  /// Clears any in-flight chunks and returns the overlay to its placeholder.
  static void clearImage() {
    _chunkBuffer.clear();
    _safeApply(() => _image.value = null);
  }

  // Transform setters — each one mutates a single notifier and the
  // [ListenableBuilder] rebuilds only the overlay subtree. The panel calls
  // these via short eval expressions, e.g. `PerfectFlutter.setOpacity(0.5)`.
  // All setters defer through [_safeApply] because evals can land in any
  // scheduler phase.

  /// Sets overlay opacity, clamped to `[0, 1]`.
  static void setOpacity(double v) =>
      _safeApply(() => _opacity.value = v.clamp(0.0, 1.0));

  /// Sets overlay translation in logical pixels.
  static void setOffset(double dx, double dy) =>
      _safeApply(() => _offset.value = Offset(dx, dy));

  /// Sets uniform scale, clamped to a sane range.
  static void setScale(double v) =>
      _safeApply(() => _scale.value = v.clamp(0.01, 100.0));

  /// Toggles horizontal mirror.
  static void setFlipH(bool v) => _safeApply(() => _flipH.value = v);

  /// Toggles vertical mirror.
  static void setFlipV(bool v) => _safeApply(() => _flipV.value = v);

  /// Shows or hides the overlay without removing the entry. State (image,
  /// transforms, follow-scroll attachment) is preserved while hidden.
  static void setVisible(bool v) => _safeApply(() => _visible.value = v);

  /// Toggles Follow scroll. Instead of attaching a listener to a single
  /// [ScrollPosition] picked at toggle time (which goes stale on screen
  /// navigation and frequently picks a deeply-nested inner scrollable on
  /// complex screens), this re-picks the currently visible scrollable
  /// every frame via a render-aware walk — see [_findActiveScrollPosition].
  ///
  /// Toggling on schedules the first post-frame tick. The tick re-schedules
  /// itself while [_followScroll] stays true; toggling off lets the chain
  /// decay on the next frame (no removal API for post-frame callbacks).
  static void setFollowScroll(bool v) {
    if (_followScroll.value == v) return;
    _safeApply(() {
      _followScroll.value = v;
      if (!v) _scrollOffsetY.value = 0;
    });
    if (v) _scheduleFollowTick();
  }

  static void _scheduleFollowTick() {
    if (_followTickScheduled) return;
    _followTickScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followTickScheduled = false;
      if (!_followScroll.value) return;
      final pos = _findActiveScrollPosition();
      if (pos != null && pos.hasContentDimensions) {
        // ValueNotifier short-circuits identical values, but the explicit
        // check avoids a `_safeApply` -> notify hop when the scroll hasn't
        // changed (idle screen).
        if (_scrollOffsetY.value != pos.pixels) {
          _safeApply(() => _scrollOffsetY.value = pos.pixels);
        }
      }
      _scheduleFollowTick();
    });
  }

  /// Picks the vertical [ScrollPosition] whose render box covers the most
  /// screen area — works even when the app has dozens of inner scrollables
  /// (dropdowns, tab inners, slivers) because a full-screen list always
  /// beats a 200x200 dropdown by area. Re-evaluates each frame, so route
  /// changes and overlays are handled transparently.
  static ScrollPosition? _findActiveScrollPosition() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    final screen = _screenRect();
    ScrollPosition? best;
    double bestArea = 0;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        try {
          final ss = e.state as ScrollableState;
          final pos = ss.position;
          if (pos.axis != Axis.vertical || !pos.hasViewportDimension) {
            e.visitChildren(visit);
            return;
          }
          final ro = ss.context.findRenderObject();
          if (ro is RenderBox && ro.attached && ro.hasSize) {
            final rect = ro.localToGlobal(Offset.zero) & ro.size;
            final vis = rect.intersect(screen);
            if (!vis.isEmpty) {
              final area = vis.width * vis.height;
              if (area > bestArea) {
                bestArea = area;
                best = pos;
              }
            }
          }
        } catch (_) {
          // Position not yet attached or render object not laid out; skip.
        }
      }
      e.visitChildren(visit);
    }

    visit(root);
    return best;
  }

  /// Logical-pixel rect of the implicit view. Falls back to the root
  /// render object's size if the platform view isn't accessible yet.
  static Rect _screenRect() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      final size = view.physicalSize / view.devicePixelRatio;
      return Offset.zero & Size(size.width, size.height);
    }
    final ro = WidgetsBinding.instance.rootElement?.findRenderObject();
    if (ro is RenderBox && ro.hasSize) return Offset.zero & ro.size;
    return Rect.zero;
  }

  static Widget _placeholder() => Container(
        color: const Color(0x55FF00FF),
        alignment: Alignment.center,
        child: const Text(
          'perfect_flutter (no image)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  /// Builds the composed overlay tree. Order matters:
  ///
  ///   translate ← outermost (positions whole result)
  ///     scale   ← uniform zoom, anchored at top-left so the offset
  ///               positions the image's top-left corner
  ///       flip  ← mirror in place (center-aligned)
  ///         Image
  ///
  /// Opacity is applied on the Image via its `opacity` parameter, and
  /// FilterQuality.none avoids blur when scaled (matches the S4 risk note
  /// in the sprint plan).
  static Widget _imageOverlay(MemoryImage image) => Transform.translate(
        // Follow scroll: subtract the tracked scrollable's pixel offset so
        // the overlay appears to move with content as the user scrolls.
        offset: _offset.value + Offset(0, -_scrollOffsetY.value),
        child: Transform.scale(
          scale: _scale.value,
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scaleX: _flipH.value ? -1.0 : 1.0,
            scaleY: _flipV.value ? -1.0 : 1.0,
            child: Opacity(
              opacity: _opacity.value,
              child: Image(
                image: image,
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
      );
}

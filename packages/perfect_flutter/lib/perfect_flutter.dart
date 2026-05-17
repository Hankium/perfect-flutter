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

/// Internal helper called by the DevTools panel through `evaluate`.
/// Not intended to be called from app code.
class PerfectFlutter {
  PerfectFlutter._();

  /// The decoded design image, or null while no upload has completed.
  static final ValueNotifier<MemoryImage?> _image =
      ValueNotifier<MemoryImage?>(null);

  /// Overlay opacity in [0, 1]. 0.5 by default for natural design-vs-app
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
  static final ValueNotifier<double> _scrollOffsetY =
      ValueNotifier<double>(0);

  /// Scrollable position currently being followed. Captured at the moment
  /// the user toggles Follow scroll on; cleared on toggle off.
  static ScrollPosition? _trackedPosition;

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
    overlay!.insert(entry);
    _entry = entry;
    return entry;
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
    _image.value = MemoryImage(bytes);
  }

  /// Clears any in-flight chunks and returns the overlay to its placeholder.
  static void clearImage() {
    _chunkBuffer.clear();
    _image.value = null;
  }

  // Transform setters — each one mutates a single notifier and the
  // [ListenableBuilder] rebuilds only the overlay subtree. The panel calls
  // these via short eval expressions, e.g. `PerfectFlutter.setOpacity(0.5)`.

  /// Sets overlay opacity, clamped to [0, 1].
  static void setOpacity(double v) => _opacity.value = v.clamp(0.0, 1.0);

  /// Sets overlay translation in logical pixels.
  static void setOffset(double dx, double dy) =>
      _offset.value = Offset(dx, dy);

  /// Sets uniform scale, clamped to a sane range.
  static void setScale(double v) => _scale.value = v.clamp(0.01, 100.0);

  /// Toggles horizontal mirror.
  static void setFlipH(bool v) => _flipH.value = v;

  /// Toggles vertical mirror.
  static void setFlipV(bool v) => _flipV.value = v;

  /// Shows or hides the overlay without removing the entry. State (image,
  /// transforms, follow-scroll attachment) is preserved while hidden.
  static void setVisible(bool v) => _visible.value = v;

  /// Toggles Follow scroll. Attaches to the largest vertical scrollable in
  /// the app on the next frame. If no scrollable is present yet, the
  /// attachment quietly no-ops — re-toggle after navigating to a screen
  /// with a scroll view, or the panel can offer a Rescan button later.
  static void setFollowScroll(bool v) {
    if (_followScroll.value == v) return;
    _followScroll.value = v;
    if (v) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_followScroll.value) return;
        final pos = _findPrimaryScrollPosition();
        if (pos == null) return;
        _trackedPosition = pos;
        _scrollOffsetY.value = pos.pixels;
        pos.addListener(_onScrollChanged);
      });
    } else {
      _detachScroll();
    }
  }

  static void _onScrollChanged() {
    final pos = _trackedPosition;
    if (pos == null) return;
    if (pos.hasContentDimensions) {
      _scrollOffsetY.value = pos.pixels;
    }
  }

  static void _detachScroll() {
    _trackedPosition?.removeListener(_onScrollChanged);
    _trackedPosition = null;
    _scrollOffsetY.value = 0;
  }

  /// Walks the Element tree from rootElement and returns the
  /// [ScrollPosition] of the largest vertical scrollable on screen.
  /// "Largest" is measured by viewport dimension, which correlates well
  /// with "the main page scroller" vs. small nested lists.
  static ScrollPosition? _findPrimaryScrollPosition() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    ScrollPosition? best;
    double bestDim = 0;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        try {
          final pos = (e.state as ScrollableState).position;
          if (pos.axis == Axis.vertical && pos.hasViewportDimension) {
            if (pos.viewportDimension > bestDim) {
              best = pos;
              bestDim = pos.viewportDimension;
            }
          }
        } catch (_) {
          // Position not yet attached; skip.
        }
      }
      e.visitChildren(visit);
    }
    visit(root);
    return best;
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
        offset:
            _offset.value + Offset(0, -_scrollOffsetY.value),
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

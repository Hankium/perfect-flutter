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

import 'package:flutter/material.dart';

/// Internal injection helper called by the DevTools panel through `evaluate`.
/// Not intended to be called from app code.
class PerfectFlutter {
  PerfectFlutter._();

  /// Walks the widget tree from the root element, locates the first
  /// [OverlayState], inserts a placeholder [OverlayEntry], and returns the
  /// entry so the panel can later remove it.
  static OverlayEntry inject() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      throw StateError(
        'perfect_flutter: no rootElement yet (first frame not rendered).',
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
      builder: (ctx) => IgnorePointer(
        child: Container(
          color: const Color(0x55FF00FF),
          alignment: Alignment.center,
          child: const Text(
            'perfect_flutter',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
    overlay!.insert(entry);
    return entry;
  }

  /// Removes a previously injected [OverlayEntry].
  static void remove(OverlayEntry entry) => entry.remove();
}

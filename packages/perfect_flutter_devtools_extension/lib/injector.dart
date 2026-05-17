// Injection logic. The panel uses VM service `evaluate` to run Dart
// expressions inside the running app's isolate. Because evaluate only accepts
// single expressions (not statements), the body is wrapped in an IIFE.
//
// State across calls is held panel-side: inject() returns the OverlayEntry's
// InstanceRef id, which we pass back through `scope` on remove().

import 'package:vm_service/vm_service.dart';

class InjectionResult {
  const InjectionResult({
    required this.entryRef,
    required this.targetLibraryUri,
  });

  final String entryRef;
  final String targetLibraryUri;
}

class Injector {
  // Single Dart expression. Walks the widget tree from the root element to
  // find the first OverlayState, inserts a placeholder OverlayEntry, and
  // returns the entry so the panel can later remove it.
  static const String _injectExpression = r'''
(() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    throw StateError('perfect_flutter: no rootElement yet (first frame not rendered).');
  }
  OverlayState? overlay;
  void visit(Element e) {
    if (overlay != null) return;
    if (e is StatefulElement) {
      final state = e.state;
      if (state is OverlayState) {
        overlay = state;
        return;
      }
    }
    e.visitChildren(visit);
  }
  visit(root);
  if (overlay == null) {
    throw StateError('perfect_flutter: no Overlay found in the widget tree.');
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
})()
''';

  static const String _removeExpression =
      r'(() { entry.remove(); return null; })()';

  /// Picks a target library whose scope includes the Flutter widget classes
  /// we use. `package:flutter/material.dart` is the safest choice — all the
  /// types referenced in the injector are exported from it.
  static Future<LibraryRef> pickTargetLibrary(
    VmService service,
    String isolateId,
  ) async {
    final isolate = await service.getIsolate(isolateId);
    final libs = isolate.libraries ?? const <LibraryRef>[];

    for (final uri in const [
      'package:flutter/material.dart',
      'package:flutter/widgets.dart',
    ]) {
      for (final lib in libs) {
        if (lib.uri == uri && lib.id != null) return lib;
      }
    }
    throw StateError(
      'No flutter/material or flutter/widgets library in the target isolate. '
      'Is this a Flutter app running in debug mode?',
    );
  }

  static Future<InjectionResult> inject(
    VmService service,
    String isolateId,
  ) async {
    final lib = await pickTargetLibrary(service, isolateId);
    final response = await service.evaluate(
      isolateId,
      lib.id!,
      _injectExpression,
    );
    final ref = _unwrap(response);
    return InjectionResult(
      entryRef: ref.id!,
      targetLibraryUri: lib.uri ?? '',
    );
  }

  static Future<void> remove(
    VmService service,
    String isolateId,
    String entryRef,
  ) async {
    final lib = await pickTargetLibrary(service, isolateId);
    final response = await service.evaluate(
      isolateId,
      lib.id!,
      _removeExpression,
      scope: {'entry': entryRef},
    );
    _unwrap(response);
  }

  static InstanceRef _unwrap(Response response) {
    if (response is ErrorRef) {
      throw StateError('VM eval error: ${response.message}');
    }
    if (response is Sentinel) {
      throw StateError('VM eval returned sentinel: ${response.valueAsString}');
    }
    if (response is! InstanceRef) {
      throw StateError('Unexpected eval result: ${response.runtimeType}');
    }
    if (response.kind == InstanceKind.kNull) {
      // The remove expression returns null — that's success.
      return response;
    }
    if (response.id == null) {
      throw StateError('Eval returned an instance with no id.');
    }
    return response;
  }
}

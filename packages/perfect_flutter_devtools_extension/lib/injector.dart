// Injection logic. The panel uses VM service `evaluate` to call into the
// `perfect_flutter` runtime helper inside the running app's isolate.
//
// The consuming app must `import 'package:perfect_flutter/perfect_flutter.dart'`
// once (typically in main.dart). That import has no runtime effect but ensures
// the `PerfectFlutter` helper class is linked into the debug build, so the
// expressions below can reach it.
//
// State across calls is held panel-side: inject() returns the OverlayEntry's
// InstanceRef id, which we pass back through `scope` on remove().

import 'package:vm_service/vm_service.dart';

class InjectionResult {
  const InjectionResult({
    required this.entryRef,
    required this.targetLibraryUri,
    required this.targetLibraryId,
  });

  final String entryRef;
  final String targetLibraryUri;

  /// VM-service-internal id for the runtime library. Reused by transform
  /// setters to skip the `getIsolate` lookup on every slider tick.
  final String targetLibraryId;
}

class Injector {
  static const String _targetLibraryUri =
      'package:perfect_flutter/perfect_flutter.dart';

  static const String _injectExpression = 'PerfectFlutter.inject()';
  static const String _removeExpression = 'PerfectFlutter.remove(entry)';

  /// Picks the perfect_flutter runtime library. If it isn't loaded, the
  /// consuming app forgot the one-line import; we throw with a clear message.
  static Future<LibraryRef> pickTargetLibrary(
    VmService service,
    String isolateId,
  ) async {
    final isolate = await service.getIsolate(isolateId);
    final libs = isolate.libraries ?? const <LibraryRef>[];
    for (final lib in libs) {
      if (lib.uri == _targetLibraryUri && lib.id != null) return lib;
    }
    throw StateError(
      "perfect_flutter runtime not loaded. Add a single import to your app:\n"
      "  import 'package:perfect_flutter/perfect_flutter.dart';\n"
      "(typically at the top of main.dart). The import has no runtime effect "
      "but ensures the helper is linked into the debug build.",
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
      targetLibraryId: lib.id!,
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
      return response;
    }
    if (response.id == null) {
      throw StateError('Eval returned an instance with no id.');
    }
    return response;
  }
}

// Transform setters — short `evaluate` calls into `PerfectFlutter`'s static
// setters. The library id is captured once at inject time (see
// [InjectionResult.targetLibraryId]) and reused, avoiding a per-tick
// `getIsolate` round-trip during slider drags.

import 'package:vm_service/vm_service.dart';

class TransformController {
  TransformController({
    required this.service,
    required this.isolateId,
    required this.libraryId,
  });

  final VmService service;
  final String isolateId;
  final String libraryId;

  Future<void> setOpacity(double v) =>
      _eval('PerfectFlutter.setOpacity(${_d(v)})');

  Future<void> setOffset(double dx, double dy) =>
      _eval('PerfectFlutter.setOffset(${_d(dx)}, ${_d(dy)})');

  Future<void> setScale(double v) => _eval('PerfectFlutter.setScale(${_d(v)})');

  Future<void> setFlipH(bool v) => _eval('PerfectFlutter.setFlipH($v)');

  Future<void> setFlipV(bool v) => _eval('PerfectFlutter.setFlipV($v)');

  Future<void> setVisible(bool v) => _eval('PerfectFlutter.setVisible($v)');

  Future<void> setFollowScroll(bool v) =>
      _eval('PerfectFlutter.setFollowScroll($v)');

  Future<void> _eval(String expression) async {
    await service.evaluate(isolateId, libraryId, expression);
  }

  /// Renders a double as a Dart literal that always parses (avoids
  /// scientific notation surprises for very small or large values).
  static String _d(double v) => v.toStringAsFixed(6);
}

/// Coalesces rapid-fire updates to a single in-flight eval at a time. While
/// an eval is in flight, the most recent value is queued and sent as soon as
/// the previous one completes — older intermediate values are dropped.
///
/// This keeps slider drags responsive without flooding the VM service.
class LatestValueQueue<T> {
  LatestValueQueue(this._send, {this.onError});

  final Future<void> Function(T value) _send;

  /// Called with the most recent eval failure. Lets the panel surface
  /// silently-dropped errors (e.g. method not found after a hot restart,
  /// isolate disconnected) instead of leaving sliders that look like they
  /// "do nothing".
  final void Function(Object error)? onError;

  T? _pending;
  bool _pendingSet = false;
  bool _inFlight = false;

  /// Upper bound on how long any single `_send` may run before the queue
  /// gives up and resets. `service.evaluate` against a paused isolate (mid
  /// hot-reload, breakpoint hit, transient disconnect) can hang indefinitely;
  /// without a timeout, `_inFlight` stays true forever and the queue
  /// silently swallows every subsequent `submit`.
  static const Duration _sendTimeout = Duration(seconds: 3);

  /// Drops any pending value and clears the in-flight flag. Call this when
  /// the underlying connection has changed (e.g. isolate swap) so the next
  /// `submit` flushes immediately instead of queuing behind a dead Future.
  /// An old in-flight Future may still resolve later; that's harmless
  /// because `_pending` is cleared and the post-await path becomes a no-op.
  void reset() {
    _pending = null;
    _pendingSet = false;
    _inFlight = false;
  }

  void submit(T value) {
    if (_inFlight) {
      _pending = value;
      _pendingSet = true;
      return;
    }
    _flush(value);
  }

  Future<void> _flush(T value) async {
    _inFlight = true;
    try {
      await _send(value).timeout(_sendTimeout);
    } catch (e) {
      onError?.call(e);
    } finally {
      _inFlight = false;
    }
    if (_pendingSet) {
      final next = _pending as T;
      _pending = null;
      _pendingSet = false;
      submit(next);
    }
  }
}

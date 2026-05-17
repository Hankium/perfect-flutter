import 'dart:typed_data';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart';

import 'image_picker_web.dart';
import 'image_uploader.dart';
import 'injector.dart';
import 'panel_storage.dart';
import 'transforms.dart';

void main() {
  runApp(const PerfectFlutterExtension());
}

class PerfectFlutterExtension extends StatelessWidget {
  const PerfectFlutterExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: PanelHome());
  }
}

class PanelHome extends StatefulWidget {
  const PanelHome({super.key});

  @override
  State<PanelHome> createState() => _PanelHomeState();
}

class _PanelHomeState extends State<PanelHome> {
  VM? _vm;
  String? _vmError;

  InjectionResult? _injection;
  String? _injectionError;
  bool _busy = false;

  bool _uploading = false;
  double _uploadProgress = 0;
  String? _uploadError;
  String? _lastImageName;

  /// Cached image bytes used to re-upload the design after a hot restart.
  /// Lost on Chrome refresh — that's expected (panel state is per-session).
  Uint8List? _cachedImageBytes;
  bool _restoring = false;

  // Transform state — kept in sync with the runtime via [_transforms].
  TransformController? _transforms;
  double _opacity = 0.5;
  double _scale = 1.0;
  double _offsetX = 0;
  double _offsetY = 0;
  bool _flipH = false;
  bool _flipV = false;
  bool _visible = true;
  bool _followScroll = false;
  String? _transformError;

  late final TextEditingController _offsetXController =
      TextEditingController(text: '0');
  late final TextEditingController _offsetYController =
      TextEditingController(text: '0');
  late final TextEditingController _scaleController =
      TextEditingController(text: '1.00');

  late final LatestValueQueue<double> _opacityQueue = LatestValueQueue<double>(
    (v) async {
      final t = _transforms;
      if (t != null) await t.setOpacity(v);
    },
    onError: (e) => _onTransformError('Opacity', e),
  );
  late final LatestValueQueue<double> _scaleQueue = LatestValueQueue<double>(
    (v) async {
      final t = _transforms;
      if (t != null) await t.setScale(v);
    },
    onError: (e) => _onTransformError('Scale', e),
  );
  late final LatestValueQueue<Offset> _offsetQueue = LatestValueQueue<Offset>(
    (o) async {
      final t = _transforms;
      if (t != null) await t.setOffset(o.dx, o.dy);
    },
    onError: (e) => _onTransformError('Offset', e),
  );

  void _onTransformError(String label, Object error) {
    if (!mounted) return;
    setState(() => _transformError = '$label eval failed: $error');
  }

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
    _refreshVm();
    serviceManager.isolateManager.mainIsolate.addListener(_onIsolateChanged);
    // If the iframe was remounted (hot restart from terminal, Chrome refresh,
    // etc.) with cached state + a live isolate, kick off restore once the
    // first frame is in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_cachedImageBytes != null &&
          _mainIsolate?.id != null &&
          _injection == null) {
        _restoreAfterRestart();
      }
    });
  }

  /// Populates panel state from `localStorage`. Runs synchronously in
  /// `initState` so the UI shows the previous session's transform values
  /// and image name from the very first frame.
  void _loadFromStorage() {
    final t = PanelStorage.loadTransforms();
    if (t != null) {
      _opacity = (t['opacity'] as num?)?.toDouble() ?? 0.5;
      _scale = (t['scale'] as num?)?.toDouble() ?? 1.0;
      _offsetX = (t['offsetX'] as num?)?.toDouble() ?? 0;
      _offsetY = (t['offsetY'] as num?)?.toDouble() ?? 0;
      _flipH = t['flipH'] as bool? ?? false;
      _flipV = t['flipV'] as bool? ?? false;
      _visible = t['visible'] as bool? ?? true;
      _followScroll = t['followScroll'] as bool? ?? false;
      _offsetXController.text = _offsetX.round().toString();
      _offsetYController.text = _offsetY.round().toString();
      _scaleController.text = _scale.toStringAsFixed(2);
    }
    final img = PanelStorage.loadImage();
    if (img != null) {
      _cachedImageBytes = img.bytes;
      _lastImageName = img.name;
    }
  }

  /// Saves the current transform values to `localStorage`. Called from every
  /// transform handler so the persisted state matches panel state exactly.
  void _persistTransforms() {
    PanelStorage.saveTransforms(
      opacity: _opacity,
      scale: _scale,
      offsetX: _offsetX,
      offsetY: _offsetY,
      flipH: _flipH,
      flipV: _flipV,
      visible: _visible,
      followScroll: _followScroll,
    );
  }

  @override
  void dispose() {
    serviceManager.isolateManager.mainIsolate.removeListener(_onIsolateChanged);
    _offsetXController.dispose();
    _offsetYController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _onIsolateChanged() {
    // A new main isolate means any previous injection ref is invalid.
    if (!mounted) return;
    final hadCache = _cachedImageBytes != null;
    setState(() {
      _injection = null;
      _injectionError = null;
      _transforms = null;
      // Preserve transform values + cached bytes if we're about to restore.
      // Otherwise reset to defaults (fresh app, no prior session to replay).
      if (!hadCache) {
        _resetTransformsToDefaults();
        _lastImageName = null;
      }
    });
    _refreshVm();
    if (hadCache) {
      _restoreAfterRestart();
    }
  }

  /// Re-injects, re-uploads the cached image, and replays all transform
  /// values after a hot restart. Waits for the new isolate to finish
  /// initialization before any eval — hammering evals during runApp() can
  /// leave the app in a stuck state.
  Future<void> _restoreAfterRestart() async {
    if (_restoring) return;
    _restoring = true;
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Auto-restoring overlay — waiting 2s for app to stabilize…',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() => _injectionError = 'Auto-restoring overlay…');
      }
      // Give the new isolate time to finish main()/runApp() and render its
      // first frame before we touch it with any service.evaluate calls.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final service = _service;
      final iso = _mainIsolate;
      if (service == null || iso?.id == null) {
        setState(() => _injectionError = null);
        return;
      }
      final isolateId = iso!.id!;

      InjectionResult? result;
      try {
        result = await Injector.inject(service, isolateId);
      } catch (e) {
        if (mounted) {
          setState(() => _injectionError =
              'Auto-restore failed: $e\nClick Inject overlay to retry.');
        }
        return;
      }
      if (!mounted) return;

      final restored = result;
      setState(() {
        _injection = restored;
        _injectionError = null;
        _transforms = TransformController(
          service: service,
          isolateId: isolateId,
          libraryId: restored.targetLibraryId,
        );
      });

      // Re-upload bytes.
      final bytes = _cachedImageBytes;
      if (bytes != null) {
        setState(() {
          _uploading = true;
          _uploadProgress = 0;
          _uploadError = null;
        });
        try {
          await ImageUploader.upload(
            service,
            isolateId,
            bytes,
            onProgress: (p) {
              if (!mounted) return;
              setState(() => _uploadProgress = p);
            },
          );
        } catch (e) {
          if (mounted) setState(() => _uploadError = 'Restore upload: $e');
        } finally {
          if (mounted) setState(() => _uploading = false);
        }
      }

      // Replay transforms. Apply unconditionally so the runtime matches
      // panel state exactly.
      final t = _transforms;
      if (t != null) {
        try {
          await t.setOpacity(_opacity);
          await t.setScale(_scale);
          await t.setOffset(_offsetX, _offsetY);
          await t.setFlipH(_flipH);
          await t.setFlipV(_flipV);
          await t.setVisible(_visible);
          await t.setFollowScroll(_followScroll);
        } catch (e) {
          if (mounted) setState(() => _transformError = 'Restore: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Overlay restored after restart.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      _restoring = false;
    }
  }

  void _resetTransformsToDefaults() {
    _opacity = 0.5;
    _scale = 1.0;
    _offsetX = 0;
    _offsetY = 0;
    _flipH = false;
    _flipV = false;
    _visible = true;
    _followScroll = false;
    _offsetXController.text = '0';
    _offsetYController.text = '0';
    _scaleController.text = '1.00';
    _transformError = null;
  }

  VmService? get _service => serviceManager.service;

  IsolateRef? get _mainIsolate =>
      serviceManager.isolateManager.mainIsolate.value;

  Future<void> _refreshVm() async {
    setState(() {
      _vmError = null;
    });
    try {
      final service = _service;
      if (service == null) {
        throw StateError('No VM service connection.');
      }
      final vm = await service.getVM();
      if (!mounted) return;
      setState(() => _vm = vm);
    } catch (e) {
      if (!mounted) return;
      setState(() => _vmError = e.toString());
    }
  }

  Future<void> _inject() async {
    final service = _service;
    final iso = _mainIsolate;
    if (service == null || iso?.id == null) return;
    final isolateId = iso!.id!;
    setState(() {
      _busy = true;
      _injectionError = null;
    });
    try {
      final result = await Injector.inject(service, isolateId);
      if (!mounted) return;
      setState(() {
        _injection = result;
        _transforms = TransformController(
          service: service,
          isolateId: isolateId,
          libraryId: result.targetLibraryId,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _injectionError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hotReload() async {
    final service = _service;
    final iso = _mainIsolate;
    if (service == null || iso?.id == null) return;
    final isolateId = iso!.id!;
    setState(() => _busy = true);
    try {
      // Pass rootLibUri so the VM knows where to recompile from. Without
      // this, DDS often errors with "error while starting kernel task" on
      // apps started with `flutter run` (the frontend_server is owned by
      // the flutter tool, not DDS).
      final isolate = await service.getIsolate(isolateId);
      final rootLibUri = isolate.rootLib?.uri;

      final report = await service.reloadSources(
        isolateId,
        rootLibUri: rootLibUri,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatReloadReport(report)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final kernelFail =
          msg.contains('kernel') || msg.contains('compile');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kernelFail
                ? 'Hot reload from DevTools failed. With `flutter run`, '
                    'press `r` in the terminal — that uses the frontend '
                    'compiler this button can\'t reach.'
                : 'Hot reload error: $e',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// VM `reloadSources` returns success: false for the no-changes case as
  /// well as for real failures. Flutter's `r` command treats no-changes as a
  /// no-op; we do the same and only surface a real error when there's a
  /// specific reason in the report.
  String _formatReloadReport(ReloadReport report) {
    if (report.success ?? true) return 'Hot reload complete.';
    final json = report.json;
    final notices = json?['notices'];
    if (notices is List) {
      for (final n in notices) {
        if (n is Map) {
          final msg = n['message'];
          if (msg is String && msg.isNotEmpty) {
            return 'Hot reload: $msg';
          }
        }
      }
    }
    return 'Hot reload: no source changes.';
  }

  Future<void> _remove() async {
    final service = _service;
    final iso = _mainIsolate;
    final injection = _injection;
    if (service == null || iso?.id == null || injection == null) return;
    setState(() {
      _busy = true;
      _injectionError = null;
    });
    try {
      await Injector.remove(service, iso!.id!, injection.entryRef);
      if (!mounted) return;
      setState(() {
        _injection = null;
        _transforms = null;
        _lastImageName = null;
        _uploadError = null;
        _uploadProgress = 0;
        _cachedImageBytes = null;
        _resetTransformsToDefaults();
      });
      // Explicit Remove → clear persisted state too. Next mount starts fresh.
      PanelStorage.clearAll();
    } catch (e) {
      if (!mounted) return;
      // Even on error, clear the injection — the ref is likely stale.
      setState(() {
        _injectionError = e.toString();
        _injection = null;
        _transforms = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final service = _service;
    final iso = _mainIsolate;
    if (service == null || iso?.id == null) return;

    setState(() => _uploadError = null);

    PickedImage? picked;
    try {
      picked = await pickImage();
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _uploadError = 'File picker error: $e\n$st');
      return;
    }

    if (picked == null) return;

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _lastImageName = picked!.name;
    });
    try {
      await ImageUploader.upload(
        service,
        iso!.id!,
        picked.bytes,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      // Cache the bytes panel-side so we can re-upload after hot restart
      // without forcing the user to pick again. Also persist to localStorage
      // so the cache survives iframe remounts and Chrome refreshes.
      setState(() => _cachedImageBytes = picked!.bytes);
      PanelStorage.saveImage(picked.name, picked.bytes);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _uploadError = 'Upload error: $e\n$st');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _clearImage() async {
    final service = _service;
    final iso = _mainIsolate;
    if (service == null || iso?.id == null) return;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      await ImageUploader.clear(service, iso!.id!);
      if (!mounted) return;
      setState(() {
        _lastImageName = null;
        _uploadProgress = 0;
        _cachedImageBytes = null;
      });
      PanelStorage.clearImage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadError = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Transform handlers ─────────────────────────────────────────────────

  void _onOpacityChanged(double v) {
    setState(() {
      _opacity = v;
      _transformError = null;
    });
    _persistTransforms();
    _opacityQueue.submit(v);
  }

  void _onScaleChanged(double v) {
    setState(() {
      _scale = v;
      _transformError = null;
    });
    _persistTransforms();
    _scaleQueue.submit(v);
  }

  void _onOffsetChanged({double? dx, double? dy}) {
    setState(() {
      if (dx != null) _offsetX = dx;
      if (dy != null) _offsetY = dy;
      _transformError = null;
    });
    _persistTransforms();
    _offsetQueue.submit(Offset(_offsetX, _offsetY));
  }

  void _nudgeOffsetX(double delta) {
    _offsetXController.text = (_offsetX + delta).toStringAsFixed(0);
    _onOffsetChanged(dx: _offsetX + delta);
  }

  void _nudgeOffsetY(double delta) {
    _offsetYController.text = (_offsetY + delta).toStringAsFixed(0);
    _onOffsetChanged(dy: _offsetY + delta);
  }

  /// Multiplicative scale nudge — `factor` of 1.05 grows by 5%, `1/1.05`
  /// shrinks by 5%. Multiplicative keeps the perceptual step size
  /// consistent across the full scale range.
  void _nudgeScale(double factor) {
    final next = (_scale * factor).clamp(0.01, 100.0).toDouble();
    _scaleController.text = next.toStringAsFixed(2);
    _onScaleChanged(next);
  }

  Future<void> _onFlipHToggled() async {
    final t = _transforms;
    if (t == null) return;
    final next = !_flipH;
    setState(() {
      _flipH = next;
      _transformError = null;
    });
    _persistTransforms();
    try {
      await t.setFlipH(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _transformError = 'Flip H error: $e');
    }
  }

  Future<void> _onFlipVToggled() async {
    final t = _transforms;
    if (t == null) return;
    final next = !_flipV;
    setState(() {
      _flipV = next;
      _transformError = null;
    });
    _persistTransforms();
    try {
      await t.setFlipV(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _transformError = 'Flip V error: $e');
    }
  }

  Future<void> _onVisibleToggled(bool v) async {
    final t = _transforms;
    if (t == null) return;
    setState(() {
      _visible = v;
      _transformError = null;
    });
    _persistTransforms();
    try {
      await t.setVisible(v);
    } catch (e) {
      if (!mounted) return;
      setState(() => _transformError = 'Visible eval failed: $e');
    }
  }

  Future<void> _onFollowScrollToggled(bool v) async {
    final t = _transforms;
    if (t == null) return;
    setState(() {
      _followScroll = v;
      _transformError = null;
    });
    _persistTransforms();
    try {
      await t.setFollowScroll(v);
    } catch (e) {
      if (!mounted) return;
      setState(() => _transformError = 'Follow scroll eval failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfect Flutter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bolt),
            tooltip: 'Hot reload app',
            onPressed: _busy ? null : _hotReload,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh VM info',
            onPressed: _busy ? null : _refreshVm,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _injectionSection(),
            const SizedBox(height: 24),
            _imageSection(),
            const SizedBox(height: 24),
            _displaySection(),
            const SizedBox(height: 24),
            _transformsSection(),
            const SizedBox(height: 24),
            _vmSection(),
          ],
        ),
      ),
    );
  }

  Widget _injectionSection() {
    return ValueListenableBuilder<IsolateRef?>(
      valueListenable: serviceManager.isolateManager.mainIsolate,
      builder: (context, iso, _) {
        final isolateName = iso?.name ?? '(no isolate)';
        final isolateId = iso?.id ?? '';
        final injected = _injection != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overlay',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _kv('Isolate', '$isolateName  ·  $isolateId'),
            _kv(
              'State',
              injected
                  ? 'injected (entry ${_injection!.entryRef})'
                  : 'not injected',
            ),
            if (_injection != null)
              _kv('Target lib', _injection!.targetLibraryUri),
            if (_injectionError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  _injectionError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.layers),
                  label: const Text('Inject overlay'),
                  onPressed:
                      (_busy || injected || iso?.id == null) ? null : _inject,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.layers_clear),
                  label: const Text('Remove overlay'),
                  onPressed: (_busy || !injected) ? null : _remove,
                ),
                if (_cachedImageBytes != null && !injected) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore'),
                    onPressed:
                        (_busy || _restoring) ? null : _restoreAfterRestart,
                  ),
                ],
                const SizedBox(width: 12),
                if (_busy || _restoring)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Inject creates a single OverlayEntry that listens for an image. '
              'Until one is uploaded, a magenta placeholder renders.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Widget _imageSection() {
    final injected = _injection != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Image', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _kv('Current', _lastImageName ?? '(none tracked — placeholder or pre-refresh image)'),
        if (_uploadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(
              _uploadError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('Pick image'),
              onPressed: (_uploading || !injected) ? null : _pickAndUploadImage,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.clear),
              label: const Text('Clear image'),
              onPressed: (_uploading || !injected) ? null : _clearImage,
            ),
          ],
        ),
        if (_uploading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _uploadProgress),
          const SizedBox(height: 4),
          Text(
            'Uploading ${(_uploadProgress * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (!injected) ...[
          const SizedBox(height: 8),
          Text(
            'Inject the overlay first, then pick an image.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _displaySection() {
    final enabled = _transforms != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Display', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Show overlay'),
          subtitle: const Text(
            'Hide without removing the entry — image and transforms are preserved.',
          ),
          value: _visible,
          onChanged: enabled ? _onVisibleToggled : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Follow scroll'),
          subtitle: const Text(
            'Overlay translates with the app\'s largest vertical scrollable. '
            'Toggle off then on after navigating to attach to the new screen.',
          ),
          value: _followScroll,
          onChanged: enabled ? _onFollowScrollToggled : null,
        ),
        if (!enabled) ...[
          const SizedBox(height: 4),
          Text(
            'Inject the overlay first to enable display toggles.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _transformsSection() {
    final enabled = _transforms != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transforms', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        // Opacity
        Row(
          children: [
            const SizedBox(
              width: 70,
              child: Text('Opacity', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Slider(
                value: _opacity,
                onChanged: enabled ? _onOpacityChanged : null,
                onChangeEnd: enabled ? _onOpacityChanged : null,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '${(_opacity * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Scale — multiplicative ±5% per click, direct entry via text field.
        _numericRow(
          label: 'Scale',
          controller: _scaleController,
          onSubmitted: (s) {
            final v = double.tryParse(s);
            if (v == null) return;
            final clamped = v.clamp(0.01, 100.0).toDouble();
            _scaleController.text = clamped.toStringAsFixed(2);
            _onScaleChanged(clamped);
          },
          onMinus: enabled ? () => _nudgeScale(1 / 1.05) : null,
          onPlus: enabled ? () => _nudgeScale(1.05) : null,
          enabled: enabled,
          suffix: '×',
          minusTooltip: '-5%',
          plusTooltip: '+5%',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 4),
        // Offset X
        _numericRow(
          label: 'Offset X',
          controller: _offsetXController,
          onSubmitted: (s) {
            final v = double.tryParse(s);
            if (v != null) _onOffsetChanged(dx: v);
          },
          onMinus: enabled ? () => _nudgeOffsetX(-1) : null,
          onPlus: enabled ? () => _nudgeOffsetX(1) : null,
          enabled: enabled,
        ),
        const SizedBox(height: 4),
        _numericRow(
          label: 'Offset Y',
          controller: _offsetYController,
          onSubmitted: (s) {
            final v = double.tryParse(s);
            if (v != null) _onOffsetChanged(dy: v);
          },
          onMinus: enabled ? () => _nudgeOffsetY(-1) : null,
          onPlus: enabled ? () => _nudgeOffsetY(1) : null,
          enabled: enabled,
        ),
        const SizedBox(height: 12),
        // Flips
        Row(
          children: [
            const SizedBox(
              width: 70,
              child: Text('Flip', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            FilterChip(
              avatar: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Horizontal'),
              selected: _flipH,
              onSelected: enabled ? (_) => _onFlipHToggled() : null,
            ),
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.swap_vert, size: 18),
              label: const Text('Vertical'),
              selected: _flipV,
              onSelected: enabled ? (_) => _onFlipVToggled() : null,
            ),
          ],
        ),
        if (_transformError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              _transformError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!enabled) ...[
          const SizedBox(height: 8),
          Text(
            'Inject the overlay first to enable transforms.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _numericRow({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onSubmitted,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
    required bool enabled,
    String suffix = 'px',
    String minusTooltip = '-1 px',
    String plusTooltip = '+1 px',
    TextInputType keyboardType =
        const TextInputType.numberWithOptions(signed: true, decimal: true),
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: onMinus,
          tooltip: minusTooltip,
        ),
        SizedBox(
          width: 80,
          child: TextField(
            controller: controller,
            enabled: enabled,
            textAlign: TextAlign.center,
            keyboardType: keyboardType,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: onSubmitted,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: onPlus,
          tooltip: plusTooltip,
        ),
        const SizedBox(width: 8),
        Text(suffix, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _vmSection() {
    if (_vmError != null) {
      return SelectableText(
        'VM error: $_vmError',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    final vm = _vm;
    if (vm == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isolates = vm.isolates ?? const <IsolateRef>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('VM', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _kv('Name', vm.name ?? 'unknown'),
        _kv('Version', vm.version ?? 'unknown'),
        _kv('Host CPU', vm.hostCPU ?? 'unknown'),
        _kv(
          'Architecture',
          vm.architectureBits == null
              ? 'unknown'
              : '${vm.architectureBits}-bit',
        ),
        _kv('PID', '${vm.pid ?? 'unknown'}'),
        const SizedBox(height: 12),
        Text(
          'Isolates (${isolates.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final iso in isolates)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: SelectableText('· ${iso.name ?? '(unnamed)'}  ${iso.id}'),
          ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

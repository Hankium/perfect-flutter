import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart';

import 'injector.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshVm();
    serviceManager.isolateManager.mainIsolate.addListener(_onIsolateChanged);
  }

  @override
  void dispose() {
    serviceManager.isolateManager.mainIsolate.removeListener(_onIsolateChanged);
    super.dispose();
  }

  void _onIsolateChanged() {
    // A new main isolate means any previous injection ref is invalid.
    if (mounted) {
      setState(() {
        _injection = null;
        _injectionError = null;
      });
      _refreshVm();
    }
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
    setState(() {
      _busy = true;
      _injectionError = null;
    });
    try {
      final result = await Injector.inject(service, iso!.id!);
      if (!mounted) return;
      setState(() => _injection = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _injectionError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      setState(() => _injection = null);
    } catch (e) {
      if (!mounted) return;
      // Even on error, clear the injection — the ref is likely stale.
      setState(() {
        _injectionError = e.toString();
        _injection = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfect Flutter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
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
                const SizedBox(width: 12),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sprint 2 stub: inserts a semi-transparent magenta rectangle. '
              'Real image upload + transforms come in S3/S4.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
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

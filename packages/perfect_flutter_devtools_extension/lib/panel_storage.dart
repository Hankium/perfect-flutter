// Panel-side persistence via browser `localStorage`. Survives DevTools
// extension iframe remounts (which wipe Dart memory), Chrome refreshes,
// and browser restarts.
//
// Why not the app's isolate? The isolate is what restarts on hot restart —
// it's exactly the state we lose. We need a store that lives in the
// browser process, outside the device-app/DDS boundary.

import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class PanelStorage {
  PanelStorage._();

  static const String _imageBytesKey = 'perfect_flutter.image.bytes';
  static const String _imageNameKey = 'perfect_flutter.image.name';
  static const String _transformsKey = 'perfect_flutter.transforms';

  /// Persists the design image. Base64 inflates by 4/3, so a 5 MB PNG
  /// becomes ~6.7 MB stored — within localStorage's typical 5–10 MB
  /// per-origin quota. Larger images will silently fail to persist and
  /// fall back to in-memory only.
  static void saveImage(String name, Uint8List bytes) {
    try {
      web.window.localStorage.setItem(_imageBytesKey, base64Encode(bytes));
      web.window.localStorage.setItem(_imageNameKey, name);
    } catch (_) {
      // QuotaExceeded — in-memory cache continues to work for this session.
    }
  }

  static ({String name, Uint8List bytes})? loadImage() {
    try {
      final b64 = web.window.localStorage.getItem(_imageBytesKey);
      final name = web.window.localStorage.getItem(_imageNameKey);
      if (b64 == null || name == null) return null;
      return (name: name, bytes: base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  static void clearImage() {
    try {
      web.window.localStorage.removeItem(_imageBytesKey);
      web.window.localStorage.removeItem(_imageNameKey);
    } catch (_) {}
  }

  static void saveTransforms({
    required double opacity,
    required double scale,
    required double offsetX,
    required double offsetY,
    required bool flipH,
    required bool flipV,
    required bool visible,
    required bool followScroll,
  }) {
    try {
      web.window.localStorage.setItem(
        _transformsKey,
        jsonEncode({
          'opacity': opacity,
          'scale': scale,
          'offsetX': offsetX,
          'offsetY': offsetY,
          'flipH': flipH,
          'flipV': flipV,
          'visible': visible,
          'followScroll': followScroll,
        }),
      );
    } catch (_) {}
  }

  static Map<String, dynamic>? loadTransforms() {
    try {
      final raw = web.window.localStorage.getItem(_transformsKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  static void clearTransforms() {
    try {
      web.window.localStorage.removeItem(_transformsKey);
    } catch (_) {}
  }

  static void clearAll() {
    clearImage();
    clearTransforms();
  }
}

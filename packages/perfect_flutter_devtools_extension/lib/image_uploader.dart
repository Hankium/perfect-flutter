// Base64-chunked image upload from the panel into the running app.
//
// Workflow:
//   1. Clear any stale buffer with PerfectFlutter.clearImage().
//   2. base64-encode the raw bytes once on the panel side.
//   3. Send the base64 string in ~256 KB chunks via PerfectFlutter.appendChunk.
//   4. Final call: PerfectFlutter.commitImage() decodes and publishes to the
//      overlay's ValueNotifier.
//
// Base64 alphabet (A-Za-z0-9+/=) contains no quote characters, so the chunks
// can be inlined directly into single-quoted Dart string literals — no
// escaping required.

import 'dart:convert';
import 'dart:typed_data';

import 'package:vm_service/vm_service.dart';

import 'injector.dart';

class ImageUploader {
  /// Base64 characters per `appendChunk` eval call. The VM service `evaluate`
  /// endpoint has an undocumented payload ceiling (anecdotally ~1 MB); we
  /// stay well below it to keep individual round-trips fast on slow ADB
  /// connections too.
  static const int _chunkSizeChars = 256 * 1024;

  /// Uploads [rawBytes] to the running app and commits it as the overlay
  /// image. Reports progress in [0.0, 1.0] including the final commit step.
  static Future<void> upload(
    VmService service,
    String isolateId,
    Uint8List rawBytes, {
    void Function(double progress)? onProgress,
  }) async {
    final lib = await Injector.pickTargetLibrary(service, isolateId);
    final libId = lib.id!;

    final base64Str = base64Encode(rawBytes);
    final totalChunks = (base64Str.length / _chunkSizeChars).ceil();
    final totalSteps = totalChunks + 2; // clear + chunks + commit

    var step = 0;
    void tick() {
      step++;
      onProgress?.call(step / totalSteps);
    }

    await service.evaluate(isolateId, libId, 'PerfectFlutter.clearImage()');
    tick();

    for (var i = 0; i < totalChunks; i++) {
      final start = i * _chunkSizeChars;
      final end = (start + _chunkSizeChars) > base64Str.length
          ? base64Str.length
          : start + _chunkSizeChars;
      final chunk = base64Str.substring(start, end);
      await service.evaluate(
        isolateId,
        libId,
        "PerfectFlutter.appendChunk('$chunk')",
      );
      tick();
    }

    await service.evaluate(isolateId, libId, 'PerfectFlutter.commitImage()');
    tick();
  }

  /// Clears the overlay image, returning to the placeholder.
  static Future<void> clear(VmService service, String isolateId) async {
    final lib = await Injector.pickTargetLibrary(service, isolateId);
    await service.evaluate(
      isolateId,
      lib.id!,
      'PerfectFlutter.clearImage()',
    );
  }
}

// Native HTML file-input picker, used instead of `file_picker`.
//
// Why not file_picker? Its web registrar throws an uncaught error inside the
// DevTools extension's iframe context — the error escapes Dart's async error
// boundaries and shows only as an obfuscated JS stack. A direct
// `<input type="file">` via `package:web` sidesteps the plugin entirely.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class PickedImage {
  const PickedImage({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// Opens a native browser file picker scoped to image MIME types. Resolves
/// to the picked file's bytes, or null if the user cancels. May throw if
/// the browser's `FileReader` fails to read the file.
Future<PickedImage?> pickImage() {
  final completer = Completer<PickedImage?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = 'image/*';

  void completeNullOnce() {
    if (!completer.isCompleted) completer.complete(null);
  }

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completeNullOnce();
      return;
    }
    final file = files.item(0);
    if (file == null) {
      completeNullOnce();
      return;
    }
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      if (completer.isCompleted) return;
      final result = reader.result;
      if (result == null) {
        completer.complete(null);
        return;
      }
      final bytes = (result as JSArrayBuffer).toDart.asUint8List();
      completer.complete(PickedImage(name: file.name, bytes: bytes));
    }).toJS;
    reader.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('FileReader error: ${reader.error?.message ?? "unknown"}'),
        );
      }
    }).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;

  // `cancel` fires when the user dismisses the picker without choosing a
  // file (Chrome 113+, Firefox 91+, Safari 16.4+). Without this, a cancel
  // would leave the Future pending forever.
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      completeNullOnce();
    }).toJS,
  );

  input.click();
  return completer.future;
}

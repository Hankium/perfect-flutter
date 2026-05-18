# perfect_flutter_example

Demo app for the [`perfect_flutter`](https://pub.dev/packages/perfect_flutter)
package. A simple `MaterialApp` with cards, lists, and an expandable FAQ —
designed to exercise the overlay against realistic UI surfaces.

## Run it

```bash
flutter pub get
flutter run
```

Then open DevTools (the URL is printed by `flutter run`) and switch to the
**Perfect Flutter** tab. Click **Inject**, upload a design image, and adjust.

## What this app shows

The only `perfect_flutter`-related code is two lines in `lib/main.dart`:

```dart
// ignore: unused_import, depend_on_referenced_packages
import 'package:perfect_flutter/perfect_flutter.dart';
```

That's it. No widget wrapping, no `runApp` changes, no debug branches.

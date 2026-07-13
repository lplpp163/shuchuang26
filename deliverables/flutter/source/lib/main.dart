import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app.dart';
import 'services/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the web semantics tree available on touch-only devices as well.
  // This makes the child flow usable with screen readers and switch access;
  // Flutter's hidden desktop-only activation target is otherwise unreachable
  // under some mobile browser emulations.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  final store = await AppStore.load();
  runApp(HomeTongueApp(store: store));
}

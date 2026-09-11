import 'package:flutter/material.dart';

import 'app/hoomy_app.dart';
import 'services/startup_logger.dart';

Future<void> main() async {
  StartupLogger.start();
  WidgetsFlutterBinding.ensureInitialized();
  StartupLogger.mark('Flutter binding ready');
  runApp(const HoomyApp());
  StartupLogger.mark('runApp called');
}

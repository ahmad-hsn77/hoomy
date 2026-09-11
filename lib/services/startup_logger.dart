import 'package:flutter/foundation.dart';

class StartupLogger {
  StartupLogger._();

  static final Stopwatch _watch = Stopwatch();

  static void start() {
    if (!_watch.isRunning) _watch.start();
    mark('App process start');
  }

  static void mark(String stage) {
    if (!_watch.isRunning) _watch.start();
    debugPrint('[startup +${_watch.elapsedMilliseconds}ms] $stage');
  }
}

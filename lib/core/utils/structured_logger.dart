abstract class StructuredLogger {
  void log({
    required String event,
    required Map<String, Object?> fields,
  });
}

class ConsoleStructuredLogger implements StructuredLogger {
  @override
  void log({
    required String event,
    required Map<String, Object?> fields,
  }) {
    final payload = <String, Object?>{
      'event': event,
      ...fields,
    };
    // ignore: avoid_print
    print(payload);
  }
}

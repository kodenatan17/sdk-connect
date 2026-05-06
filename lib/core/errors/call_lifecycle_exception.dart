class CallLifecycleException implements Exception {
  CallLifecycleException(this.message);

  final String message;

  @override
  String toString() => 'CallLifecycleException: $message';
}

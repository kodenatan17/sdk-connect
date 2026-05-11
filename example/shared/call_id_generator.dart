import 'dart:math';

/// Generates a cryptographically random call identifier.
///
/// Format: `call_<32 hex chars>`
String generateCallId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'call_$hex';
}

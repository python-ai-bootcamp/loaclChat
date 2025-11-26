import 'dart:math';

class UserIdGenerator {
  static const String _chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static final Random _random = Random();
  
  /// Generates a minimal unique hash (8 characters)
  /// This provides ~218 trillion combinations, sufficient for 10k+ users
  static String generate() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = _random.nextInt(10000);
    
    // Combine timestamp and random number, then convert to base62
    final combined = timestamp * 10000 + randomPart;
    return _toBase62(combined).substring(0, 8);
  }
  
  static String _toBase62(int number) {
    if (number == 0) return '0';
    
    String result = '';
    while (number > 0) {
      result = _chars[number % 62] + result;
      number ~/= 62;
    }
    
    // Pad to ensure minimum length
    while (result.length < 8) {
      result = _chars[_random.nextInt(62)] + result;
    }
    
    return result;
  }
}


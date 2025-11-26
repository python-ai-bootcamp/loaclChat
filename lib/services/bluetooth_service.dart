import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/discovered_user.dart';

// Conditional import - only import flutter_blue_plus on non-web platforms
import 'bluetooth_service_stub.dart'
    if (dart.library.io) 'bluetooth_service_impl.dart' as impl;

abstract class BluetoothServiceBase {
  Stream<Map<String, DiscoveredUser>> get discoveredUsersStream;
  Map<String, DiscoveredUser> get discoveredUsers;
  Future<void> initialize();
  Future<bool> checkPermissions();
  Future<void> startAdvertising(String userId, String nickname);
  Future<void> stopAdvertising();
  Future<void> startScanning();
  Future<void> stopScanning();
  void dispose();
}

class BluetoothService {
  static BluetoothServiceBase create() {
    return impl.createBluetoothService();
  }
}

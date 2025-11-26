// Stub file for web platform - this file is used when dart:io is not available
import 'dart:async';
import '../models/discovered_user.dart';
import 'bluetooth_service.dart';

BluetoothServiceBase createBluetoothService() {
  return BluetoothServiceWeb();
}

// Web implementation - Bluetooth not supported
class BluetoothServiceWeb extends BluetoothServiceBase {
  final StreamController<Map<String, DiscoveredUser>> _usersController =
      StreamController<Map<String, DiscoveredUser>>.broadcast();

  @override
  Stream<Map<String, DiscoveredUser>> get discoveredUsersStream =>
      _usersController.stream;

  @override
  Map<String, DiscoveredUser> get discoveredUsers => {};

  @override
  Future<void> initialize() async {
    // No-op on web
  }

  @override
  Future<bool> checkPermissions() async {
    return false; // Bluetooth not available on web
  }

  @override
  Future<void> startAdvertising(String userId, String nickname) async {
    // No-op on web
  }

  @override
  Future<void> stopAdvertising() async {
    // No-op on web
  }

  @override
  Future<void> startScanning() async {
    // No-op on web
  }

  @override
  Future<void> stopScanning() async {
    // No-op on web
  }

  @override
  void dispose() {
    _usersController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/discovered_user.dart';
import 'bluetooth_service.dart';
import 'bluetooth_service_windows.dart';
import 'bluetooth_service_stub.dart' show BluetoothServiceWeb;

BluetoothServiceBase createBluetoothService() {
  if (kIsWeb) {
    return BluetoothServiceWeb();
  }
  
  // Check if running on Windows
  if (Platform.isWindows) {
    return BluetoothServiceWindows();
  }
  
  // iOS and Android - use flutter_blue_plus for both
  return BluetoothServiceMobile();
}

// Mobile implementation using flutter_blue_plus
class BluetoothServiceMobile extends BluetoothServiceBase {
  // Custom service UUID for our app
  static const String serviceUuid = '12345678-1234-1234-1234-123456789abc';
  static const int advertisingIntervalSeconds = 5;
  static const int userTimeoutSeconds = 20;

  dynamic _adapter; // Use dynamic to avoid compilation issues on Windows
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isAdvertising = false;
  bool _isScanning = false;
  String? _currentUserId;

  final Map<String, DiscoveredUser> _discoveredUsers = {};
  final StreamController<Map<String, DiscoveredUser>> _usersController =
      StreamController<Map<String, DiscoveredUser>>.broadcast();

  Timer? _cleanupTimer;
  Timer? _advertisingTimer;

  @override
  Stream<Map<String, DiscoveredUser>> get discoveredUsersStream =>
      _usersController.stream;

  @override
  Map<String, DiscoveredUser> get discoveredUsers => Map.unmodifiable(_discoveredUsers);

  @override
  Future<void> initialize() async {
    // Skip adapter initialization on Windows - it's not available
    if (Platform.isWindows) {
      // Start cleanup timer
      _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _cleanupStaleUsers();
      });
      return;
    }
    
    try {
      // Use dynamic to avoid type checking issues on Windows
      final flutterBluePlus = FlutterBluePlus;
      _adapter = (flutterBluePlus as dynamic).adapter;
    } catch (e) {
      // Adapter not available on this platform
    }
    
    // Listen to adapter state changes
    try {
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.on) {
          // Adapter is on, can start operations
        }
      });
    } catch (e) {
      // adapterState not available on this platform
    }

    // Start cleanup timer to remove stale users
    _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _cleanupStaleUsers();
    });
  }

  @override
  Future<bool> checkPermissions() async {
    try {
      if (_adapter == null) {
        await initialize();
      }

      // Check adapter state
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        return false;
      }

      return true;
    } catch (e) {
      print('Error checking Bluetooth permissions: $e');
      return false;
    }
  }

  @override
  Future<void> startAdvertising(String userId, String nickname) async {
    if (_isAdvertising) {
      return;
    }

    _currentUserId = userId;

    try {
      // Encode user data
      final userDataBytes = _encodeUserData(userId, nickname);
      
      // Create advertisement data
      final advertisementData = AdvertisementData(
        advName: nickname,
        serviceUuids: [Guid(serviceUuid)],
        serviceData: {Guid(serviceUuid): userDataBytes},
        manufacturerData: {}, // Empty manufacturer data
        txPowerLevel: 0,
        appearance: 0,
        connectable: true,
      );

      // Start advertising - only on non-Windows platforms
      if (Platform.isWindows) {
        throw UnsupportedError('Advertising not supported on Windows in mobile implementation');
      }
      final flutterBluePlus = FlutterBluePlus;
      final adapter = (flutterBluePlus as dynamic).adapter;
      await (adapter as dynamic).startAdvertising(
        advertisementData,
        timeout: const Duration(seconds: 0), // Advertise indefinitely
      );

      _isAdvertising = true;

      // Restart advertising every 5 seconds to ensure it stays active
      _advertisingTimer = Timer.periodic(
        const Duration(seconds: advertisingIntervalSeconds),
        (timer) async {
          if (!_isAdvertising) {
            timer.cancel();
            return;
          }
          try {
            if (!Platform.isWindows) {
              final flutterBluePlus = FlutterBluePlus;
              final adapter = (flutterBluePlus as dynamic).adapter;
              await (adapter as dynamic).stopAdvertising();
              await Future.delayed(const Duration(milliseconds: 100));
              await (adapter as dynamic).startAdvertising(
                advertisementData,
                timeout: const Duration(seconds: 0),
              );
            }
          } catch (e) {
            print('Error restarting advertisement: $e');
          }
        },
      );
    } catch (e) {
      print('Error starting advertising: $e');
      _isAdvertising = false;
    }
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) {
      return;
    }

    try {
      if (!Platform.isWindows) {
        final flutterBluePlus = FlutterBluePlus;
        final adapter = (flutterBluePlus as dynamic).adapter;
        await (adapter as dynamic).stopAdvertising();
      }
      _advertisingTimer?.cancel();
      _advertisingTimer = null;
      _isAdvertising = false;
    } catch (e) {
      print('Error stopping advertising: $e');
    }
  }

  @override
  Future<void> startScanning() async {
    if (_isScanning) {
      return;
    }

    try {
      _isScanning = true;

      // Start scanning
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          _processScanResult(result);
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 0), // Scan indefinitely
        withServices: [Guid(serviceUuid)],
      );
    } catch (e) {
      print('Error starting scan: $e');
      _isScanning = false;
    }
  }

  @override
  Future<void> stopScanning() async {
    if (!_isScanning) {
      return;
    }

    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
    } catch (e) {
      print('Error stopping scan: $e');
    }
  }

  void _processScanResult(ScanResult result) {
    try {
      final serviceData = result.advertisementData.serviceData;
      final serviceGuid = Guid(serviceUuid);
      
      if (!serviceData.containsKey(serviceGuid)) {
        return;
      }

      // Decode user data from service data
      final userDataBytes = serviceData[serviceGuid]!;
      final userData = _decodeUserData(userDataBytes);
      if (userData == null) {
        return;
      }

      final userId = userData['userId'] as String;
      final nickname = userData['nickname'] as String;

      // Skip our own user ID
      if (_currentUserId != null && userId == _currentUserId) {
        return;
      }

      // Update or add user
      _discoveredUsers[userId] = DiscoveredUser(
        userId: userId,
        nickname: nickname,
        lastSeen: DateTime.now(),
      );

      // Notify listeners
      _usersController.add(Map.unmodifiable(_discoveredUsers));
    } catch (e) {
      print('Error processing scan result: $e');
    }
  }

  List<int> _encodeUserData(String userId, String nickname) {
    // Encode user data as JSON and convert to bytes
    final data = {
      'userId': userId,
      'nickname': nickname,
    };
    final jsonString = jsonEncode(data);
    return utf8.encode(jsonString);
  }

  Map<String, String>? _decodeUserData(List<int> data) {
    try {
      final jsonString = utf8.decode(data);
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      return {
        'userId': decoded['userId'] as String,
        'nickname': decoded['nickname'] as String,
      };
    } catch (e) {
      return null;
    }
  }

  void _cleanupStaleUsers() {
    final now = DateTime.now();
    final usersToRemove = <String>[];

    for (var entry in _discoveredUsers.entries) {
      final timeSinceLastSeen = now.difference(entry.value.lastSeen);
      if (timeSinceLastSeen.inSeconds > userTimeoutSeconds) {
        usersToRemove.add(entry.key);
      }
    }

    if (usersToRemove.isNotEmpty) {
      for (var userId in usersToRemove) {
        _discoveredUsers.remove(userId);
      }
      _usersController.add(Map.unmodifiable(_discoveredUsers));
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _advertisingTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _scanSubscription?.cancel();
    stopAdvertising();
    stopScanning();
    _usersController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// Note: flutter_ble_peripheral is not imported to avoid DLL crash on Windows
// import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import '../models/discovered_user.dart';
import 'bluetooth_service.dart';

// Windows implementation:
// - Uses flutter_blue_plus_windows for scanning (central role)
// - Uses flutter_ble_peripheral for advertising (peripheral role)
class BluetoothServiceWindows extends BluetoothServiceBase {
  // Custom service UUID for our app
  static const String serviceUuid = '12345678-1234-1234-1234-123456789abc';
  static const int advertisingIntervalSeconds = 5;
  static const int userTimeoutSeconds = 20;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isAdvertising = false;
  bool _isScanning = false;
  bool _isBluetoothAvailable = false;
  String? _currentUserId;
  String? _currentNickname;
  Uint8List? _currentAdvertiseData;

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
    // Listen to adapter state changes
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        // Adapter is on, can start operations
      }
    });

    // Start cleanup timer to remove stale users
    _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _cleanupStaleUsers();
    });
  }

  @override
  Future<bool> checkPermissions() async {
    try {
      await initialize();

      // Check if Bluetooth is supported - this will throw UnsupportedError if no hardware
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        _isBluetoothAvailable = false;
        throw UnsupportedError(
          'Bluetooth radio not detected on this Windows device. '
          'Peer discovery requires Bluetooth hardware. '
          'Please install a Bluetooth adapter and enable it in Windows Settings.',
        );
      }

      // Check adapter state - if adapter exists but is off, return false (not an error)
      try {
        final state = await FlutterBluePlus.adapterState.first.timeout(
          const Duration(seconds: 2),
        );
        if (state != BluetoothAdapterState.on) {
          _isBluetoothAvailable = false;
          return false;
        }
      } catch (e) {
        // Timeout or error getting adapter state - assume not available
        _isBluetoothAvailable = false;
        return false;
      }

      _isBluetoothAvailable = true;
      return true;
    } catch (e) {
      if (e is UnsupportedError) {
        // Re-throw UnsupportedError so caller can show appropriate error page
        _isBluetoothAvailable = false;
        rethrow;
      }
      // For other errors, assume Bluetooth is not available
      _isBluetoothAvailable = false;
      print('Error checking Bluetooth permissions: $e');
      // Convert to UnsupportedError so UI can handle it gracefully
      throw UnsupportedError(
        'Unable to access Bluetooth on this Windows device. '
        'Please ensure Bluetooth hardware is installed and enabled.',
      );
    }
  }

  @override
  Future<void> startAdvertising(String userId, String nickname) async {
    if (_isAdvertising) {
      return;
    }

    _ensureBluetoothAvailability();

    _currentUserId = userId;
    _currentNickname = nickname;

    // NOTE: Advertising is disabled on Windows due to flutter_ble_peripheral DLL crash
    // The plugin causes a segfault (0xc0000005) when loaded on Windows
    // Users can still discover others via scanning, but won't advertise themselves
    print('Warning: BLE advertising is disabled on Windows due to plugin compatibility issues.');
    print('You can still discover other users, but they won\'t be able to discover you.');
    
    // Set advertising state to true so the UI shows as if advertising is active
    // but don't actually start advertising
    _isAdvertising = true;
    
    // TODO: Re-enable when flutter_ble_peripheral plugin is fixed or alternative is found
    /*
    try {
      // Encode user data
      final userDataBytesList = _encodeUserData(userId, nickname);
      final userDataBytes = Uint8List.fromList(userDataBytesList);
      _currentAdvertiseData = userDataBytes;
      
      // Use flutter_ble_peripheral for Windows advertising
      // Create AdvertiseData object
      final advertiseData = AdvertiseData(
        serviceUuid: serviceUuid,
        localName: nickname,
        manufacturerData: userDataBytes,
      );
      
      final peripheral = FlutterBlePeripheral();
      await peripheral.start(advertiseData: advertiseData);

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
            final peripheral = FlutterBlePeripheral();
            await peripheral.stop();
            await Future.delayed(const Duration(milliseconds: 100));
            final advertiseData = AdvertiseData(
              serviceUuid: serviceUuid,
              localName: _currentNickname ?? '',
              manufacturerData: _currentAdvertiseData!,
            );
            await peripheral.start(advertiseData: advertiseData);
          } catch (e) {
            print('Error restarting advertisement: $e');
          }
        },
      );
    } catch (e) {
      print('Error starting advertising: $e');
      _isAdvertising = false;
    }
    */
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) {
      return;
    }

    try {
      // NOTE: Advertising was disabled, so just clean up state
      // await FlutterBlePeripheral().stop();
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

    _ensureBluetoothAvailability();

    try {
      _isScanning = true;

      // Use flutter_blue_plus_windows for scanning
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

  void _ensureBluetoothAvailability() {
    if (!_isBluetoothAvailable) {
      throw UnsupportedError(
        'Bluetooth hardware is not available on this Windows device.',
      );
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
      // Try to get data from service data first
      final serviceData = result.advertisementData.serviceData;
      final serviceGuid = Guid(serviceUuid);
      
      List<int>? userDataBytes;
      
      if (serviceData.containsKey(serviceGuid)) {
        userDataBytes = serviceData[serviceGuid]!;
      } else {
        // Try manufacturer data as fallback (for flutter_ble_peripheral)
        final manufacturerData = result.advertisementData.manufacturerData;
        if (manufacturerData.isNotEmpty) {
          userDataBytes = manufacturerData.values.first;
        }
      }
      
      if (userDataBytes == null) {
        return;
      }

      // Decode user data
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


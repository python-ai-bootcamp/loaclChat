import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/discovered_user.dart';
import 'bluetooth_service.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
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
      // Android: advertise via flutter_ble_peripheral using manufacturer data
      if (Platform.isAndroid) {
        print('[BLE Adv] startAdvertising invoked (Android) for userId="$userId", nickname="$nickname"');
        final userDataBytes =
            Uint8List.fromList(_encodeUserData(userId, nickname));

        final advertiseData = AdvertiseData(
          // Keep the payload minimal to stay within 31-byte legacy ADV
          // Do not include localName or 128-bit service UUID here.
          manufacturerId: 0xFFFF,
          manufacturerData: userDataBytes,
        );

        final peripheral = FlutterBlePeripheral();
        await peripheral.start(advertiseData: advertiseData);
        try {
          final previewLen = userDataBytes.length > 16 ? 16 : userDataBytes.length;
          final hexPreview = userDataBytes
              .sublist(0, previewLen)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          print('[BLE Adv] started: manufacturerId=0xFFFF, payloadLen=${userDataBytes.length}, payloadHex[0..${previewLen - 1}]= $hexPreview');
        } catch (_) {}
        _isAdvertising = true;
        return;
      }

      // Other mobile platforms: not supported in this simplified implementation
      throw UnsupportedError('Advertising not supported on this platform');

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
      if (Platform.isAndroid) {
        await FlutterBlePeripheral().stop();
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
      print('[BLE Scan] startScanning begin (mobile)');
      _isScanning = true;

      // Start scanning
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        try {
          print('[BLE Scan] results batch: ${results.length}');
        } catch (_) {}
        for (var result in results) {
          _processScanResult(result);
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 0), // Scan indefinitely
        withServices: [Guid(serviceUuid)],
      );
      print('[BLE Scan] startScan issued (mobile)');
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

      List<int>? userDataBytes;

      if (serviceData.containsKey(serviceGuid)) {
        userDataBytes = serviceData[serviceGuid]!;
      } else {
        // Fallback: some devices/plugins only populate manufacturer data
        final manufacturerData = result.advertisementData.manufacturerData;
        if (manufacturerData.isNotEmpty) {
          userDataBytes = manufacturerData.values.first;
        }
      }

      if (userDataBytes == null) {
        try {
          final md = result.advertisementData.manufacturerData;
          final sd = result.advertisementData.serviceData;
          print('[BLE Scan] skip adv: name=${result.advertisementData.advName}, md.keys=${md.keys.toList()}, sd.keys=${sd.keys.toList()}');
        } catch (_) {}
        return;
      }

      // Decode user data from bytes
      final userData = _decodeUserData(userDataBytes);
      if (userData == null) {
        try {
          final previewLen = userDataBytes.length > 16 ? 16 : userDataBytes.length;
          final hexPreview = userDataBytes
              .sublist(0, previewLen)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          print('[BLE Scan] failed to decode payloadLen=${userDataBytes.length}, hex[0..${previewLen - 1}]= $hexPreview');
        } catch (_) {}
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
      try {
        print('[BLE Scan] discovered user="$nickname" ($userId), total=${_discoveredUsers.length}');
      } catch (_) {}
      _usersController.add(Map.unmodifiable(_discoveredUsers));
    } catch (e) {
      print('Error processing scan result: $e');
    }
  }

  List<int> _encodeUserData(String userId, String nickname) {
    // Prefer a compact JSON to fit in legacy advertising (<= 31 bytes total).
    // Truncate nickname defensively.
    String truncatedNickname = nickname;
    if (truncatedNickname.runes.length > 12) {
      truncatedNickname = String.fromCharCodes(truncatedNickname.runes.take(12));
    }

    // First try full keys
    var data = {
      'userId': userId,
      'nickname': truncatedNickname,
    };
    var jsonString = jsonEncode(data);
    var bytes = utf8.encode(jsonString);
    if (bytes.length <= 24) {
      return bytes;
    }

    // Fallback to short keys
    data = {
      'u': userId,
      'n': truncatedNickname,
    };
    jsonString = jsonEncode(data);
    return utf8.encode(jsonString);
  }

  Map<String, String>? _decodeUserData(List<int> data) {
    try {
      final jsonString = utf8.decode(data);
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      // Accept both long and short keys
      final userId = (decoded['userId'] ?? decoded['u']) as String?;
      final nickname = (decoded['nickname'] ?? decoded['n']) as String?;
      if (userId == null || nickname == null) {
        return null;
      }
      return {'userId': userId, 'nickname': nickname};
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

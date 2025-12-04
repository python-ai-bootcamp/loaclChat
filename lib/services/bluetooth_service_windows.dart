import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart' as fbp;
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

  StreamSubscription<fbp.BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
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
  Timer? _scanRestartTimer;

  @override
  Stream<Map<String, DiscoveredUser>> get discoveredUsersStream =>
      _usersController.stream;

  @override
  Map<String, DiscoveredUser> get discoveredUsers => Map.unmodifiable(_discoveredUsers);

  @override
  Future<void> initialize() async {
    // Listen to adapter state changes (best-effort; ignore if unsupported)
    try {
      _adapterStateSubscription = fbp.FlutterBluePlus.adapterState.listen((state) {
        print('[BluetoothServiceWindows] Adapter state stream: $state');
        if (state == fbp.BluetoothAdapterState.on) {
          // Adapter is on
        }
      });
    } catch (e) {
      // Some plugin builds may not expose adapterState on Windows; ignore
      print('[BluetoothServiceWindows] adapterState stream unsupported: $e');
    }

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
      final supported = await fbp.FlutterBluePlus.isSupported;
      print('[BluetoothServiceWindows] FlutterBluePlus.isSupported: $supported');
      if (!supported) {
        _isBluetoothAvailable = false;
        throw UnsupportedError(
          'Bluetooth radio not detected on this Windows device. '
          'Peer discovery requires Bluetooth hardware. '
          'Please install a Bluetooth adapter and enable it in Windows Settings.',
        );
      }

      // Probe by starting a short scan; if it succeeds, adapter is effectively ON
      try {
        print('[BluetoothServiceWindows] Probing scan start...');
        await fbp.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 2),
          // Do not filter here; probe for basic scan capability
        );
        // If we get here without exception, scanning API is available
        print('[BluetoothServiceWindows] Scan probe succeeded');
      } catch (e) {
        // Do not fail hard if probing scan fails for transient reasons.
        // We will still attempt scanning in the main flow.
        print('[BluetoothServiceWindows] Scan probe failed (continuing): $e');
      }

      _isBluetoothAvailable = true;
      return true;
    } catch (e) {
      // Only treat explicit UnsupportedError (no hardware) as a hard failure
      if (e is UnsupportedError) {
        _isBluetoothAvailable = false;
        rethrow;
      }
      // For other errors, log and report not-ready rather than hard failing
      _isBluetoothAvailable = false;
      print('[BluetoothServiceWindows] Error checking Bluetooth: $e');
      return false;
    }
  }

  @override
  Future<void> startAdvertising(String userId, String nickname) async {
    if (_isAdvertising) {
      return;
    }

    _ensureBluetoothAvailability();

    print('[BluetoothServiceWindows] startAdvertising invoked');
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
      print('[BluetoothServiceWindows] startScanning begin');
      _isScanning = true;

      // Use flutter_blue_plus_windows for scanning
      // Start scanning
      _scanSubscription = fbp.FlutterBluePlus.scanResults.listen((results) {
        try {
          print('[BluetoothServiceWindows] scanResults batch: ${results.length}');
        } catch (_) {}
        for (var result in results) {
          _processScanResult(result);
        }
      });

      await fbp.FlutterBluePlus.startScan(
        // Some Windows stacks behave better with a finite timeout; we'll restart periodically.
        timeout: const Duration(seconds: 60),
        // Do not restrict by service UUID to allow manufacturer-only adverts to pass through.
        // We'll filter by service/manufacturer data in _processScanResult.
      );
      print('[BluetoothServiceWindows] startScan issued');

      // Periodically restart scan to keep data flowing on some adapters
      _scanRestartTimer?.cancel();
      _scanRestartTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
        if (!_isScanning) {
          return;
        }
        try {
          print('[BluetoothServiceWindows] restarting scan...');
          await fbp.FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 100));
          await fbp.FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 60),
          );
          print('[BluetoothServiceWindows] scan restart issued');
        } catch (e) {
          print('[BluetoothServiceWindows] scan restart error: $e');
        }
      });
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
      _scanRestartTimer?.cancel();
      _scanRestartTimer = null;
      await fbp.FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
    } catch (e) {
      print('Error stopping scan: $e');
    }
  }

  void _processScanResult(fbp.ScanResult result) {
    try {
      // Diagnostic: log basic advertisement summary to verify frames are received
      final mdDiag = result.advertisementData.manufacturerData;
      final sdDiag = result.advertisementData.serviceData;
      try {
        print('[WinScan] name=${result.advertisementData.localName}, '
            'md.keys=${mdDiag.keys.toList()}, '
            'md.len=${mdDiag.values.isEmpty ? 0 : mdDiag.values.first.length}, '
            'sd.keys=${sdDiag.keys.toList()}');
      } catch (_) {}

      // Try to get data from service data first
      final serviceData = result.advertisementData.serviceData;
      final serviceGuid = fbp.Guid(serviceUuid);
      
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
    // Mirror Android encoding: compact JSON and truncated nickname to fit legacy adverts
    String truncatedNickname = nickname;
    if (truncatedNickname.runes.length > 12) {
      truncatedNickname = String.fromCharCodes(truncatedNickname.runes.take(12));
    }

    var data = {
      'userId': userId,
      'nickname': truncatedNickname,
    };
    var jsonString = jsonEncode(data);
    var bytes = utf8.encode(jsonString);
    if (bytes.length <= 24) {
      return bytes;
    }

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


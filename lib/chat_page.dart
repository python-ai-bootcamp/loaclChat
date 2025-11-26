import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/discovered_user.dart';
import '../services/bluetooth_service.dart';

class ChatPage extends StatefulWidget {
  final String userId;
  final String nickname;
  final String? avatarPath;
  final Uint8List? avatarBytes;

  const ChatPage({
    super.key,
    required this.userId,
    required this.nickname,
    this.avatarPath,
    this.avatarBytes,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final BluetoothServiceBase _bluetoothService;
  StreamSubscription<Map<String, DiscoveredUser>>? _usersSubscription;
  Map<String, DiscoveredUser> _discoveredUsers = {};
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _bluetoothService = BluetoothService.create();
    _initializeBluetooth();
  }

  Future<void> _initializeBluetooth() async {
    // Skip Bluetooth on web
    if (kIsWeb) {
      setState(() {
        _isInitialized = true;
        _errorMessage = 'Bluetooth peer-to-peer discovery is not available on web. Please use a mobile device or desktop app.';
      });
      return;
    }

    try {
      await _bluetoothService.initialize();
      
      final hasPermission = await _bluetoothService.checkPermissions();
      if (!hasPermission) {
        setState(() {
          _errorMessage = 'Bluetooth is not available. Please enable Bluetooth.';
          _isInitialized = true;
        });
        return;
      }

      // Start advertising
      await _bluetoothService.startAdvertising(widget.userId, widget.nickname);

      // Start scanning
      await _bluetoothService.startScanning();

      // Listen to discovered users
      _usersSubscription = _bluetoothService.discoveredUsersStream.listen((users) {
        if (mounted) {
          setState(() {
            _discoveredUsers = users;
          });
        }
      });

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        if (e is UnsupportedError) {
          _errorMessage =
              e.message ?? 'Bluetooth is not supported on this device.';
        } else {
          _errorMessage = 'Error initializing Bluetooth: $e';
        }
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    _bluetoothService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isInitialized
          ? Column(
              children: [
                // User info header
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: Row(
                    children: [
                      (widget.avatarBytes != null ||
                              (widget.avatarPath != null &&
                                  !kIsWeb &&
                                  File(widget.avatarPath!).existsSync()))
                          ? ClipOval(
                              child: kIsWeb && widget.avatarBytes != null
                                  ? Image.memory(
                                      widget.avatarBytes!,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const CircleAvatar(
                                          radius: 25,
                                          child: Icon(Icons.person, size: 25),
                                        );
                                      },
                                    )
                                  : widget.avatarPath != null && !kIsWeb
                                      ? Image.file(
                                          File(widget.avatarPath!),
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const CircleAvatar(
                                              radius: 25,
                                              child: Icon(Icons.person, size: 25),
                                            );
                                          },
                                        )
                                      : const CircleAvatar(
                                          radius: 25,
                                          child: Icon(Icons.person, size: 25),
                                        ),
                            )
                          : const CircleAvatar(
                              radius: 25,
                              child: Icon(Icons.person, size: 25),
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.nickname,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'ID: ${widget.userId}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.bluetooth_connected,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                // Discovered users list
                Expanded(
                  child: _discoveredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bluetooth_searching,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Scanning for nearby users...',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Users will appear here when discovered',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _discoveredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _discoveredUsers.values.elementAt(index);
                            final timeSinceLastSeen =
                                DateTime.now().difference(user.lastSeen);
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 4.0,
                              ),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(
                                  user.nickname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ID: ${user.userId}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      'Last seen: ${timeSinceLastSeen.inSeconds}s ago',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.bluetooth,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            )
          : Center(
              child: _errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Initializing Bluetooth...'),
                      ],
                    ),
            ),
    );
  }
}


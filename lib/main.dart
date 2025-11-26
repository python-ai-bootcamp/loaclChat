import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'welcome_page.dart';
import 'pages/bluetooth_unavailable_page.dart';
import 'services/bluetooth_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Widget? _initialRoute;
  bool _isCheckingBluetooth = true;

  @override
  void initState() {
    super.initState();
    _checkBluetoothAvailability();
  }

  Future<void> _checkBluetoothAvailability() async {
    // Skip check on web
    if (kIsWeb) {
      setState(() {
        _initialRoute = const WelcomePage();
        _isCheckingBluetooth = false;
      });
      return;
    }

    // Only check Bluetooth on Windows (where we have issues)
    if (Platform.isWindows) {
      try {
        final bluetoothService = BluetoothService.create();
        await bluetoothService.initialize();
        
        final isSupported = await bluetoothService.checkPermissions();
        
        setState(() {
          if (isSupported) {
            _initialRoute = const WelcomePage();
          } else {
            _initialRoute = const BluetoothUnavailablePage();
          }
          _isCheckingBluetooth = false;
        });
      } catch (e) {
        // If check fails (e.g., UnsupportedError), show unavailable page
        setState(() {
          _initialRoute = const BluetoothUnavailablePage();
          _isCheckingBluetooth = false;
        });
      }
    } else {
      // On other platforms, go directly to welcome page
      setState(() {
        _initialRoute = const WelcomePage();
        _isCheckingBluetooth = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cool Project',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: _isCheckingBluetooth
          ? const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Checking Bluetooth availability...'),
                  ],
                ),
              ),
            )
          : _initialRoute ?? const WelcomePage(),
    );
  }
}


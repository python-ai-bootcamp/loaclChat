import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'chat_page.dart';
import 'pages/bluetooth_unavailable_page.dart';
import 'services/bluetooth_service.dart';
import 'utils/user_id_generator.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _nicknameController = TextEditingController();
  File? _selectedAvatar;
  Uint8List? _selectedAvatarBytes;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 200,
        maxHeight: 200,
        imageQuality: 80,
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          if (kIsWeb) {
            _selectedAvatarBytes = bytes;
            _selectedAvatar = null;
          } else {
            _selectedAvatar = File(image.path);
            _selectedAvatarBytes = null;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _handleLogin() async {
    final nickname = _nicknameController.text.trim();
    
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a nickname')),
      );
      return;
    }

    // Check Bluetooth availability before navigating (skip on web)
    if (!kIsWeb && Platform.isWindows) {
      setState(() {
        _isLoading = true;
      });

      try {
        final bluetoothService = BluetoothService.create();
        await bluetoothService.initialize();
        final hasBluetooth = await bluetoothService.checkPermissions();
        
        if (!hasBluetooth) {
          setState(() {
            _isLoading = false;
          });
          
          // Show error and navigate to unavailable page
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const BluetoothUnavailablePage(),
            ),
          );
          return;
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        
        // If check fails, show unavailable page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const BluetoothUnavailablePage(),
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    // Generate unique user ID
    final userId = UserIdGenerator.generate();

    // Navigate to chat page
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          userId: userId,
          nickname: nickname,
          avatarPath: kIsWeb ? null : _selectedAvatar?.path,
          avatarBytes: _selectedAvatarBytes,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Welcome!',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 48),
              
              // Avatar selection
              GestureDetector(
                onTap: _pickImage,
                child: (_selectedAvatar != null || _selectedAvatarBytes != null)
                    ? ClipOval(
                        child: kIsWeb && _selectedAvatarBytes != null
                            ? Image.memory(
                                _selectedAvatarBytes!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return CircleAvatar(
                                    radius: 60,
                                    backgroundColor: Colors.grey[300],
                                    child: const Icon(Icons.person, size: 60, color: Colors.grey),
                                  );
                                },
                              )
                            : _selectedAvatar != null
                                ? Image.file(
                                    _selectedAvatar!,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return CircleAvatar(
                                        radius: 60,
                                        backgroundColor: Colors.grey[300],
                                        child: const Icon(Icons.person, size: 60, color: Colors.grey),
                                      );
                                    },
                                  )
                                : const CircleAvatar(
                                    radius: 60,
                                    backgroundColor: Colors.grey,
                                    child: Icon(Icons.person, size: 60, color: Colors.white),
                                  ),
                      )
                    : const CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey,
                        child: Icon(Icons.person, size: 60, color: Colors.white),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _pickImage,
                child: const Text('Select Avatar (Optional)'),
              ),
              const SizedBox(height: 32),
              
              // Nickname field
              TextField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  hintText: 'Enter your nickname',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _handleLogin(),
              ),
              const SizedBox(height: 32),
              
              // Login button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


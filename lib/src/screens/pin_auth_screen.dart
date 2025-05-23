import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/screens/admin_panel_screen.dart';

class PinAuthScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const PinAuthScreen({super.key, required this.cameras});

  @override
  State<PinAuthScreen> createState() => _PinAuthScreenState();
}

class _PinAuthScreenState extends State<PinAuthScreen> {
  static const String ADMIN_PIN = "1234"; // Секретный PIN-код
  String enteredPin = "";
  bool isError = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
              Color(0xFF0f3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Back button
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ],
                ),
                
                const SizedBox(height: 40),
                
                // Lock icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.withOpacity(0.5), width: 2),
                  ),
                  child: const Icon(
                    Icons.lock,
                    size: 50,
                    color: Colors.orange,
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Title
                const Text(
                  'Admin Access',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 10),
                
                const Text(
                  'Enter PIN to access admin panel',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                
                const SizedBox(height: 50),
                
                // PIN dots display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < enteredPin.length 
                            ? (isError ? Colors.red : Colors.orange)
                            : Colors.white30,
                        border: Border.all(
                          color: isError ? Colors.red : Colors.orange,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                
                if (isError) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Incorrect PIN. Try again.',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                  ),
                ],
                
                const SizedBox(height: 50),
                
                // Number pad
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.2,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      if (index == 9) {
                        return _buildNumberButton(
                          null,
                          icon: Icons.clear,
                          onTap: () => _clearPin(),
                        );
                      } else if (index == 10) {
                        return _buildNumberButton("0", onTap: () => _addDigit("0"));
                      } else if (index == 11) {
                        return _buildNumberButton(
                          null,
                          icon: Icons.backspace,
                          onTap: () => _removeDigit(),
                        );
                      } else {
                        String number = (index + 1).toString();
                        return _buildNumberButton(number, onTap: () => _addDigit(number));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildNumberButton(String? number, {IconData? icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30),
        ),
        child: Center(
          child: number != null
              ? Text(
                  number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
        ),
      ),
    );
  }
  
  void _addDigit(String digit) {
    if (enteredPin.length < 4) {
      setState(() {
        enteredPin += digit;
        isError = false;
      });
      
      if (enteredPin.length == 4) {
        _checkPin();
      }
    }
  }
  
  void _removeDigit() {
    if (enteredPin.isNotEmpty) {
      setState(() {
        enteredPin = enteredPin.substring(0, enteredPin.length - 1);
        isError = false;
      });
    }
  }
  
  void _clearPin() {
    setState(() {
      enteredPin = "";
      isError = false;
    });
  }
  
  void _checkPin() {
    if (enteredPin == ADMIN_PIN) {
      // Correct PIN - navigate to admin panel
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminPanelScreen(cameras: widget.cameras),
        ),
      );
    } else {
      // Incorrect PIN
      setState(() {
        isError = true;
      });
      
      // Clear PIN after 1 second
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _clearPin();
        }
      });
    }
  }
} 
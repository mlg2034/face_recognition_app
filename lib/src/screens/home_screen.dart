import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/screens/face_recognition_screen.dart';
import 'package:realtime_face_recognition/src/screens/pin_auth_screen.dart';

class HomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;

  const HomeScreen({super.key, required this.cameras});

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
                const SizedBox(height: 40),
                // App Title
                const Text(
                  'Face Recognition',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Text(
                  'System',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 60),
                
                // Recognition Mode Card
                Expanded(
                  child: Column(
                    children: [
                      _buildModeCard(
                        context: context,
                        title: 'Face Recognition',
                        subtitle: 'Scan faces for access control',
                        icon: Icons.face_retouching_natural,
                        color: Colors.blue,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FaceRecognitionScreen(cameras: cameras),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      
                      // Admin Mode Card
                      _buildModeCard(
                        context: context,
                        title: 'Admin Panel',
                        subtitle: 'Manage users and settings',
                        icon: Icons.admin_panel_settings,
                        color: Colors.orange,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PinAuthScreen(cameras: cameras),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Footer
                const Text(
                  'Select mode to continue',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.5), width: 2),
              ),
              child: Icon(
                icon,
                size: 40,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
} 
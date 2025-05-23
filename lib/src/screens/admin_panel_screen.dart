import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/screens/admin_camera_screen.dart';
import 'package:realtime_face_recognition/src/screens/registered_users_screen.dart';
import 'package:realtime_face_recognition/src/screens/threshold_tuning_screen.dart';
import 'package:realtime_face_recognition/src/services/face_detection_service.dart';
import 'package:realtime_face_recognition/src/services/recognizer.dart';

class AdminPanelScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminPanelScreen({super.key, required this.cameras});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late FaceDetectionService faceDetectionService;
  late Recognizer recognizer;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    faceDetectionService = FaceDetectionService();
    recognizer = Recognizer();
    
    await faceDetectionService.initialize();
    await recognizer.initDB();
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      faceDetectionService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
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
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.orange),
                SizedBox(height: 20),
                Text(
                  'Initializing admin services...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                // Header with back button
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        'Admin Panel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48), // To balance the back button
                  ],
                ),
                
                const SizedBox(height: 30),
                
                // Admin icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.withOpacity(0.5), width: 2),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings,
                    size: 40,
                    color: Colors.orange,
                  ),
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  'Administrative Functions',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Admin functions
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.9,
                    children: [
                      _buildAdminCard(
                        context: context,
                        title: 'Register Face',
                        subtitle: 'Add new users',
                        icon: Icons.face_retouching_natural,
                        color: Colors.blue,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdminCameraScreen(cameras: widget.cameras),
                            ),
                          );
                        },
                      ),
                      _buildAdminCard(
                        context: context,
                        title: 'Manage Users',
                        subtitle: 'View & delete users',
                        icon: Icons.people,
                        color: Colors.green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RegisteredUsersScreen(
                                faceDetectionService: faceDetectionService,
                              ),
                            ),
                          );
                        },
                      ),
                      _buildAdminCard(
                        context: context,
                        title: 'Threshold Tuning',
                        subtitle: 'Adjust recognition',
                        icon: Icons.tune,
                        color: Colors.purple,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ThresholdTuningScreen(
                                recognizer: recognizer,
                              ),
                            ),
                          );
                        },
                      ),
                      _buildAdminCard(
                        context: context,
                        title: 'System Stats',
                        subtitle: 'View metrics',
                        icon: Icons.analytics,
                        color: Colors.teal,
                        onTap: () {
                          _showRealSystemStats(context);
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Logout button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.8),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Exit Admin Panel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminCard({
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
        padding: const EdgeInsets.all(16),
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
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.5), width: 2),
              ),
              child: Icon(
                icon,
                size: 30,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRealSystemStats(BuildContext context) async {
    // Get real statistics from the services
    final users = await faceDetectionService.getRegisteredUsers();
    final accuracyReport = faceDetectionService.getAccuracyReport();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text(
          'System Statistics',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recognition System Status:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('• Registered Users: ${users.length}', style: const TextStyle(color: Colors.white70)),
            Text('• Recognition Threshold: ${Recognizer.RECOGNITION_THRESHOLD}', style: const TextStyle(color: Colors.white70)),
            Text('• High Confidence: < ${Recognizer.HIGH_CONFIDENCE_THRESHOLD}', style: const TextStyle(color: Colors.white70)),
            Text('• Medium Confidence: < ${Recognizer.MEDIUM_CONFIDENCE_THRESHOLD}', style: const TextStyle(color: Colors.white70)),
            Text('• Embedding Size: ${recognizer.EMBEDDING_SIZE} dimensions', style: const TextStyle(color: Colors.white70)),
            Text('• Model: ${recognizer.modelName.split('/').last}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const Text(
              'Performance Metrics:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(accuracyReport, style: const TextStyle(color: Colors.orange, fontSize: 12)),
            const SizedBox(height: 16),
            if (users.isNotEmpty) ...[
              const Text(
                'Registered Users:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...users.take(5).map((user) => Text('• $user', style: const TextStyle(color: Colors.white70))),
              if (users.length > 5) 
                Text('• ... and ${users.length - 5} more', style: const TextStyle(color: Colors.white70)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showDetailedStats();
            },
            child: const Text('View Details', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showDetailedStats() {
    // Show detailed statistics using the face detection service
    faceDetectionService.showFaceRecognitionStats();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📊 Detailed statistics displayed in console. Check debug output.'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _showUsersInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text(
          'User Management',
          style: TextStyle(color: Colors.white),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User management features:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• View all registered users', style: TextStyle(color: Colors.white70)),
            Text('• Delete specific users', style: TextStyle(color: Colors.white70)),
            Text('• Check registration status', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Text(
              'User management is available through the database directly or via SQLite browser tools.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _showThresholdInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text(
          'Threshold Settings',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Recognition Thresholds:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('• Recognition Threshold: ${Recognizer.RECOGNITION_THRESHOLD}', style: const TextStyle(color: Colors.white70)),
            Text('• High Confidence: < ${Recognizer.HIGH_CONFIDENCE_THRESHOLD}', style: const TextStyle(color: Colors.white70)),
            Text('• Medium Confidence: < ${Recognizer.MEDIUM_CONFIDENCE_THRESHOLD}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const Text(
              'These thresholds have been optimized for best performance. Lower values = stricter matching.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }
}

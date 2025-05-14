import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/services/face_detection_service.dart';
import 'package:realtime_face_recognition/src/services/liveness_settings_service.dart';

class RegisteredUsersScreen extends StatefulWidget {
  final FaceDetectionService faceDetectionService;
  
  const RegisteredUsersScreen({
    super.key,
    required this.faceDetectionService,
  });

  @override
  _RegisteredUsersScreenState createState() => _RegisteredUsersScreenState();
}

class _RegisteredUsersScreenState extends State<RegisteredUsersScreen> {
  late Future<List<String>> _usersFuture;
  bool _livenessCheckRequired = true;
  DateTime? _lastLivenessCheck;
  
  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadLivenessSettings();
  }
  
  void _loadUsers() {
    _usersFuture = widget.faceDetectionService.getRegisteredUsers();
  }
  
  Future<void> _loadLivenessSettings() async {
    final required = await LivenessSettingsService.isLivenessCheckRequired();
    final lastCheck = await LivenessSettingsService.getLastSuccessTime();
    
    if (mounted) {
      setState(() {
        _livenessCheckRequired = required;
        _lastLivenessCheck = lastCheck;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Зарегистрированные пользователи"),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.security),
            tooltip: 'Настройки проверки живости',
            onPressed: () {
              _showLivenessSettings();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Секция с настройками проверки живости
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Проверка живости',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Switch(
                      value: _livenessCheckRequired,
                      onChanged: (value) async {
                        await LivenessSettingsService.setLivenessCheckRequired(value);
                        _loadLivenessSettings();
                      },
                      activeColor: Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _livenessCheckRequired
                      ? 'Проверка живости активирована'
                      : 'Проверка живости отключена',
                  style: TextStyle(
                    color: _livenessCheckRequired ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_lastLivenessCheck != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Последняя проверка: ${_formatDateTime(_lastLivenessCheck!)}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          
          // Список пользователей
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          "Ошибка загрузки пользователей: ${snapshot.error}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _loadUsers();
                            });
                          },
                          child: const Text("Повторить"),
                        ),
                      ],
                    ),
                  );
                }
                
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off, size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "Нет зарегистрированных пользователей",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Зарегистрируйте лицо, чтобы увидеть его здесь",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                
                List<String> users = snapshot.data!;
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: const Icon(Icons.person, color: Colors.blue),
                      ),
                      title: Text(
                        users[index],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _showDeleteConfirmation(users[index]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'только что';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} мин. назад';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} ч. назад';
    } else {
      return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
  
  void _showLivenessSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Настройки проверки живости"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text("Требовать проверку живости"),
              subtitle: const Text("Защищает от подделки при помощи фото или видео"),
              value: _livenessCheckRequired,
              onChanged: (value) async {
                await LivenessSettingsService.setLivenessCheckRequired(value);
                if (mounted) {
                  Navigator.pop(context);
                  _loadLivenessSettings();
                }
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await LivenessSettingsService.resetLivenessSettings();
                if (mounted) {
                  Navigator.pop(context);
                  _loadLivenessSettings();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text("Сбросить настройки"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Закрыть"),
          ),
        ],
      ),
    );
  }
  
  void _showDeleteConfirmation(String userName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Удалить пользователя"),
        content: Text("Вы уверены, что хотите удалить $userName?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteUser(userName);
            },
            child: const Text("Удалить", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteUser(String userName) async {
    try {
      await widget.faceDetectionService.deleteUser(userName);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$userName успешно удален"))
        );
        
        setState(() {
          _loadUsers();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Не удалось удалить пользователя: $e"))
        );
      }
    }
  }
} 
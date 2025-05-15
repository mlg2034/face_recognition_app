import 'package:shared_preferences/shared_preferences.dart';

class LivenessSettingsService {
  static const String _livenessRequiredKey = 'liveness_check_required';
  static const String _lastSuccessTimeKey = 'liveness_last_success_time';
  static const int _livenessTimeoutMinutes = 10; // Время действия проверки живости

  // Получить, требуется ли проверка живости
  static Future<bool> isLivenessCheckRequired() async {
    final prefs = await SharedPreferences.getInstance();
    
    // По умолчанию проверка живости включена
    final required = prefs.getBool(_livenessRequiredKey) ?? true;
    
    if (!required) {
      return false;
    }
    
    // Проверяем, не истек ли срок действия последней проверки
    final lastSuccessTime = prefs.getInt(_lastSuccessTimeKey);
    if (lastSuccessTime != null) {
      final lastCheckTime = DateTime.fromMillisecondsSinceEpoch(lastSuccessTime);
      final now = DateTime.now();
      
      // Если с момента последней успешной проверки прошло меньше установленного времени
      if (now.difference(lastCheckTime).inMinutes < _livenessTimeoutMinutes) {
        return false; // Проверка уже пройдена и еще действительна
      }
    }
    
    return true;
  }
  
  static Future<void> setLivenessCheckPassed() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_lastSuccessTimeKey, now);
  }
  
  static Future<void> setLivenessCheckRequired(bool required) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_livenessRequiredKey, required);
  }
  
  static Future<DateTime?> getLastSuccessTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastSuccessTimeKey);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }
  
  static Future<void> resetLivenessSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_livenessRequiredKey);
    await prefs.remove(_lastSuccessTimeKey);
  }
} 
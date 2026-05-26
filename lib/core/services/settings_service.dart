import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight wrapper around SharedPreferences for app settings.
class SettingsService {
  static const _keyDefaultRate = 'default_rate_per_fat';

  /// Returns the saved default Rate per FAT (falls back to 9.0).
  static Future<double> getDefaultRate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyDefaultRate) ?? 9.0;
  }

  /// Persists the default Rate per FAT.
  static Future<void> setDefaultRate(double rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDefaultRate, rate);
  }
}

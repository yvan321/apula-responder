import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmsService {
  static final Telephony _telephony = Telephony.instance;

  static bool _enabled = false;
  static String _number = "";

  // -------------------------------
  // INITIALIZE SERVICE (IMPORTANT)
  // -------------------------------
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('smsEnabled') ?? false;
    _number = prefs.getString('responderNumber') ?? "";

    print("📲 SMS Initialized");
    print("Enabled: $_enabled");
    print("Number: $_number");
  }

  // -------------------------------
  // SAVE SETTINGS
  // -------------------------------
  static Future<void> saveSettings({
    required bool enabled,
    required String number,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smsEnabled', enabled);
    await prefs.setString('responderNumber', number);

    _enabled = enabled;
    _number = number;

    print("💾 SMS Settings Saved");
  }

  // -------------------------------
  // LOAD SETTINGS
  // -------------------------------
  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    bool enabled = prefs.getBool('smsEnabled') ?? false;
    String number = prefs.getString('responderNumber') ?? "";

    return {
      "enabled": enabled,
      "number": number,
    };
  }

  // -------------------------------
  // SEND DISPATCH SMS
  // -------------------------------
  static Future<void> sendDispatch({required String location}) async {
    print("📲 SMS FUNCTION CALLED");
    print("Enabled: $_enabled");
    print("Number: $_number");

    if (!_enabled) {
      print("❌ SMS DISABLED");
      return;
    }

    if (_number.isEmpty) {
      print("❌ No responder number saved");
      return;
    }

    try {
      await _telephony.sendSms(
        to: _number,
        message:
            "APULA DISPATCH ALERT\n"
            "Emergency: Possible fire incident reported.\n"
            "Location: $location\n"
            "Please respond immediately.",
      );

      print("✅ SMS SENT SUCCESSFULLY");
    } catch (e) {
      print("❌ SMS FAILED: $e");
    }
  }
}
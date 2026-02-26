import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/services/sms_service.dart';

class NotifSettingsPage extends StatefulWidget {
  const NotifSettingsPage({super.key});

  @override
  State<NotifSettingsPage> createState() => _NotifSettingsPageState();
}

class _NotifSettingsPageState extends State<NotifSettingsPage> {
  bool _sendViaSms = false;

  final TextEditingController _phoneController = TextEditingController(
    text: "+639123456789",
  );

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // LOAD SAVED SETTINGS
  Future<void> _loadSettings() async {
    final settings = await SmsService.loadSettings();

    setState(() {
      _sendViaSms = settings["enabled"];
      _phoneController.text = settings["number"].isEmpty
          ? "+639XXXXXXXXX"
          : settings["number"];
    });
  }

  // SAVE SETTINGS
  void _saveSettings() async {
    if (_sendViaSms && _phoneController.text.trim().isEmpty) {
      _showSnackBar("Please enter responder phone number.", Colors.red);
      return;
    }

    await SmsService.saveSettings(
      enabled: _sendViaSms,
      number: _phoneController.text.trim(),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _loadingDialog("Saving your notification settings..."),
    );

    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context);
      _showSuccessDialog("Notification Settings Saved!");
    });
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _loadingDialog(String message) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset('assets/fireloading.json', width: 130, height: 130),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFA30000),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showSmsDisclaimer() async {
    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            "APULA SMS Alert Notice",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "SMS alerts allow you to receive fire dispatch notifications even without internet connection.\n\n"
            "These messages are sent through your mobile carrier network. "
            "Standard text messaging rates or data charges may apply depending on your service provider.\n\n"
            "By enabling this feature, you agree to possible carrier charges.",
            textAlign: TextAlign.justify,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFA30000),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("I UNDERSTAND"),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pop(context);
          Navigator.pop(context);
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                'assets/check orange.json',
                width: 150,
                height: 150,
                repeat: false,
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFA30000),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFA30000);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: const Icon(
                  Icons.chevron_left,
                  size: 30,
                  color: redColor,
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Text(
                "Notification Settings",
                style: TextStyle(
                  color: redColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: redColor.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              title: const Text(
                                "Send Dispatch SMS to Responder",
                              ),
                              activeColor: redColor,
                              value: _sendViaSms,
                              onChanged: (value) async {
                                if (value == true) {
                                  bool accepted = await _showSmsDisclaimer();

                                  if (!accepted) return;

                                  setState(() {
                                    _sendViaSms = true;
                                  });
                                } else {
                                  setState(() {
                                    _sendViaSms = false;
                                  });
                                }
                              },
                            ),

                            const SizedBox(height: 10),

                            TextField(
                              controller: _phoneController,
                              enabled: _sendViaSms,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: "Responder Phone Number",
                                hintText: "+639XXXXXXXXX",
                                prefixIcon: const Icon(
                                  Icons.local_fire_department,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            if (!_sendViaSms)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  "Enable SMS to send fire dispatch alerts.",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: redColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            "Save Settings",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

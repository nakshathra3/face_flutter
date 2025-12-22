import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  CameraController? _controller;
  bool _loading = true;
  bool _processing = false;

  String _statusText = "Ready";
  bool _success = true; // controls status icon color
  String _activeTab = "in"; // in | out
  String? _recognizedImageBase64;
  String? _emotion;
  String? _employeeName;
  double? _hoursWorked;

  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startClock();
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    _controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  /// ✅ FIXED CAPTURE LOGIC
  Future<void> _captureAndSend() async {
    if (_processing || _controller == null) return;

    setState(() {
      _processing = true;
      _statusText = "Scanning face...";
      _success = true;
    });

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await ApiService.recognizeFace(base64Image, _activeTab);

      if (!mounted) return;

      if (response["matched"] == true) {
        final message = response["message"] ?? "";
        final employee = response["employee"];
        final emotion = response["emotion"] ?? "neutral";
        final imageBase64 = response["image"];
        final record = response["record"];

        setState(() {
          _recognizedImageBase64 = imageBase64;
          _emotion = emotion;
          _employeeName = employee != null ? employee["name"] : null;
          _hoursWorked = record != null && record["hours_worked"] != null
              ? record["hours_worked"].toDouble()
              : null;

          _statusText = message.isNotEmpty &&
                  (message.contains("Already") || message.contains("Clock in"))
              ? message
              : (_activeTab == "in"
                  ? "✔ Clock-In Successful"
                  : "✔ Clock-Out Successful");
          _success = true;
        });

        // Show success snackbar with emotion message
        final emotionMessage = _getEmotionMessage(emotion);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusText),
                if (emotionMessage.isNotEmpty)
                  Text(
                    emotionMessage,
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        final errorMsg = response["message"] ?? "Failed to recognize";
        // Ensure message starts with "Failed to recognize" if it doesn't already
        final displayMsg = errorMsg.contains("Failed to recognize")
            ? errorMsg
            : "Failed to recognize - $errorMsg";

        setState(() {
          _statusText = displayMsg;
          _success = false;
          _recognizedImageBase64 = null;
          _emotion = null;
          _employeeName = null;
          _hoursWorked = null;
        });

        // Show error snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final errorMsg = "Camera error: ${e.toString()}";
      setState(() {
        _statusText = errorMsg;
        _success = false;
        _recognizedImageBase64 = null;
        _emotion = null;
        _employeeName = null;
        _hoursWorked = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      /// ✅ ALWAYS unlock button
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  String _getEmotionMessage(String emotion) {
    final messages = {
      "happy": "😊 You're looking great today! Keep that positive energy!",
      "sad": "😔 Hope your day gets better! You've got this!",
      "angry": "😠 Take a deep breath. Everything will be okay!",
      "surprise": "😲 Ready for an amazing day ahead!",
      "fear": "😰 Don't worry, you're doing great!",
      "disgust": "😤 Stay strong and keep pushing forward!",
      "neutral": "😐 Have a productive day!",
    };
    return messages[emotion.toLowerCase()] ?? "Have a great day!";
  }

  @override
  void dispose() {
    _timer.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('hh:mm:ss a').format(_now);
    final date = DateFormat('EEEE, dd MMMM').format(_now);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      bottomNavigationBar: const BottomNav(index: 1),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  /// HEADER
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    height: 60,
                    color: const Color(0xFF1C1A1A),
                    child: Row(
                      children: [
                        IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Back",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                      child: Column(
                        children: [
                          /// CLOCK CARD
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1A1A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  time,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  date,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          /// CLOCK IN / OUT SWITCH
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1A1A),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                _tabButton("Clock In", "in"),
                                _tabButton("Clock Out", "out"),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),

                          /// CAMERA
                          Container(
                            width: 260,
                            height: 260,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF72BF45),
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF57C200).withOpacity(0.4),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _controller!
                                            .value.previewSize?.height ??
                                        260,
                                    height:
                                        _controller!.value.previewSize?.width ??
                                            260,
                                    child: CameraPreview(_controller!),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          /// CAPTURE BUTTON
                          ElevatedButton(
                            onPressed: _processing ? null : _captureAndSend,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF72BF45),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _processing
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  )
                                : const Text(
                                    "Capture Face",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 24),

                          /// RECOGNIZED IMAGE (if available)
                          if (_recognizedImageBase64 != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1A1A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF72BF45),
                                ),
                              ),
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      base64Decode(_recognizedImageBase64!),
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (_employeeName != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _employeeName!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                  if (_emotion != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _getEmotionMessage(_emotion!),
                                      style: const TextStyle(
                                        color: Color(0xFF72BF45),
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                          /// STATUS CARD
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1A1A),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _success
                                    ? const Color(0xFF72BF45)
                                    : Colors.redAccent,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: _success
                                        ? const Color(0xFF72BF45)
                                        : Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _success ? Icons.check : Icons.close,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _statusText,
                                  style: TextStyle(
                                    color: _success
                                        ? const Color(0xFF72BF45)
                                        : Colors.redAccent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (_hoursWorked != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF72BF45)
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "Hours Worked: ${_hoursWorked!.toStringAsFixed(2)} hrs",
                                      style: const TextStyle(
                                        color: Color(0xFF72BF45),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _tabButton(String label, String value) {
    final active = _activeTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF72BF45) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

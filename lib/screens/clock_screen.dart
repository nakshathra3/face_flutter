import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/api_service.dart';
import '../widgets/camera_preview_widget.dart';
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
  String _status = "Ready";

  @override
  void initState() {
    super.initState();
    _initCamera();
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

  Future<void> _handleAction(String action) async {
    if (_processing || _controller == null) return;

    setState(() {
      _processing = true;
      _status = "Processing...";
    });

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await ApiService.recognizeFace(
        base64Image,
        action, // "in" or "out"
      );

      if (response["matched"] != true) {
        setState(() {
          _status = response["message"] ?? "Face not recognized";
        });
      } else if (response.containsKey("record")) {
        final record = response["record"];
        setState(() {
          if (action == "in") {
            _status = "✔ Clocked In at ${record["clock_in"]}";
          } else {
            _status = "✔ Clocked Out at ${record["clock_out"]}";
          }
        });
      } else {
        setState(() {
          _status = response["message"] ?? "Action not allowed";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Camera / Network error";
      });
    }

    setState(() => _processing = false);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(index: 1),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    "Employee Attendance",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  /// Camera Preview (same role as clock.html)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: CameraPreviewWidget(
                          controller: _controller!,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  /// Status Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// Clock In / Clock Out Buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                _processing ? null : () => _handleAction("in"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              "CLOCK IN",
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                _processing ? null : () => _handleAction("out"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              "CLOCK OUT",
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/api_service.dart';
import '../widgets/camera_preview_widget.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  CameraController? _controller;
  bool _loading = true;
  bool _countingDown = false;
  int _countdown = 0;

  final _idController = TextEditingController();
  final _nameController = TextEditingController();

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

  Future<void> _startEnrollment() async {
    if (_countingDown || _controller == null) return;

    setState(() {
      _countdown = 3;
      _countingDown = true;
    });

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_countdown == 1) {
        timer.cancel();
        await _captureAndEnroll();
        setState(() => _countingDown = false);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _captureAndEnroll() async {
    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final faceBase64 = base64Encode(bytes);

      final success = await ApiService.enrollEmployee(
        employeeId: _idController.text.trim(),
        name: _nameController.text.trim(),
        faceBase64: faceBase64,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? "Enrollment Successful" : "Enrollment Failed",
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Camera error during enrollment"),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Employee Enrollment")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      CameraPreviewWidget(controller: _controller!),
                      if (_countingDown)
                        Center(
                          child: Text(
                            "$_countdown",
                            style: const TextStyle(
                              fontSize: 80,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          labelText: "Employee ID",
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Employee Name",
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _countingDown ? null : _startEnrollment,
                        child: const Text("Enroll Employee"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

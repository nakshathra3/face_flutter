import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

// Add this custom widget class before _ClockScreenState

class ArcProgressIndicator extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final Color color;
  final double strokeWidth;
  final double size;

  const ArcProgressIndicator({
    super.key,
    required this.progress,
    this.color = const Color(0xFF72BF45),
    this.strokeWidth = 8.0,
    this.size = 60.0,
  });

  @override
  State<ArcProgressIndicator> createState() => _ArcProgressIndicatorState();
}

class _ArcProgressIndicatorState extends State<ArcProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: widget.progress).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(ArcProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _animation = Tween<double>(
              begin: oldWidget.progress, end: widget.progress)
          .animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            painter: ArcProgressPainter(
              progress: _animation.value,
              color: widget.color,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class ArcProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  ArcProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Draw background arc (subtle)
    final backgroundPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -90 * (3.14159 / 180), // Start from top
      360 * (3.14159 / 180), // Full circle
      false,
      backgroundPaint,
    );

    // Draw progress arc
    final sweepAngle = 360 * progress * (3.14159 / 180);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -90 * (3.14159 / 180), // Start from top
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(ArcProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _ClockScreenState extends State<ClockScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _loading = true;
  bool _processing = false;
  bool _isInitializing = false;

  String _statusText = "Ready";
  bool _success = true; // controls status icon color
  String _activeTab = "in"; // in | out
  String? _recognizedImageBase64;
  String? _emotion;
  String? _employeeName;
  double? _hoursWorked;

  late Timer _timer;
  DateTime _now = DateTime.now();

  // Add progress tracking
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller != null && _controller!.value.isInitialized) {
      if (state == AppLifecycleState.inactive) {
        _controller!.dispose();
        _controller = null;
      } else if (state == AppLifecycleState.resumed) {
        if (!_isInitializing && _controller == null) {
          _initCamera();
        }
      }
    }
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  Future<void> _initCamera() async {
    if (_isInitializing) return;

    _isInitializing = true;

    try {
      // Dispose existing controller if any
      if (_controller != null) {
        try {
          await _controller!.dispose();
        } catch (e) {
          print("⚠️ [CLOCK] Error disposing old controller: $e");
        }
        _controller = null;
      }

      // Delay to ensure previous camera is fully released (1.5 seconds for loading)
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) {
        _isInitializing = false;
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        print("❌ [CLOCK] No cameras available");
        if (mounted) {
          setState(() {
            _loading = false;
            _isInitializing = false;
          });
        }
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _loading = false;
          _isInitializing = false;
        });
        print("✅ [CLOCK] Camera initialized successfully");
      }
    } catch (e) {
      print("❌ [CLOCK] Error initializing camera: $e");
      if (mounted) {
        setState(() {
          _loading = false;
          _isInitializing = false;
        });
      }
      // Retry after a delay if initialization failed
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted &&
            (_controller == null || !_controller!.value.isInitialized)) {
          _initCamera();
        }
      });
    }
  }

  /// ✅ FIXED CAPTURE LOGIC WITH LIVE PROGRESS
  Future<void> _captureAndSend() async {
    if (_processing || _controller == null) return;

    setState(() {
      _processing = true;
      _progress = 0.0;
      _statusText = "Scanning face...";
      _success = true;
    });

    try {
      // Step 1: Capturing image (0-25%)
      _updateProgressSmoothly(0.25,
          duration: const Duration(milliseconds: 400));
      final image = await _controller!.takePicture();

      // Step 2: Reading and encoding (25-50%)
      _updateProgressSmoothly(0.50,
          duration: const Duration(milliseconds: 300));
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Step 3: Sending to API (50-90%)
      // Start API call and update progress gradually during the call
      final apiCall = ApiService.recognizeFace(base64Image, _activeTab);

      // Update progress gradually during API call (50% to 90%)
      final response = await _updateProgressDuringApiCall(0.50, 0.90, apiCall);

      if (!mounted) return;

      // Step 4: Processing response (90-100%)
      _updateProgressSmoothly(1.0, duration: const Duration(milliseconds: 200));
      await Future.delayed(const Duration(milliseconds: 100));

      if (response["matched"] == true) {
        final message = response["message"] ?? "";
        final employee = response["employee"];
        final emotion = response["emotion"] ?? "neutral";
        final imageBase64 = response["image"];
        final record = response["record"];

        final employeeName = employee != null
            ? (employee["full_name"] ?? employee["name"] ?? "")
            : "";

        // Get current time for display
        final now = DateTime.now();
        final clockTime = DateFormat('hh:mm:ss a').format(now);

        // Don't store in state - just show dialog
        setState(() {
          _processing = false;
          _progress = 0.0;
        });

        // Show success dialog
        _showClockSuccessDialog(
          imageBase64: imageBase64 ?? "",
          employeeName: employeeName,
          emotion: emotion,
          message: message.isNotEmpty &&
                  (message.contains("Already") ||
                      message.contains("Clock in first"))
              ? message
              : (_activeTab == "in"
                  ? "Successfully Clocked In"
                  : "Successfully Clocked Out"),
          clockTime: clockTime,
        );
      } else {
        final errorMsg = response["message"] ?? "Failed to recognize";

        // Don't store in state - just show dialog
        setState(() {
          _processing = false;
          _progress = 0.0;
        });

        // Show error dialog with captured image
        _showClockErrorDialog(
          imageBase64: base64Image,
          message: errorMsg,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final errorMsg = "Camera error: ${e.toString()}";

      setState(() {
        _processing = false;
        _progress = 0.0;
      });

      // Show error dialog for camera errors too (without image)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          // Auto-close after 3 seconds
          Future.delayed(const Duration(seconds: 5), () {
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          });

          return AlertDialog(
            backgroundColor: const Color(0xFF1C1A1A),
            title: Text(
              "Error",
              style: GoogleFonts.inter(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              errorMsg,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  "OK",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      /// ✅ ALWAYS unlock button
      if (mounted) {
        setState(() {
          _processing = false;
          _progress = 0.0;
        });
      }
    }
  }

  /// Smoothly animate progress from current value to target
  void _updateProgressSmoothly(double target,
      {required Duration duration}) async {
    if (!mounted || !_processing) return;

    final startProgress = _progress;
    final steps = (duration.inMilliseconds / 16).round(); // ~60fps
    final increment = (target - startProgress) / steps;

    for (int i = 0; i <= steps; i++) {
      if (!mounted || !_processing) break;

      final newProgress = (startProgress + (increment * i)).clamp(0.0, target);
      setState(() {
        _progress = newProgress;
      });

      await Future.delayed(
          Duration(milliseconds: duration.inMilliseconds ~/ steps));
    }

    // Ensure we reach exactly the target
    if (mounted && _processing) {
      setState(() {
        _progress = target.clamp(0.0, 1.0);
      });
    }
  }

  /// Update progress gradually during API call
  Future<dynamic> _updateProgressDuringApiCall(
      double start, double end, Future<dynamic> apiCall) async {
    if (!mounted || !_processing) {
      return await apiCall;
    }

    // Set initial progress
    setState(() {
      _progress = start;
    });

    // Start a timer that gradually increases progress during API call
    final progressTimer =
        Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted || !_processing) {
        timer.cancel();
        return;
      }

      // Gradually increase progress, but don't exceed end
      setState(() {
        if (_progress < end - 0.05) {
          _progress = (_progress + 0.008).clamp(start, end - 0.05);
        }
      });
    });

    // Wait for API call to complete
    try {
      final result = await apiCall;
      return result;
    } finally {
      progressTimer.cancel();
      // Set to end value when API completes
      if (mounted && _processing) {
        setState(() {
          _progress = end;
        });
      }
    }
  }

  void _updateProgress(double value) {
    if (mounted && _processing) {
      setState(() {
        _progress = value.clamp(0.0, 1.0);
      });
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

  void _showClockSuccessDialog({
    required String imageBase64,
    required String employeeName,
    required String emotion,
    required String message,
    String? clockTime,
  }) {
    final emotionMessage = _getEmotionMessage(emotion);
    final isWarning =
        message.contains("Already") || message.contains("Clock in first");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Auto-close after 3 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        });

        return AlertDialog(
          backgroundColor: const Color(0xFF1C1A1A),
          title: Text(
            isWarning ? "Notice" : "Success",
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..scale(-1.0, 1.0), // Flip horizontally
                  child: Image.memory(
                    base64Decode(imageBase64),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: GoogleFonts.inter(
                  color: isWarning ? Colors.orange : const Color(0xFF72BF45),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (employeeName.isNotEmpty && !isWarning) ...[
                const SizedBox(height: 8),
                Text(
                  employeeName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (clockTime != null && !isWarning) ...[
                const SizedBox(height: 4),
                Text(
                  clockTime,
                  style: GoogleFonts.inter(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (emotionMessage.isNotEmpty && !isWarning) ...[
                const SizedBox(height: 16),
                Text(
                  emotionMessage,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF72BF45),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF72BF45),
                foregroundColor: Colors.white,
              ),
              child: Text(
                "OK",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showClockErrorDialog({
    required String imageBase64,
    required String message,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Auto-close after 3 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        });

        return AlertDialog(
          backgroundColor: const Color(0xFF1C1A1A),
          title: Text(
            "Face Not Identified",
            style: GoogleFonts.inter(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..scale(-1.0, 1.0), // Flip horizontally
                  child: Image.memory(
                    base64Decode(imageBase64),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Face not identified. Please retry.",
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              // const SizedBox(height: 8),
              // Text(
              //   message,
              //   style: GoogleFonts.inter(
              //     color: Colors.grey,
              //     fontSize: 12,
              //   ),
              //   textAlign: TextAlign.center,
              //),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(
                "Retry",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _controller?.dispose();
    _controller = null;
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
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ArcProgressIndicator(
                                        progress: _progress,
                                        color: Colors.white,
                                        strokeWidth: 3.0,
                                        size: 20.0,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "${(_progress * 100).toInt()}%",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
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

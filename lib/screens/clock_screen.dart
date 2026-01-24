import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math';

import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';

import '../camera_cache.dart';

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
  bool _isDetectingFace = false;

  DateTime? _blinkWindowStart;
  bool _eyesWereOpen = false;
  bool _eyesWereClosed = false;

  late FaceDetector _faceDetector;

  int _closedEyeFrames = 0;
  bool _blinkDetected = false;

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
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: false,
        enableClassification: true, // REQUIRED for eye open probability
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller != null && _controller!.value.isInitialized) {
      if (state == AppLifecycleState.paused) {
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

  // ⚡ FIXED INIT: Adds 600ms safety delay to prevent "Green Screen" & hardware crashes
  Future<void> _initCamera() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      // 1. SAFETY DELAY: Give the previous screen (Enrollment) time to release the camera
      await Future.delayed(const Duration(milliseconds: 600));

      // Dispose existing controller if any
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }

      if (!mounted) {
        _isInitializing = false;
        return;
      }

      // 2. Use Cached Cameras if available (Faster)
      final cameras = cachedCameras ?? await availableCameras();
      
      if (cameras.isEmpty) {
        print("❌ [CLOCK] No cameras available");
        if (mounted) setState(() { _loading = false; _isInitializing = false; });
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
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _loading = false; // Unblock UI logic (if used)
          _isInitializing = false;
        });
        print("✅ [CLOCK] Camera initialized successfully");
      }
    } catch (e) {
      print("❌ [CLOCK] Camera Error: $e");
      // Auto-retry once if failed
      if (mounted) {
        setState(() { _loading = false; _isInitializing = false; });
      }
    }
  }
  
  // 🔐 PREVIEW-BASED LIVENESS CHECK (NO IMAGE CAPTURE)
  // 🔐 PREVIEW-BASED LIVENESS CHECK (REAL & SAFE)
  Future<bool> _detectBlinkWithinTimeWindow({
    required Duration maxDuration,
  }) async {
    _blinkWindowStart = DateTime.now();
    _eyesWereOpen = false;
    _eyesWereClosed = false;

    while (DateTime.now().difference(_blinkWindowStart!) < maxDuration) {
      // Capture a lightweight frame
      final image = await _controller!.takePicture();

      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final left = face.leftEyeOpenProbability;
        final right = face.rightEyeOpenProbability;

        if (left != null && right != null) {
          final avg = (left + right) / 2;

          if (avg > 0.55) {
            _eyesWereOpen = true;
          }

          if (avg < 0.30) {
            _eyesWereClosed = true;
          }

          // ✅ OPEN → CLOSED detected = BLINK
          if (_eyesWereOpen && _eyesWereClosed) {
            return true;
          }
        } else {
          // Glasses fallback
          if (_fallbackLiveness(face)) {
            return true;
          }
        }
      }

      // Small delay so we don't hammer the camera
      await Future.delayed(const Duration(milliseconds: 180));
    }

    return false;
  }


  bool _fallbackLiveness(Face face) {
    // Head movement check
    final yaw = face.headEulerAngleY ?? 0;

    // Face must be large & centered (prevents phone photo spoof)
    final box = face.boundingBox;
    final area = box.width * box.height;

    if (area < 9000) return false; // photo usually smaller

    // Require slight head turn
    return yaw.abs() > 6.0;
  }


  /// ✅ FIXED CAPTURE LOGIC WITH LIVE PROGRESS
  Future<void> _captureAndSend() async {
    if (_processing || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _processing = true;
      _progress = 0.0;
      _statusText = "Scanning face...";
      _success = true;
    });

    try {
      // Re-check controller before use (it might have been disposed)
      if (_controller == null || !_controller!.value.isInitialized) {
        setState(() {
          _processing = false;
        });
        return;
      }

      // 🔐 LIVENESS CHECK BEFORE CAPTURE
      final blinked = await _detectBlinkWithinTimeWindow(
        maxDuration: const Duration(seconds: 2),
      );

      if (!blinked) {
        setState(() {
          _processing = false;
          _progress = 0.0;
        });

        _showClockErrorDialog(
          imageBase64: "",
          message: "Please blink naturally once within 2 seconds or gently nod your head.",
          isSpoof: true,
        );
        return;
      }

      // Capture FINAL image AFTER liveness passes
      final image = await _controller!.takePicture();

      // Step 1: Capturing image (0-25%)
      _updateProgressSmoothly(0.25, duration: Duration(milliseconds: 400));

      // Step 2: Reading and encoding (25-50%)
      _updateProgressSmoothly(0.50,
          duration: const Duration(milliseconds: 300));
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Step 3: Sending to API (50-90%)
      // For clock-out, first check hours with preview (confirm=false)
      // For clock-in, proceed normally
      Map<String, dynamic> response;

      if (_activeTab == "out") {
        // First, get preview (hours calculation without saving)
        _updateProgressSmoothly(0.60,
            duration: const Duration(milliseconds: 200));
        final previewCall =
            ApiService.recognizeFace(base64Image, _activeTab, confirm: false);
        final previewResponse =
            await _updateProgressDuringApiCall(0.60, 0.75, previewCall);

        if (!mounted) return;

        if (previewResponse["matched"] == true) {
          final previewRecord = previewResponse["record"];
          final hoursWorked = previewRecord != null
              ? (previewRecord["hours_worked"] as num?)?.toDouble()
              : null;

          // If hours < 5, show confirmation before saving
          if (hoursWorked != null && hoursWorked < 5.0) {
            final employee = previewResponse["employee"];
            final emotion = previewResponse["emotion"] ?? "neutral";
            final imageBase64 = previewResponse["image"];

            final employeeName = employee != null
                ? (employee["full_name"] ?? employee["name"] ?? "")
                : "";

            final now = DateTime.now();
            final clockTime = DateFormat('hh:mm:ss a').format(now);

            setState(() {
              _processing = false;
              _progress = 0.0;
            });

            // Show confirmation dialog
            _showClockOutConfirmationDialog(
              imageBase64: imageBase64 ?? "",
              employeeName: employeeName,
              emotion: emotion,
              hoursWorked: hoursWorked,
              clockTime: clockTime,
              onConfirm: () async {
                // User confirmed, now actually save the clock-out
                setState(() {
                  _processing = true;
                  _progress = 0.75;
                });

                // Send actual clock-out request with confirm=true
                final confirmCall = ApiService.recognizeFace(
                    base64Image, _activeTab,
                    confirm: true);
                final confirmResponse =
                    await _updateProgressDuringApiCall(0.75, 0.95, confirmCall);

                if (!mounted) return;

                _updateProgressSmoothly(1.0,
                    duration: const Duration(milliseconds: 200));
                await Future.delayed(const Duration(milliseconds: 100));

                if (confirmResponse["matched"] == true) {
                  final confirmEmployee = confirmResponse["employee"];
                  final confirmEmotion =
                      confirmResponse["emotion"] ?? "neutral";
                  final confirmImageBase64 = confirmResponse["image"];

                  final confirmEmployeeName = confirmEmployee != null
                      ? (confirmEmployee["full_name"] ??
                          confirmEmployee["name"] ??
                          "")
                      : "";

                  setState(() {
                    _processing = false;
                    _progress = 0.0;
                  });

                  // Show success dialog
                  _showClockSuccessDialog(
                    imageBase64: confirmImageBase64 ?? "",
                    employeeName: confirmEmployeeName,
                    emotion: confirmEmotion,
                    message: "Successfully Clocked Out",
                    clockTime: clockTime,
                  );
                } else {
                  setState(() {
                    _processing = false;
                    _progress = 0.0;
                  });

                  _showClockErrorDialog(
                    imageBase64: base64Image,
                    message:
                        confirmResponse["message"] ?? "Failed to clock out",
                  );
                }
              },
              onCancel: () {
                // User cancelled - clock-out was NOT saved
                // No need to do anything, just return to normal state
              },
            );

            return; // Exit early, don't proceed with normal flow
          }
        }

        // If hours >= 5 or preview failed, proceed with normal clock-out (confirm=true)
        _updateProgressSmoothly(0.75,
            duration: const Duration(milliseconds: 200));
      }

      // Normal flow: clock-in or clock-out with hours >= 5
      final apiCall =
          ApiService.recognizeFace(base64Image, _activeTab, confirm: true);
      final apiProgressStart = _activeTab == "out" ? 0.75 : 0.50;

      // Update progress gradually during API call
      response =
          await _updateProgressDuringApiCall(apiProgressStart, 0.90, apiCall);

      if (!mounted) return;

      // Step 4: Processing response (90-100%)
      _updateProgressSmoothly(1.0, duration: const Duration(milliseconds: 200));
      await Future.delayed(const Duration(milliseconds: 100));

      if (response["matched"] == true) {
        final message = response["message"] ?? "";
        final employee = response["employee"];
        final emotion = response["emotion"] ?? "neutral";
        final imageBase64 = response["image"];

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
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (dialogContext) {
          // Auto-close after 5 seconds
          Future.delayed(const Duration(seconds: 5), () {
            if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          });

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AlertDialog(
            backgroundColor: const Color(0xFF1C1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(
                color: Color(0xFF72BF45),
                width: 2,
              ),
            ),
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
                  if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                  }
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
            ),
          );
        },
      );
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
    final emotionLower = emotion.toLowerCase();
    
    if (emotionLower == "happy") {
      final happyMessages = [
        "😄 That smile looks confidently optimistic.",
        "😏 Someone's day seems to be behaving.",
        "😄 That's a \"things are fine\" kind of face.",
        "😁 Clearly, today started on the right side.",
        "😄 Mood check: suspiciously positive.",
        "😏 That smile suggests good coffee decisions.",
        "😄 You look like today isn't winning yet.",
        "😁 That's a solid \"I've got this\" expression.",
        "😄 Happiness detected — proceed carefully.",
        "😏 That grin says things are going reasonably well.",
        "😄 You look ready… or at least willing.",
        "😁 That's a smile with confidence.",
        "😄 Optimism levels: pleasantly high.",
        "😏 You look like the plan is working.",
        "😄 That's a calm-before-the-emails smile.",
        "😁 You seem cheerful — noted.",
        "😄 That expression says \"manageable day.\"",
        "😏 Someone's expectations are nicely aligned.",
        "😄 That smile looks well-timed.",
        "😁 Happiness logged — no errors found.",
        "😄 You look prepared for today.",
        "😏 That grin suggests good timing.",
        "😄 Mood: positive. Reality: pending.",
        "😁 That's a confident start.",
        "😄 You look like things are under control.",
        "😏 That smile says, \"So far, so good.\"",
        "😄 Happiness detected — system approves.",
        "😁 That's an optimistic check-in.",
        "😄 You look surprisingly ready.",
        "😏 That grin suggests a smooth start.",
        "😄 Mood looks stable — nice.",
        "😁 That smile means progress already.",
        "😄 You look pleased — cautiously.",
        "😏 Someone's confidence is showing.",
        "😄 That expression says \"let's do this.\"",
        "😁 Happiness confirmed — briefly.",
        "😄 You look comfortable with today.",
        "😏 That smile says things are cooperating.",
        "😄 Mood detected: upbeat.",
        "😁 That's a good look for today.",
        "😄 That smile says, \"Nothing has gone wrong yet.\"",
        "😏 You look happy… did the internet work on the first try?",
        "😄 That's a rare \"everything loaded correctly\" face.",
        "😁 Either today's great — or the coffee is excellent.",
        "😄 You look like someone who remembered their password.",
        "😏 That smile suggests zero surprise meetings (so far).",
        "😄 Mood: cheerful. Inbox: unaware.",
        "😁 You look happy — the system is slightly impressed.",
        "😄 That grin says, \"Today hasn't tested me yet.\"",
        "😏 Either you're happy, or the meeting got cancelled.",
      ];
      // Use current time in milliseconds to get a random index
      final random = DateTime.now().millisecondsSinceEpoch % happyMessages.length;
      return happyMessages[random];
    }
    
    if (emotionLower == "sad") {
      final sadMessages = [
        "😔 You seem a bit down — take things at your own pace today.",
        "💙 It's okay to have quieter days. You're doing fine.",
        "🌤️ Not every day has to be perfect — one step at a time.",
        "😔 You look thoughtful — hope the day treats you kindly.",
        "💭 Some days feel heavier, and that's completely okay.",
        "🌱 Take a breath — you don't have to rush today.",
        "😔 You seem a little low — be gentle with yourself.",
        "💙 A calm start can still be a strong one.",
        "🌤️ Even slow progress is progress.",
        "😔 You look reflective — wishing you an easier day.",
        "💭 It's okay to pause and reset.",
        "🌱 One task at a time is more than enough today.",
        "😔 You seem quiet — hope things ease up soon.",
        "💙 Remember, you're not alone in this.",
        "🌤️ Some days are for patience, not pressure.",
        "😔 It looks like a tough moment — take care.",
        "💭 You don't have to be at your best every day.",
        "🌱 Small wins still count.",
        "😔 You seem a bit weighed down — hoping things improve.",
        "💙 Take today gently; that's still productive.",
        "🌤️ Even calm days move things forward.",
        "😔 You look a little tired — rest when you can.",
        "💭 It's okay to feel this way.",
        "🌱 One steady step is enough for now.",
        "😔 You seem low — hoping today brings some relief.",
        "💙 Be kind to yourself today.",
        "🌤️ A slower day doesn't mean a bad one.",
        "😔 You look thoughtful — wishing you a smoother day.",
        "💭 It's okay to take things one moment at a time.",
        "🌱 You're doing the best you can — that matters.",
        "😔 You seem a bit drained — take care.",
        "💙 Today can be gentle and still count.",
        "🌤️ Not every day needs full energy.",
        "😔 You look a little heavy-hearted — hope it eases.",
        "💭 Quiet strength still counts as strength.",
        "🌱 Even showing up is meaningful.",
        "😔 You seem down — wishing you some calm today.",
        "💙 It's okay to move slowly today.",
        "🌤️ You don't have to push through everything.",
        "😔 You look reflective — hoping things feel lighter soon.",
        "💭 Some days are about balance, not speed.",
        "🌱 You're allowed to take breaks.",
        "😔 You seem subdued — take things gently.",
        "💙 You don't have to carry everything alone.",
        "🌤️ Progress can be quiet and still real.",
        "😔 You look a bit low — hoping the day improves.",
        "💭 It's okay if today feels different.",
        "🌱 Just being here is enough.",
        "😔 You seem thoughtful — wishing you steadier moments ahead.",
        "💙 Take care — tomorrow is another chance.",
      ];
      // Use current time in milliseconds to get a random index
      final random = DateTime.now().millisecondsSinceEpoch % sadMessages.length;
      return sadMessages[random];
    }
    
    if (emotionLower == "angry") {
      final angryMessages = [
        "😠 You seem frustrated — let's take this one step at a time.",
        "🧘 It looks like a tense moment — a pause can help.",
        "😠 You appear upset — taking a breath might ease things.",
        "🌿 Some moments test our patience — it's okay to slow down.",
        "😠 You seem annoyed — hope things settle soon.",
        "🧘 A calm moment can make a big difference.",
        "😠 It looks like something's bothering you — take your time.",
        "🌿 Even strong feelings pass — give yourself a moment.",
        "😠 You seem tense — stepping back can help.",
        "🧘 It's okay to pause before moving forward.",
        "😠 You look frustrated — hope the day smooths out.",
        "🌿 A short break can reset a tough moment.",
        "😠 You seem unsettled — take a steady breath.",
        "🧘 Calm focus can help regain balance.",
        "😠 It looks like a challenging moment — take it slowly.",
        "🌿 Not every moment needs an immediate response.",
        "😠 You seem irritated — wishing you some calm ahead.",
        "🧘 A composed step forward is still progress.",
        "😠 You look upset — hope things ease shortly.",
        "🌿 It's okay to reset before continuing.",
        "😠 You seem tense — slowing down might help.",
        "🧘 A moment of calm can change the tone.",
        "😠 It looks like frustration is present — take care.",
        "🌿 Pausing can bring clarity.",
        "😠 You seem bothered — hoping things improve.",
        "🧘 Calm decisions often come after a pause.",
        "😠 You look stressed — take a steady moment.",
        "🌿 Even tough moments can pass quietly.",
        "😠 You seem agitated — hoping for calmer minutes ahead.",
        "🧘 It's okay to collect your thoughts.",
        "😠 Someone woke up on the wrong side of the codebase.",
        "😏 Deep breaths — keyboards are innocent.",
        "😠 As they say, \"Anger solves nothing… except bugs.\" (sometimes)",
        "😏 Channeling main-character energy today?",
        "😠 Calm down — this isn't the final boss fight.",
        "😏 Looks like patience is on airplane mode.",
        "😠 Remember: even legends pause before reacting.",
        "😏 Today's mood says, \"Let me count to ten.\"",
        "😠 A wise proverb says: pause first, respond later.",
        "😏 That face says the meeting could have been an email.",
        "😠 Even heroes take a breather between battles.",
        "😏 Looks like the calm update is still loading.",
        "😠 Old saying: anger is loud, calm is powerful.",
        "😏 Someone's inner monologue is very active today.",
        "😠 Not every moment needs a dramatic soundtrack.",
        "😏 Take a breath — plot twist pending.",
        "😠 Proverb check: patience outlives frustration.",
        "😏 That look says, \"I need five minutes.\"",
        "😠 Even the strongest pause before acting.",
        "😏 Let's switch from reaction mode to wisdom mode.",
      ];
      // Use current time in milliseconds to get a random index
      final random = DateTime.now().millisecondsSinceEpoch % angryMessages.length;
      return angryMessages[random];
    }
    
    if (emotionLower == "surprise") {
      final surpriseMessages = [
        "😮 Well… that was not on the schedule.",
        "😏 Looks like the plan just updated itself.",
        "😮 Surprise! Nobody saw that coming.",
        "😏 That face says, \"Wait, what?\"",
        "😮 Plot twist detected.",
        "😏 Something just skipped the memo.",
        "😮 That was… unexpected.",
        "😏 Looks like today brought a bonus feature.",
        "😮 That expression says, \"Interesting.\"",
        "😏 The universe just pressed refresh.",
        "😮 That moment clearly wasn't rehearsed.",
        "😏 Looks like the script changed mid-scene.",
        "😮 Surprise unlocked.",
        "😏 Something just broke the routine.",
        "😮 That was a surprise, indeed.",
        "😏 Today decided to add a twist.",
        "😮 Didn't see that one coming.",
        "😏 That's a certified plot twist.",
        "😮 Well, that escalated quickly.",
        "😏 Looks like reality updated without notice.",
        "😮 That expression says, \"Oh… okay.\"",
        "😏 Surprise delivered — no warning included.",
        "😮 That moment just changed the plan.",
        "😏 Looks like expectations have shifted.",
        "😮 Unexpected, but noted.",
        "😏 The day just went off-script.",
        "😮 That reaction says everything.",
        "😏 Something new just entered the chat.",
        "😮 Surprise detected — processing…",
        "😏 Today chose unpredictability.",
        "😮 That was not in the handbook.",
        "😏 Looks like logic took a short break.",
        "😮 That was a surprise, alright.",
        "😏 The plot thickens.",
        "😮 Something just caught you off guard.",
        "😏 Looks like plans are flexible now.",
        "😮 Unexpected twist logged.",
        "😏 The schedule didn't see this coming.",
        "😮 That expression says, \"Well then.\"",
        "😏 Today decided to be interesting.",
        "😮 Surprise mode activated.",
        "😏 Reality just improvised.",
        "😮 That moment arrived unannounced.",
        "😏 Looks like the routine is optional today.",
        "😮 That was a curveball.",
        "😏 Something just rewrote the script.",
        "😮 Surprise acknowledged.",
        "😏 The unexpected just showed up.",
        "😮 That face says it all.",
        "😏 Looks like today had a sense of humor.",
      ];
      // Use current time in milliseconds to get a random index
      final random = DateTime.now().millisecondsSinceEpoch % surpriseMessages.length;
      return surpriseMessages[random];
    }
    
    if (emotionLower == "fear") {
      final fearMessages = [
        "😨 You seem uneasy — take a slow breath.",
        "🫶 It's okay to feel unsure — you're safe here.",
        "🌿 A moment of calm can help steady things.",
        "😨 You look anxious — take things one step at a time.",
        "🧘 Pause for a breath — you've got this.",
        "😨 It seems like a tense moment — slow down if needed.",
        "🌿 You're safe — take a moment to regroup.",
        "😨 You appear worried — it's okay to pause.",
        "🫶 Fear can pass — give yourself a moment.",
        "🌿 A steady breath can help right now.",
        "😨 You look uncertain — take things gently.",
        "🧘 It's okay to slow down and refocus.",
        "😨 You seem startled — give yourself time.",
        "🌿 Calm moments can bring clarity.",
        "😨 You appear tense — breathe and reset.",
        "🫶 You're not alone — take it step by step.",
        "😨 That looks like a nervous moment — it will pass.",
        "🌿 A pause can bring balance.",
        "😨 You seem uneasy — take a breath.",
        "🧘 Calm thoughts can steady the moment.",
        "😨 You look concerned — slow and steady is fine.",
        "🌿 It's okay to feel cautious sometimes.",
        "😨 You seem alert — take a moment to relax.",
        "🫶 Fear fades — patience helps.",
        "😨 You look tense — take things at your pace.",
        "🌿 A calm reset can help.",
        "😨 You appear anxious — breathe slowly.",
        "🧘 You're safe — no rush needed.",
        "😨 That looks like a startled reaction — it's okay.",
        "🌿 Gentle moments bring comfort.",
        "😨 You seem worried — take a steady breath.",
        "🫶 It's okay to pause before continuing.",
        "😨 You look nervous — slow steps are fine.",
        "🌿 Calmness can return quickly.",
        "😨 You seem unsettled — take a moment.",
        "🧘 A breath can help steady the moment.",
        "😨 You appear cautious — that's okay.",
        "🌿 Take a pause — things will settle.",
        "😨 You look tense — take care.",
        "🫶 Fear doesn't last forever.",
        "😨 You seem startled — breathe and reset.",
        "🌿 Calm moments help restore balance.",
        "😨 You look uneasy — it's okay to slow down.",
        "🧘 You're safe — take a steady breath.",
        "😨 You appear anxious — give yourself time.",
        "🌿 Calm focus can help right now.",
        "😨 You seem worried — breathe gently.",
        "🫶 It's okay to feel cautious today.",
        "😨 You look tense — things can ease.",
        "🌿 A calm pause can change the moment.",
      ];
      // Use current time in milliseconds to get a random index
      final random = DateTime.now().millisecondsSinceEpoch % fearMessages.length;
      return fearMessages[random];
    }
    
    if (emotionLower == "disgust") {
      final disgustMessages = [
        "🤢 That reaction says, \"Let's not do that again.\"",
        "😅 Something seems… less than ideal.",
        "🤢 That face suggests a quick reset might help.",
        "😅 Looks like that wasn't your favorite moment.",
        "🤢 Mild discomfort detected — noted and acknowledged.",
        "😅 That expression says, \"Hmm… no.\"",
        "🤢 Something felt off — totally understandable.",
        "😅 That reaction says, \"Let's move past this.\"",
        "🤢 A brief pause might improve the situation.",
        "😅 That didn't quite pass the vibe check.",
        "🤢 You look uncomfortable — time for a mental reset.",
        "😅 That moment clearly wasn't on the wish list.",
        "🤢 Something didn't sit right — it happens.",
        "😅 That face says, \"Okay, next.\"",
        "🤢 Mild discomfort logged — thanks for powering through.",
        "😅 That reaction suggests a change of scene might help.",
        "🤢 Looks like that wasn't the best experience.",
        "😅 That moment earned a quiet \"nope.\"",
        "🤢 You seem uneasy — let's move forward calmly.",
        "😅 That expression says, \"Let's pretend that didn't happen.\"",
        "🤢 Discomfort detected — nothing you can't handle.",
        "😅 That reaction was very… expressive.",
        "🤢 Something felt unpleasant — totally fair.",
        "😅 That face says, \"Could be better.\"",
        "🤢 A calm pause might help reset things.",
        "😅 That moment clearly missed expectations.",
        "🤢 You look unsettled — take it easy.",
        "😅 That reaction says, \"Alright, moving on.\"",
        "🤢 Something didn't feel right — no worries.",
        "😅 That expression suggests a strong opinion.",
        "🤢 Mild discomfort noted — thanks for your patience.",
        "😅 That face says, \"Let's not repeat that.\"",
        "🤢 You seem uncomfortable — it's okay to pause.",
        "😅 That reaction was very honest.",
        "🤢 Something felt off — let's reset.",
        "😅 That moment clearly wasn't ideal.",
        "🤢 You look unsettled — take a breath.",
        "😅 That face says, \"Lesson learned.\"",
        "🤢 Discomfort happens — you're handling it well.",
        "😅 That reaction says, \"Okay… noted.\"",
        "🤢 You seem uneasy — calm moments help.",
        "😅 That expression says, \"Could've skipped that.\"",
        "🤢 A small pause might improve things.",
        "😅 That moment didn't quite land.",
        "🤢 You look uncomfortable — steady now.",
        "😅 That face says, \"Let's keep going.\"",
        "🤢 Mild unease detected — all good.",
        "😅 That reaction was quietly expressive.",
        "🤢 Something felt unpleasant — it will pass.",
        "😅 That look says, \"Alright, next task.\"",
      ];
      // Use current time in milliseconds to get a random index
      final random = DateTime.now().millisecondsSinceEpoch % disgustMessages.length;
      return disgustMessages[random];
    }
    
    if (emotionLower == "neutral") {
      final neutralMessages = [
        "😐 You look settled and composed.",
        "😏 Mood successfully loading… still loading.",
        "😐 This is the face of \"everything is fine.\"",
        "😏 Neutral — the Switzerland of emotions.",
        "😐 Nothing to report. Literally.",
        "😏 Emotion status: undecided.",
        "😐 Perfectly balanced, as expected.",
        "😏 This look says, \"I'm here.\"",
        "😐 Calm. Stable. Unbothered.",
        "😏 Emotion took the day off.",
        "😐 Neither excited nor concerned — impressive.",
        "😏 Mood: default settings.",
        "😐 That's a very neutral expression.",
        "😏 Nothing's happening, and that's okay.",
        "😐 Emotion detected: standard edition.",
        "😏 This is peak emotional efficiency.",
        "😐 All systems running… normally.",
        "😏 You've mastered the art of neutrality.",
        "😐 Calm, collected, and undecided.",
        "😏 This face says, \"Proceed as usual.\"",
        "😐 No highs. No lows. Just vibes.",
        "😏 Emotion successfully avoided.",
        "😐 Steady expression — no updates required.",
        "😏 Mood set to \"default.\"",
        "😐 Nothing dramatic detected.",
        "😏 Emotion level: acceptable.",
        "😐 This is a very professional face.",
        "😏 You look… appropriately neutral.",
        "😐 Balanced enough to confuse everyone.",
        "😏 Neither impressed nor disappointed.",
        "😐 Emotion: present, but minimal.",
        "😏 This is the calm before… more calm.",
        "😐 Neutral mood confirmed — again.",
        "😏 Expression says, \"Okay.\"",
        "😐 You look emotionally budget-friendly.",
        "😏 No strong feelings were found.",
        "😐 Steady face, steady pace.",
        "😏 Emotion running in low-power mode.",
        "😐 Calm, quiet, and fully operational.",
        "😏 You've chosen the neutral path.",
        "😐 This expression has no spoilers.",
        "😏 Emotion detected, enthusiasm not included.",
        "😐 A very \"let's get on with it\" look.",
        "😏 Mood successfully unchanged.",
        "😐 Neutral — because why not.",
        "😏 Expression says, \"This is happening.\"",
        "😐 Emotion delivered without extras.",
        "😏 Nothing exciting, nothing alarming.",
        "😐 Calm enough to pass inspection.",
        "😏 Neutral mode engaged.",
      ];
      // Use current time in milliseconds to get a random index
      final random = DateTime.now().millisecondsSinceEpoch % neutralMessages.length;
      return neutralMessages[random];
    }
    
    // Fallback message for unknown emotions - random selection
    final defaultMessages = [
      "🙂 Have a great day!",
      "🌟 Wishing you a smooth and productive day.",
      "😊 Hope today goes well for you.",
      "🌤️ All set — have a good one!",
      "👍 You're good to go — enjoy your day.",
      "✨ Have a positive and steady day ahead.",
      "😊 Wishing you a calm and successful day.",
      "🌞 Hope today treats you well.",
      "👍 Everything's set — have a nice day.",
      "🌱 Take it easy and have a good day.",
      "😊 Ready to go — best of luck today.",
      "🌟 Wishing you a balanced and productive day.",
      "👍 You're all checked in — have a great day.",
      "🌤️ Hope today goes smoothly.",
      "😊 Sending good vibes for the day ahead.",
      "🌞 Have a pleasant and productive day.",
      "👍 All set — enjoy your day.",
      "✨ Wishing you a positive start today.",
      "😊 Hope your day is a good one.",
      "🌱 Take care and have a great day.",
      "👍 Everything looks good — have a nice day.",
      "🌟 Wishing you a smooth day ahead.",
      "😊 All done — enjoy your day.",
      "🌤️ Hope the rest of your day goes well.",
      "👍 You're good to go — make it a good day.",
      "✨ Have a calm and productive day.",
      "😊 Wishing you an easy and pleasant day.",
      "🌞 Hope today is kind to you.",
      "👍 All set — wishing you a great day.",
      "🌱 Have a steady and successful day.",
    ];
    // Use current time in milliseconds to get a random index
    final random = DateTime.now().millisecondsSinceEpoch % defaultMessages.length;
    return defaultMessages[random];
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
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
        // Auto-close after 30 seconds
        Future.delayed(const Duration(seconds: 30), () {
          if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AlertDialog(
          backgroundColor: const Color(0xFF1C1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: Color(0xFF72BF45),
              width: 2,
            ),
          ),
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
                  child: _safeImage(imageBase64, width: 200, height: 200),
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
                if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
                }
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
          ),
        );
      },
    );
  }

  void _showClockOutConfirmationDialog({
    required String imageBase64,
    required String employeeName,
    required String emotion,
    required double hoursWorked,
    required String clockTime,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AlertDialog(
          backgroundColor: const Color(0xFF1C1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: Colors.orange,
              width: 2,
            ),
          ),
          title: Text(
            "Confirm Clock Out",
            style: GoogleFonts.inter(
              color: Colors.orange,
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
                  child: _safeImage(imageBase64, width: 150, height: 150),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "You've only worked ${hoursWorked.toStringAsFixed(2)} hours today.",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Minimum working time is 5 hours.\n\nAre you sure you want to clock out?",
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              if (employeeName.isNotEmpty) ...[
                const SizedBox(height: 12),
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
              const SizedBox(height: 8),
              Text(
                clockTime,
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            // Cancel button
            TextButton(
              onPressed: () {
                if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
                }
                onCancel();
              },
              child: Text(
                "Cancel",
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Confirm button
            ElevatedButton(
              onPressed: () {
                if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
                }
                onConfirm();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(
                "Yes, Clock Out",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  void _showClockErrorDialog({
    required String imageBase64,
    required String message,
    bool isSpoof = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
        // Auto-close after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AlertDialog(
          backgroundColor: const Color(0xFF1C1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: Colors.redAccent,
              width: 2,
            ),
          ),
          title: Text(
            isSpoof ? "Spoof Detected" : "Face Not Identified",
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
                  child: _safeImage(imageBase64, width: 200, height: 200),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
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
                if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
                }
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
          ),
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
    _faceDetector.close();
  }

@override
  Widget build(BuildContext context) {
    final time = DateFormat('hh:mm:ss a').format(_now);
    final date = DateFormat('EEEE, dd MMMM').format(_now);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      bottomNavigationBar: const BottomNav(index: 1),
      body: SafeArea(
        // ⚡ INSTANT LOAD FIX: We removed the "_loading ? ..." check.
        // The UI now paints immediately. The camera box handles its own loading spinner.
        child: Column(
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

                    /// CAMERA (Internal Loader)
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
                            color: const Color(0xFF57C200).withOpacity(0.4),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        // ⚡ LOGIC: If camera is ready, show it. Else show spinner inside.
                        child: _controller != null &&
                                _controller!.value.isInitialized &&
                                _controller!.value.aspectRatio > 0
                            ? AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _controller!.value.previewSize?.height ?? 260,
                                    height: _controller!.value.previewSize?.width ?? 260,
                                    child: CameraPreview(
                                      _controller!,
                                      key: ValueKey(_controller!.description.name),
                                    ),
                                  ),
                                ),
                              )
                            : const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF72BF45),
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

  Widget _safeImage(String imageBase64,
      {double width = 200, double height = 200}) {
    if (imageBase64.isEmpty) {
      return const Icon(
        Icons.error_outline,
        size: 80,
        color: Colors.redAccent,
      );
    }

    try {
      return Image.memory(
        base64Decode(imageBase64),
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    } catch (_) {
      return const Icon(
        Icons.broken_image,
        size: 80,
        color: Colors.redAccent,
      );
    }
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

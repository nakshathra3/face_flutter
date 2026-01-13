import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:working_emu/models/attendance.dart';

import '../services/api_service.dart';
import '../services/json_storage_service.dart';
import '../models/employee.dart';
import '../widgets/bottom_nav.dart';
import 'package:http/http.dart' as http;

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;

  bool _loading = true;
  bool _countingDown = false;
  bool _processing = false;
  bool _isInitializing = false;

  int _countdown = 0;
  String _statusText = "";

  List<Attendance> _availableEmployees = [];
  Attendance? _selectedEmployee;
  String _searchQuery = "";
  String? _confirmedImageBase64; // Store confirmed image

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadEmployees();
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller != null && _controller!.value.isInitialized) {
      if (state == AppLifecycleState.inactive) {
        _controller!.dispose();
      } else if (state == AppLifecycleState.resumed) {
        if (!_isInitializing) {
          _initCamera();
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Properly dispose camera
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
    }
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      print("🔍 [ENROLL] Fetching employees from production API...");

      // Fetch from production API's active endpoint which has employee data with face_embedding
      final response = await http
          .get(Uri.parse("https://dev-workforce.dsignzmedia.com/api/active"))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception("Request timeout"),
          );

      print("🌐 [ENROLL] Response status: ${response.statusCode}");

      if (response.statusCode != 200) {
        throw Exception("Failed to fetch employees: ${response.statusCode}");
      }

      final decoded = jsonDecode(response.body);
      print("📊 [ENROLL] Response type: ${decoded.runtimeType}");

      List<dynamic> rawEmployees = [];
      List<dynamic> rawInterns = [];

      // Handle the API response structure: { "data": { "employees": [...], "interns": [...] } }
      if (decoded is Map && decoded['data'] is Map) {
        final data = decoded['data'] as Map;
        rawEmployees = data['employees'] ?? [];
        rawInterns = data['interns'] ?? [];
        print(
            "📊 [ENROLL] Found ${rawEmployees.length} employees and ${rawInterns.length} interns");
      } else if (decoded is List) {
        // Fallback: if it's a direct list
        rawEmployees = decoded;
        print("📊 [ENROLL] Found ${rawEmployees.length} items in list");
      } else if (decoded is Map && decoded['records'] is List) {
        rawEmployees = decoded['records'] as List;
        print("📊 [ENROLL] Found ${rawEmployees.length} records");
      }

      // Combine employees and interns
      final allRaw = [...rawEmployees, ...rawInterns];
      print(
          "📋 [ENROLL] Total loaded: ${allRaw.length} (${rawEmployees.length} employees + ${rawInterns.length} interns)");

      // Filter out employees who have face_embedding (they are enrolled)
      final unenrolledRaw = allRaw.where((emp) {
        final faceEmbedding = emp['face_embedding'];
        // If face_embedding is null, empty, or not present, employee is NOT enrolled
        final isEnrolled = faceEmbedding != null &&
            faceEmbedding.toString().trim().isNotEmpty &&
            faceEmbedding.toString() != 'null';

        if (isEnrolled) {
          print(
              "🚫 [ENROLL] Filtering out enrolled: ${emp['full_name'] ?? emp['name']} (${emp['code'] ?? emp['employee_id']})");
        }

        return !isEnrolled; // Only include if NOT enrolled
      }).toList();

      print(
          "📝 [ENROLL] ${unenrolledRaw.length} employees available for enrollment (${allRaw.length - unenrolledRaw.length} already enrolled)");

      // Convert filtered raw data to Attendance objects
      final unenrolledEmployees =
          unenrolledRaw.map((json) => Attendance.fromJson(json)).toList();

      setState(() {
        _availableEmployees = unenrolledEmployees;

        if (_availableEmployees.isNotEmpty && _selectedEmployee == null) {
          _selectedEmployee = _availableEmployees.first;
          print(
              "✅ [ENROLL] Selected first employee: ${_selectedEmployee!.name}");
        } else if (_availableEmployees.isEmpty) {
          _selectedEmployee = null;
          print("⚠️ [ENROLL] No employees available for enrollment");
        }
      });
    } catch (e, stackTrace) {
      print("❌ [ENROLL] Error loading employees: $e");
      print("❌ [ENROLL] Stack trace: $stackTrace");
      setState(() {
        _availableEmployees = [];
        _selectedEmployee = null;
      });

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load employees: ${e.toString()}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<Set<String>> _getEnrolledEmployeeIds() async {
    try {
      final ids = await ApiService.getEnrolledEmployeeIds();
      print("📊 Enrolled IDs from backend: $ids");
      return ids;
    } catch (e) {
      print("⚠️ Error getting enrolled IDs (backend may not be running): $e");
      // Return empty set so all employees show as available
      return {};
    }
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
          print("⚠️ [ENROLL] Error disposing old controller: $e");
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
        print("❌ [ENROLL] No cameras available");
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
        print("✅ [ENROLL] Camera initialized successfully");
      }
    } catch (e) {
      print("❌ [ENROLL] Error initializing camera: $e");
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

  List<Attendance> get _filteredEmployees {
    if (_searchQuery.isEmpty) {
      return _availableEmployees;
    }
    return _availableEmployees.where((emp) {
      final query = _searchQuery.toLowerCase();
      return emp.name.toLowerCase().contains(query) ||
          emp.code.toLowerCase().contains(query);
    }).toList();
  }

  void _startEnrollment() {
    if (_countingDown || _processing) return;

    // If image is already confirmed, proceed with enrollment
    if (_confirmedImageBase64 != null) {
      _confirmAndEnroll(_confirmedImageBase64!);
      return;
    }

    // Otherwise, start capture process
    setState(() {
      _countdown = 3;
      _countingDown = true;
      _statusText = "Get ready…";
    });

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 1) {
        timer.cancel();
        _captureAndEnroll();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _captureAndEnroll() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _countingDown = false;
      _processing = true;
    });

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final faceBase64 = base64Encode(bytes);

      if (!mounted) return;

      // Show preview dialog
      setState(() {
        _processing = false;
      });

      _showImagePreviewDialog(faceBase64);
    } catch (e) {
      if (!mounted) return;
      final errorMsg = "Error capturing image: ${e.toString()}";

      setState(() {
        _processing = false;
        _statusText = "❌ $errorMsg";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showImagePreviewDialog(String imageBase64) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1A1A),
        title: Text(
          "Preview Image",
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
                transform: Matrix4.identity()..scale(-1.0, 1.0), // Flip horizontally
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
              "Review your image. Does it look good?",
              style: GoogleFonts.inter(
                color: Colors.grey,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _confirmedImageBase64 =
                    null; // Clear confirmed image if retaking
              });
            },
            child: Text(
              "Retake",
              style: GoogleFonts.inter(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Store the confirmed image
              setState(() {
                _confirmedImageBase64 = imageBase64;
                _selectedEmployee =
                    null; // Reset selection when new image is confirmed
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF57C200),
              foregroundColor: Colors.white,
            ),
            child: Text(
              "Confirm",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndEnroll(String faceBase64) async {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an employee")),
      );
      return;
    }

    setState(() {
      _processing = true;
      _statusText = "Enrolling face…";
    });

    try {
      print(
          "🔄 Starting enrollment for: ${_selectedEmployee!.code} (${_selectedEmployee!.name})");
      print("📸 Image size: ${faceBase64.length} characters");

      final result = await ApiService.enrollEmployee(
        employeeId: _selectedEmployee!.code,
        name: _selectedEmployee!.name,
        faceBase64: faceBase64,
        uuid: _selectedEmployee!.uuid,
        user_type: _selectedEmployee!.user_type,
      );

      print("📥 Enrollment response: $result");

      if (!mounted) return;

      if (result["success"] == true) {
        // Remove from available list
        setState(() {
          _availableEmployees.removeWhere((emp) =>
              emp.uuid == _selectedEmployee!.uuid ||
              emp.code == _selectedEmployee!.code);
          _selectedEmployee = null; // Clear selection
          _searchQuery = "";
          _processing = false;
          _confirmedImageBase64 =
              null; // Clear confirmed image after successful enrollment
          _statusText = "✔ Enrollment successful";
        });

        // Reload the employee list to ensure it's up-to-date with backend
        await _loadEmployees();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✔ Enrollment successful"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorMessage = result["message"] ?? "Enrollment failed";
        setState(() {
          _processing = false;
          _statusText = "❌ $errorMessage";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print("from enrollment catch");
      if (!mounted) return;
      final errorMsg = e.toString().contains("timeout") ||
              e.toString().contains("Failed host lookup") ||
              e.toString().contains("Connection refused")
          ? "Cannot connect to backend server. Is it running?"
          : e.toString().replaceAll("Exception: ", "");

      setState(() {
        _processing = false;
        _statusText = "❌ $errorMsg";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reinitialize camera if not initialized and not currently initializing
    if (!_loading &&
        (_controller == null || !_controller!.value.isInitialized) &&
        !_isInitializing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isInitializing && _controller == null) {
          _initCamera();
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      bottomNavigationBar: const BottomNav(index: 2),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _mainContent(),
            ),
    );
  }

  // ================= MAIN CONTENT =================
  Widget _mainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleSection(),
          const SizedBox(height: 20),
          _cameraScanner(),
          const SizedBox(height: 24),
          _tipsCard(),
          const SizedBox(height: 24),
          // Show employee dropdown only after image is confirmed
          if (_confirmedImageBase64 != null) ...[
            _employeeCard(),
            const SizedBox(height: 24),
          ],
          _enrollButton(),
        ],
      ),
    );
  }

  // ================= EMPLOYEE CARD =================
  Widget _employeeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2D2A2A)),
      ),
      child: _availableEmployees.isEmpty
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  "All employees are enrolled!",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonHideUnderline(
                        child: DropdownButton<Attendance>(
                          value: _selectedEmployee,
                          hint: Text(
                            "Select Employee/Intern",
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          dropdownColor: const Color(0xFF1C1A1A),
                          icon: const Icon(Icons.expand_more,
                              color: Color(0xFF57C200)),
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                          items: _filteredEmployees.map((employee) {
                            return DropdownMenuItem<Attendance>(
                              value: employee,
                              child: Text(employee.name),
                            );
                          }).toList(),
                          onChanged: (Attendance? newValue) {
                            setState(() {
                              _selectedEmployee = newValue;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedEmployee != null) ...[
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedEmployee!.code,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _selectedEmployee!.type,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  // ================= TITLE =================
  Widget _titleSection() {
    return Column(
      children: [
        Text(
          "Position Your Face",
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        // const SizedBox(height: 8),
        // Text(
        //   "Center your face within the frame. Ensure good lighting and remove accessories.",
        //   textAlign: TextAlign.center,
        //   style: GoogleFonts.inter(
        //     fontSize: 13,
        //     color: Colors.grey,
        //   ),
        // ),
      ],
    );
  }

  // ================= CAMERA SCANNER =================
  Widget _cameraScanner() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 260,
            height: 260,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE0D8C8),
            ),
          ),
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE0D8C8), width: 4),
            ),
            clipBehavior: Clip.antiAlias,
            child: _controller != null && _controller!.value.isInitialized
                ? ClipOval(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller!.value.previewSize?.height ?? 240,
                          height: _controller!.value.previewSize?.width ?? 240,
                          child: CameraPreview(
                            _controller!,
                            key: ValueKey(_controller!.description.name),),
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black26,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
          ),
          if (_countingDown)
            Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
              ),
              child: Center(
                child: Text(
                  "$_countdown",
                  style: const TextStyle(
                    fontSize: 72,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_processing)
            Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
              ),
              child: Center(
                child: Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ================= TIPS =================
  Widget _tipsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info, color: Color(0xFF57C200)),
              SizedBox(width: 8),
              Text("Tips for success", style: TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 10),
          _tip("Hold your phone at eye level"),
          _tip("Avoid direct sunlight"),
          _tip("Keep a neutral expression"),
          _tip("Ensure good lighting"),
          _tip("Remove accessories"),
        ],
      ),
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ================= STATUS MESSAGE =================
  Widget _statusMessage() {
    final isSuccess =
        _statusText.contains("successful") || _statusText.contains("✔");
    final isError = _statusText.contains("Failed") ||
        _statusText.contains("❌") ||
        _statusText.contains("Error");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isSuccess
            ? Colors.green.shade900.withOpacity(0.3)
            : isError
                ? Colors.red.shade900.withOpacity(0.3)
                : const Color(0xFF1C1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess
              ? Colors.green.shade700
              : isError
                  ? Colors.red.shade700
                  : const Color(0xFF333333),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle
                : isError
                    ? Icons.error
                    : Icons.info,
            color: isSuccess
                ? Colors.green.shade400
                : isError
                    ? Colors.red.shade400
                    : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusText,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isSuccess
                    ? Colors.green.shade300
                    : isError
                        ? Colors.red.shade300
                        : Colors.grey.shade300,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= BUTTON =================
  Widget _enrollButton() {
    final hasConfirmedImage = _confirmedImageBase64 != null;
    final isEnabled = !_countingDown &&
        !_processing &&
        (!hasConfirmedImage ||
            (_selectedEmployee != null && _availableEmployees.isNotEmpty));

    String buttonText;
    if (_processing) {
      buttonText = "Processing...";
    } else if (_countingDown) {
      buttonText = "Get ready...";
    } else if (hasConfirmedImage) {
      buttonText = "Enroll Employee";
    } else {
      buttonText = "Capture Face";
    }

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isEnabled ? const Color(0xFF57C200) : Colors.grey.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: isEnabled ? 2 : 0,
      ),
      icon: _processing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              hasConfirmedImage ? Icons.person_add : Icons.camera_alt,
              color: Colors.white,
            ),
      label: Text(
        buttonText,
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      onPressed: isEnabled ? _startEnrollment : null,
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../services/api_service.dart';
import '../services/json_storage_service.dart';
import '../models/employee.dart';
import '../widgets/camera_preview_widget.dart';
import '../widgets/bottom_nav.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  CameraController? _controller;

  bool _loading = true;
  bool _countingDown = false;
  bool _processing = false;

  int _countdown = 0;
  String _statusText = "Select employee and tap Enroll";

  List<Employee> _availableEmployees = [];
  Employee? _selectedEmployee;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _initCamera();
  }

  Future<void> _loadEmployees() async {
    try {
      // Load from JSON file
      final employees = await JsonStorageService.loadEmployees();
      print("📋 Loaded ${employees.length} employees from JSON");

      // Fetch enrolled employees from backend
      final enrolledIds = await _getEnrolledEmployeeIds();
      print("✅ Found ${enrolledIds.length} enrolled employees: $enrolledIds");

      setState(() {
        // Filter out already enrolled employees
        _availableEmployees =
            employees.where((emp) => !enrolledIds.contains(emp.code)).toList();

        print(
            "📝 ${_availableEmployees.length} employees available for enrollment");

        if (_availableEmployees.isNotEmpty && _selectedEmployee == null) {
          _selectedEmployee = _availableEmployees.first;
        }
      });
    } catch (e) {
      print("❌ Error loading employees: $e");
      // If there's an error, still show employees (they just won't be filtered)
      try {
        final employees = await JsonStorageService.loadEmployees();
        setState(() {
          _availableEmployees = employees;
          if (_availableEmployees.isNotEmpty && _selectedEmployee == null) {
            _selectedEmployee = _availableEmployees.first;
          }
        });
      } catch (e2) {
        print("❌ Critical error: $e2");
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
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    _controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) {
      return _availableEmployees;
    }
    return _availableEmployees.where((emp) {
      final query = _searchQuery.toLowerCase();
      return emp.fullName.toLowerCase().contains(query) ||
          emp.code.toLowerCase().contains(query);
    }).toList();
  }

  void _startEnrollment() {
    if (_countingDown || _processing) return;

    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an employee")),
      );
      return;
    }

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
      _statusText = "Capturing image…";
    });

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final faceBase64 = base64Encode(bytes);

      if (!mounted) return;
      setState(() => _statusText = "Image captured ✓");

      await Future.delayed(const Duration(milliseconds: 400));

      setState(() => _statusText = "Processing face…");

      final success = await ApiService.enrollEmployee(
        employeeId: _selectedEmployee!.code,
        name: _selectedEmployee!.fullName,
        faceBase64: faceBase64,
      );

      if (!mounted) return;

      if (success) {
        // Remove from available list
        setState(() {
          _availableEmployees.remove(_selectedEmployee);
          if (_availableEmployees.isNotEmpty) {
            _selectedEmployee = _availableEmployees.first;
          } else {
            _selectedEmployee = null;
          }
          _searchQuery = "";
          _processing = false;
          _statusText = "✔ Enrollment successful";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✔ Enrollment successful"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _processing = false;
          _statusText = "❌ Failed to recognize";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Failed to recognize - Please use live camera"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().contains("timeout") ||
              e.toString().contains("Failed host lookup") ||
              e.toString().contains("Connection refused")
          ? "Cannot connect to backend server. Is it running?"
          : "Error: ${e.toString()}";

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
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Employee Enrollment"),
        centerTitle: true,
      ),
      bottomNavigationBar: const BottomNav(index: 2),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      CameraPreviewWidget(controller: _controller!),
                      if (_countingDown) _overlayText("$_countdown"),
                      if (_processing) _overlayText(_statusText),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _employeeSelector(),
                      const SizedBox(height: 14),
                      Text(
                        _statusText,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: (_countingDown ||
                                _processing ||
                                _selectedEmployee == null)
                            ? null
                            : _startEnrollment,
                        child: const Text("Enroll Employee"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _employeeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Employee",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        // Search field
        TextField(
          decoration: const InputDecoration(
            hintText: "Search by name or ID...",
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        const SizedBox(height: 8),
        // Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Employee>(
              isExpanded: true,
              value: _selectedEmployee,
              hint: const Text("Select employee..."),
              items: _filteredEmployees.map((employee) {
                return DropdownMenuItem<Employee>(
                  value: employee,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        employee.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "${employee.code} - ${employee.type}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (Employee? newValue) {
                setState(() {
                  _selectedEmployee = newValue;
                });
              },
            ),
          ),
        ),
        if (_availableEmployees.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "All employees are enrolled!",
              style: TextStyle(color: Colors.green[700]),
            ),
          ),
      ],
    );
  }

  Widget _overlayText(String text) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 42,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

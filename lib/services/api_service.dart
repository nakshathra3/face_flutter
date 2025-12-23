import 'dart:convert';
import 'package:http/http.dart' as http;
// import '../models/employee.dart' as Employee;
import '../models/employee.dart';
import '../models/attendance.dart';

class ApiService {
  // ⚠️ IMPORTANT: Update this IP address to match your computer's IP
  // Find your IP: Windows CMD -> ipconfig | findstr IPv4
  // For Android Emulator: use "http://10.0.2.2:5000"
  // For iOS Simulator: use "http://localhost:5000" or "http://127.0.0.1:5000"
  // For physical device on same network: use your computer's local IP (e.g., "http://192.168.x.x:5000")

  //static const String _baseUrl = "http://192.168.0.131:5000";
  // Updated IP addresses found: 192.168.56.1 (VirtualBox) or 192.168.29.91 (Main network)
  // For Android Emulator, change to: "http://10.0.2.2:5000"
  // static const String _baseUrl = "http://192.168.29.91:5000";
  // static const String _baseUrl = "https://workforceapi.dsignzmedia.com";
  static const String _baseUrl = "http://192.168.29.91:5000";

  static Future<Map<String, dynamic>> recognizeFace(
    String base64Image,
    String action,
  ) async {
    try {
      final response = await http
          .post(
        Uri.parse("$_baseUrl/recognize"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "image": base64Image,
          "action": action, // "in" or "out"
        }),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception("Request timeout. Check if backend is running.");
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          "matched": false,
          "message": "Server error: ${response.statusCode}",
        };
      }
    } catch (e) {
      // Handle network errors, timeouts, etc.
      String errorMessage = "Network error";
      if (e.toString().contains("Failed host lookup") ||
          e.toString().contains("Connection refused")) {
        errorMessage = "Cannot connect to server. Is backend running?";
      } else if (e.toString().contains("timeout")) {
        errorMessage = "Request timeout. Server may be slow.";
      } else {
        errorMessage = "Error: ${e.toString()}";
      }

      return {"matched": false, "message": errorMessage};
    }
  }

  static Future<List<Attendance>> fetchAttendance() async {
    try {
      final response =
          await http.get(Uri.parse("$_baseUrl/attendance")).timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception("Request timeout"),
              );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          return decoded.map((json) => Attendance.fromJson(json)).toList();
        }

        if (decoded is Map && decoded['records'] is List) {
          return (decoded['records'] as List)
              .map((json) => Attendance.fromJson(json))
              .toList();
        }

        return [];
      } else {
        return [];
      }
    } catch (e) {
      print("Error fetching attendance: $e");
      return [];
    }
  }

  static Future<Set<String>> getEnrolledEmployeeIds() async {
    try {
      final response =
          await http.get(Uri.parse("$_baseUrl/enrolled-ids")).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception("Request timeout");
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ids = data['enrolled_ids'] as List;
        return ids.map((id) => id.toString()).toSet();
      } else {
        return {};
      }
    } catch (e) {
      print("Error fetching enrolled IDs: $e");
      return {};
    }
  }

  static Future<Map<String, dynamic>> enrollEmployee({
    required String employeeId,
    required String name,
    required String faceBase64,
    required String uuid,
    required String user_type,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$_baseUrl/enroll"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "employee_id": employeeId,
          "name": name,
          "face": faceBase64,
          "uuid": uuid,
          "user_type": user_type,
        }),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception("Request timeout. Check if backend is running.");
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('data: $data');
        return {
          "success": data["success"] == true,
          "message": data["message"] ??
              (data["success"] == true
                  ? "Enrollment successful"
                  : "Enrollment failed"),
        };
      } else {
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage = errorData["message"] ?? "Enrollment failed";
          print("Enrollment failed with status: ${response.statusCode}");
          print("Response: ${response.body}");
          return {"success": false, "message": errorMessage};
        } catch (e) {
          return {
            "success": false,
            "message": "Server error: ${response.statusCode}",
          };
        }
      }
    } catch (e) {
      print("Enrollment error: $e");
      String errorMessage = "Network error";
      if (e.toString().contains("Failed host lookup") ||
          e.toString().contains("Connection refused")) {
        errorMessage = "Cannot connect to server. Is backend running?";
      } else if (e.toString().contains("timeout")) {
        errorMessage = "Request timeout. Server may be slow.";
      } else {
        errorMessage = e.toString().replaceAll("Exception: ", "");
      }
      return {"success": false, "message": errorMessage};
    }
  }
}

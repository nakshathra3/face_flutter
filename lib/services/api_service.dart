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
  //static const String _baseUrl = "http://192.168.29.91:5000";
  //static const String _baseUrl = "https://workforceapi.dsignzmedia.com";
  //static const String _baseUrl = "http://192.168.1.102:5000";
  static const String _baseUrl = "http://192.168.1.39:5000";

  static Future<Map<String, dynamic>> recognizeFace(
    String base64Image,
    String action,
  ) async {
    try {
      final url = Uri.parse("$_baseUrl/recognize");

      final response = await http
          .post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "image": base64Image,
          "action": action,
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
      // Use the direct API route
      const String apiUrl =
          "https://dev-workforce.dsignzmedia.com/api/attendance";
      print("🌐 [API] ========== FETCHING ATTENDANCE ==========");
      print("🌐 [API] Route: GET $apiUrl");

      final response = await http.get(Uri.parse(apiUrl)).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception("Request timeout"),
          );

      print("🌐 [API] Response status: ${response.statusCode}");
      print(
          "🌐 [API] Response body length: ${response.body.length} characters");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        print("📊 [API] Response type: ${decoded.runtimeType}");

        // Check if response has status field
        if (decoded is Map && decoded['status'] == true) {
          print("✅ [API] API returned success status");

          // Get the data object
          final data = decoded['data'];
          print("📊 [API] Data type: ${data.runtimeType}");

          if (data is Map) {
            // Extract employees and interns arrays
            final employees = data['employees'] ?? [];
            final interns = data['interns'] ?? [];
            final allRecords = [...employees, ...interns];

            print("📊 [API] ✅ Found data structure");
            print("📊 [API] Date in response: ${data['date']}");
            print(
                "📊 [API] Employees: ${employees.length}, Interns: ${interns.length}");
            print("📊 [API] Total records: ${allRecords.length}");

            if (allRecords.isNotEmpty) {
              print(
                  "📊 [API] Sample employee record keys: ${(employees.isNotEmpty ? employees[0] : {}).keys}");
              print(
                  "📊 [API] Sample intern record keys: ${(interns.isNotEmpty ? interns[0] : {}).keys}");
              if (employees.isNotEmpty) {
                print("📊 [API] Sample employee: ${employees[0]}");
              }
              if (interns.isNotEmpty) {
                print("📊 [API] Sample intern: ${interns[0]}");
              }
            }

            // Map all records to Attendance objects
            return allRecords.map((json) => Attendance.fromJson(json)).toList();
          } else if (data is List) {
            // If data is directly a list
            print("📊 [API] ✅ Data is a List with ${data.length} records");
            if (data.isNotEmpty) {
              print("📊 [API] Sample record: ${data[0]}");
            }
            return data.map((json) => Attendance.fromJson(json)).toList();
          } else {
            print("⚠️ [API] Unknown data structure: ${data.runtimeType}");
            return [];
          }
        } else if (decoded is Map && decoded['status'] == false) {
          print("❌ [API] API returned error status");
          print("❌ [API] Message: ${decoded['message']}");
          return [];
        }

        // Fallback: Handle if response doesn't have status field
        // Handle List response (direct array of attendance records)
        if (decoded is List) {
          print("📊 [API] ✅ Response is a List with ${decoded.length} records");
          if (decoded.isNotEmpty) {
            print("📊 [API] First record: ${decoded[0]}");
          }
          return decoded.map((json) => Attendance.fromJson(json)).toList();
        }

        // Handle Map with 'records' key
        if (decoded is Map && decoded['records'] is List) {
          final recordsList = decoded['records'] as List;
          print(
              "📊 [API] ✅ Found Map with 'records' key: ${recordsList.length} records");
          return recordsList.map((json) => Attendance.fromJson(json)).toList();
        }

        // Handle Map with 'data' key containing employees/interns (old structure)
        if (decoded is Map && decoded['data'] is Map) {
          final data = decoded['data'] as Map;
          final employees = data['employees'] ?? [];
          final interns = data['interns'] ?? [];
          final allRecords = [...employees, ...interns];
          print("📊 [API] ✅ Found Map with 'data' key");
          print(
              "📊 [API] Employees: ${employees.length}, Interns: ${interns.length}");
          return allRecords.map((json) => Attendance.fromJson(json)).toList();
        }

        // Unknown structure
        print("⚠️ [API] Unknown response structure");
        if (decoded is Map) {
          print("⚠️ [API] Map keys: ${decoded.keys}");
        }
        return [];
      } else {
        print("❌ [API] Request failed with status: ${response.statusCode}");
        print("❌ [API] Response body: ${response.body}");
        return [];
      }
    } catch (e, stackTrace) {
      print("❌ [API] Error fetching attendance: $e");
      print("❌ [API] Stack trace: $stackTrace");
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

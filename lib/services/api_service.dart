import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  //static const String _baseUrl = "http://192.168.0.131:5000";
  static const String _baseUrl = "http://192.168.172.140:5000";

  static Future<Map<String, dynamic>> recognizeFace(
  String base64Image,
  String action,
) async {
  final response = await http.post(
    Uri.parse("$_baseUrl/recognize"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "image": base64Image,
      "action": action, // "in" or "out"
    }),
  );

  return jsonDecode(response.body);
}


  static Future<List<dynamic>> fetchAttendance() async {
    final response = await http.get(
      Uri.parse("$_baseUrl/attendance"),
    );

    final data = jsonDecode(response.body);
    return data['records'];
  }
  static Future<bool> enrollEmployee({
  required String employeeId,
  required String name,
  required String faceBase64,
}) async {
  final response = await http.post(
    Uri.parse("$_baseUrl/enroll"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "employee_id": employeeId,
      "name": name,
      "face": faceBase64,
    }),
  );

  final data = jsonDecode(response.body);
  return data["success"] == true;
}

}

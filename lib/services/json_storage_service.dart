import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/employee.dart';

class JsonStorageService {
  static Future<List<Employee>> loadEmployees() async {
    final data = await rootBundle.loadString('assets/data/employees.json');
    final decoded = jsonDecode(data);
    return (decoded['employees'] as List)
        .map((e) => Employee.fromJson(e))
        .toList();
  }
}

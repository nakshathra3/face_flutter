import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/employee.dart';

class JsonStorageService {
  static Future<List<Employee>> loadEmployees() async {
    final data = await rootBundle.loadString('assets/data/employees.json');
    final decoded = jsonDecode(data);
    
    // Load both employees and interns
    final employees = (decoded['employees'] as List? ?? [])
        .map((e) => Employee.fromJson(e))
        .toList();
    
    final interns = (decoded['interns'] as List? ?? [])
        .map((e) => Employee.fromJson(e))
        .toList();
    
    // Combine both lists
    return [...employees, ...interns];
  }
}

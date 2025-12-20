class Employee {
  final String code;
  final String fullName;
  final String type; // "employee" or "intern"
  String lastEmotion;

  Employee({
    required this.code,
    required this.fullName,
    required this.type,
    this.lastEmotion = "",
  });

  // Getter for backward compatibility
  String get id => code;
  String get name => fullName;
  String get role => type;

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      code: json['code'] ?? '',
      fullName: json['full_name'] ?? '',
      type: json['type'] ?? 'employee',
      lastEmotion: json['last_emotion'] ?? "",
    );
  }

  Map<String, dynamic> toJson() => {
        "code": code,
        "full_name": fullName,
        "type": type,
        "last_emotion": lastEmotion,
      };
}

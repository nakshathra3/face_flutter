class Employee {
  final String id;
  final String name;
  final String role;
  String lastEmotion;

  Employee({
    required this.id,
    required this.name,
    required this.role,
    this.lastEmotion = "",
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'],
      name: json['name'],
      role: json['role'],
      lastEmotion: json['last_emotion'] ?? "",
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "role": role,
        "last_emotion": lastEmotion,
      };
}

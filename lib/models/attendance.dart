class Attendance {
  final String code;
  final String name;
  final String clock_in;
  final String clock_out;
  final String emotion;
  final String type;
  final String uuid;
  Attendance({
    required this.code,
    required this.name,
    required this.clock_in,
    required this.clock_out,
    required this.emotion,
    required this.type,
    required this.uuid,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      code: json['code'] ?? '',
      name: json['full_name'] ?? '',
      clock_in: json['clock_in'] ?? '',
      clock_out: json['clock_out'] ?? '',
      emotion: json['emotion'] ?? '',
      type: json['type'] ?? '',
      uuid: json['uuid'] ?? '',
    );
  }
}

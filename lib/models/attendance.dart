class Attendance {
  final String code;
  final String name;
  final String clock_in;
  final String clock_out;
  final String emotion;
  final String type;
  final String uuid;
  final String user_type;
  final String date;
  final String status;
  Attendance({
    required this.code,
    required this.name,
    required this.clock_in,
    required this.clock_out,
    required this.emotion,
    required this.type,
    required this.uuid,
    required this.user_type,
    required this.date,
    this.status = '',
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    // Handle both field name variants (clock_in_time/clock_in, clock_out_time/clock_out)
    dynamic clockInRaw = json['clock_in_time'] ?? json['clock_in'];
    dynamic clockOutRaw = json['clock_out_time'] ?? json['clock_out'];

    // Convert to string and handle null/string 'null' values
    String clockIn = '';
    String clockOut = '';

    if (clockInRaw != null && clockInRaw.toString() != 'null') {
      clockIn = clockInRaw.toString();
    }
    if (clockOutRaw != null && clockOutRaw.toString() != 'null') {
      clockOut = clockOutRaw.toString();
    }

    return Attendance(
      code: json['code'] ?? json['employee_id'] ?? '',
      name: json['full_name'] ?? json['name'] ?? '',
      clock_in: clockIn,
      clock_out: clockOut,
      emotion: json['emotion'] ?? '',
      type: json['type'] ?? '',
      uuid: json['uuid'] ?? json['user_id'] ?? '',
      user_type: json['user_type'] ?? '',
      date: json['date'] ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

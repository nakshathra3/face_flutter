import 'package:flutter/material.dart';
import 'dart:async'; // Add this import for Timer
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _records = [];
  bool _loading = true;
  DateTime _currentTime = DateTime.now(); // Add current time state
  Timer? _timer; // Add timer for live updates

  static const bgBase = Color(0xFF000000);
  static const bgSurface = Color(0xFF1C1A1A);
  static const primary = Color(0xFF57C200);
  static const secondary = Color(0xFF72BF45);
  static const textMuted = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    // Start timer to update clock every second
    _startClockTimer();
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel timer when widget is disposed
    super.dispose();
  }

  // Start timer to update clock every second
  void _startClockTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  // Format time with seconds (HH:MM:SS)
  String _formatTimeWithSeconds(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return "$hour:$minute:$second";
  }

  Future<void> _loadAttendance() async {
    try {
      print("🔍 [HOME] Fetching attendance data...");
      final data = await ApiService.fetchAttendance();
      print("📊 [HOME] Fetched ${data.length} total records from API");

      // Get today's date in YYYY-MM-DD format
      final today = DateTime.now();
      final todayStr =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      print("📅 [HOME] Today's date string: $todayStr");

      // Debug: Print sample records to see date format
      if (data.isNotEmpty) {
        print("🔍 [HOME] Sample records (first 5) to check date format:");
        for (int i = 0; i < (data.length > 5 ? 5 : data.length); i++) {
          final record = data[i];
          print("  Record $i:");
          print("    - name: ${record.name}");
          print(
              "    - date: '${record.date}' (type: ${record.date.runtimeType}, length: ${record.date.length})");
          print("    - clock_in: '${record.clock_in}'");
          print("    - clock_out: '${record.clock_out}'");
        }
      }

      // Filter to only show today's records - SHOW ALL records for today
      // Fetch by DATE only, not by employee/intern category
      final todayRecords = <dynamic>[];
      for (final record in data) {
        try {
          final recordDate = record.date;

          // Debug each record's date
          print(
              "🔍 [HOME] Checking record: name='${record.name}', date='$recordDate'");

          // Normalize date strings for comparison (handle different formats)
          String normalizedRecordDate = recordDate.trim();
          String normalizedTodayDate = todayStr.trim();

          // Try exact match first
          bool matches = normalizedRecordDate == normalizedTodayDate;

          // If no match, try parsing and comparing dates
          if (!matches && normalizedRecordDate.isNotEmpty) {
            try {
              // Try to parse the record date
              DateTime? recordDateTime;

              // Try different date formats
              if (normalizedRecordDate.contains("T")) {
                // ISO format with time
                recordDateTime =
                    DateTime.tryParse(normalizedRecordDate.split("T")[0]);
              } else if (normalizedRecordDate.contains(" ")) {
                // Date with time
                recordDateTime =
                    DateTime.tryParse(normalizedRecordDate.split(" ")[0]);
              } else {
                // Just date
                recordDateTime = DateTime.tryParse(normalizedRecordDate);
              }

              if (recordDateTime != null) {
                final recordDateOnly =
                    "${recordDateTime.year}-${recordDateTime.month.toString().padLeft(2, '0')}-${recordDateTime.day.toString().padLeft(2, '0')}";
                matches = recordDateOnly == normalizedTodayDate;
                print("  📅 Parsed date: $recordDateOnly, matches: $matches");
              }
            } catch (e) {
              print("  ⚠️ Error parsing date: $e");
            }
          }

          if (matches) {
            todayRecords.add(record);
            print(
                "✅ [HOME] MATCH! Added record: ${record.name} - Clock In: ${record.clock_in}, Clock Out: ${record.clock_out}");
          } else {
            print(
                "  ❌ No match (record date: '$recordDate' vs today: '$todayStr')");
          }
        } catch (e) {
          print("⚠️ [HOME] Error processing record: $e");
          print("⚠️ [HOME] Record: $record");
        }
      }

      print(
          "📊 [HOME] Total records: ${data.length}, Today's records: ${todayRecords.length}");

      // If no records found, show all available dates for debugging
      if (todayRecords.isEmpty && data.isNotEmpty) {
        print(
            "⚠️ [HOME] No records found for today. Available dates in database:");
        final dateSet = <String>{};
        for (final record in data) {
          if (record.date.isNotEmpty) {
            dateSet.add(record.date);
          }
        }
        for (final date in dateSet) {
          print("  - $date");
        }
      }

      // Sort by most recent activity (clock-in or clock-out, whichever is more recent)
      // Most recent entries appear at the top
      final sortedData = todayRecords
        ..sort((a, b) {
          try {
            // Get the most recent timestamp for each record
            DateTime? mostRecentA = _getMostRecentTimestamp(a, todayStr);
            DateTime? mostRecentB = _getMostRecentTimestamp(b, todayStr);

            // If both have timestamps, compare them (most recent first)
            if (mostRecentA != null && mostRecentB != null) {
              return mostRecentB.compareTo(mostRecentA);
            }
            // Records with timestamps come before those without
            if (mostRecentA != null) return -1;
            if (mostRecentB != null) return 1;
            return 0;
          } catch (e) {
            print("⚠️ [HOME] Error sorting: $e");
            return 0;
          }
        });

      print(
          "📊 [HOME] Showing ${sortedData.length} records for today, sorted by most recent activity");

      setState(() {
        _records = sortedData; // Show ALL today's records
        _loading = false;
      });
    } catch (e, stackTrace) {
      print("❌ [HOME] Error loading attendance: $e");
      print("❌ [HOME] Stack trace: $stackTrace");
      setState(() => _loading = false);
    }
  }

  // Helper to get the most recent timestamp (clock-in or clock-out)
  DateTime? _getMostRecentTimestamp(dynamic record, String dateStr) {
    DateTime? clockInTime;
    DateTime? clockOutTime;

    try {
      if (record.clock_in.isNotEmpty && record.clock_in != "null") {
        final clockInStr = "$dateStr ${record.clock_in}";
        clockInTime = _parseDateTime(clockInStr);
      }

      if (record.clock_out.isNotEmpty &&
          record.clock_out != "null" &&
          record.clock_out.trim().isNotEmpty) {
        final clockOutStr = "$dateStr ${record.clock_out}";
        clockOutTime = _parseDateTime(clockOutStr);
      }
    } catch (e) {
      print("⚠️ Error getting timestamp: $e");
    }

    // Return the most recent timestamp
    if (clockInTime != null && clockOutTime != null) {
      return clockOutTime.isAfter(clockInTime) ? clockOutTime : clockInTime;
    }
    return clockOutTime ?? clockInTime;
  }

  // Helper to parse date-time string
  DateTime? _parseDateTime(String dateTimeStr) {
    try {
      // Try ISO format first
      DateTime? parsed = DateTime.tryParse(dateTimeStr.replaceAll(" ", "T"));
      if (parsed != null) return parsed;

      // Try manual parsing: "YYYY-MM-DD HH:MM:SS" or "YYYY-MM-DD HH:MM"
      final parts = dateTimeStr.split(" ");
      if (parts.length == 2) {
        final dateParts = parts[0].split("-");
        final timeParts = parts[1].split(":");
        if (dateParts.length == 3 && timeParts.length >= 2) {
          return DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
            timeParts.length > 2 ? int.parse(timeParts[2]) : 0,
          );
        }
      }
    } catch (e) {
      print("⚠️ Error parsing date-time '$dateTimeStr': $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgBase,
      bottomNavigationBar: const BottomNav(index: 0),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 420, // matches max-w-md
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadAttendance,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 16),
                        _buildClockCard(),
                        const SizedBox(height: 16),
                        _buildThoughtCard(),
                        const SizedBox(height: 24),
                        _buildRecentActivity(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ───────────────── HEADER ─────────────────

  Widget _buildHeader() {
    final now = DateTime.now();
    final date = "${_weekday(now.weekday)}, ${now.day} ${_month(now.month)}";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(date,
              style: const TextStyle(
                  color: textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(_getGreeting(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
        ]),
        const CircleAvatar(
          radius: 22,
          backgroundColor: bgSurface,
          child: Icon(Icons.person, color: Colors.white),
        ),
      ],
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return "Good Morning";
    } else if (hour < 16) {
      return "Good Afternoon";
    } else {
      return "Good Evening";
    }
  }

  // ───────────────── CLOCK CARD ─────────────────

  Widget _buildClockCard() {
    // Use the live current time
    final timeString = _formatTimeWithSeconds(_currentTime);

    return _glassCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.circle, size: 8, color: primary),
              SizedBox(width: 6),
              Text("Ready to Clock In",
                  style:
                      TextStyle(color: primary, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 12),
          // Live clock with seconds
          Text(
            timeString,
            style: const TextStyle(
                fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text("Office Time Zone",
              style: TextStyle(color: textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  // ───────────────── THOUGHT CARD ─────────────────

  Widget _buildThoughtCard() {
    return _glassCard(
      child: Column(
        children: const [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, color: primary, size: 18),
              SizedBox(width: 6),
              Text("THOUGHT OF THE DAY",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
          SizedBox(height: 10),
          Text(
            "Success is the sum of small efforts repeated day in and day out.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ───────────────── ACTIVITY LIST ─────────────────

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Recent Activity",
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ..._records.map(_buildActivityItem),
      ],
    );
  }

  Widget _buildActivityItem(dynamic r) {
    final clockInRaw = r.clock_in;
    final clockOutRaw = r.clock_out;
    final hasClockIn = clockInRaw.isNotEmpty;
    final hasClockOut = clockOutRaw.isNotEmpty &&
        clockOutRaw != "null" &&
        clockOutRaw.trim().isNotEmpty;
    print("🎯 [HOME] hasClockIn: $hasClockIn, hasClockOut: $hasClockOut");
    // Determine status: Present or Absent
    String status;
    Color statusColor;

    if (hasClockIn) {
      status = "Present";
      statusColor = primary;
    } else {
      status = "Absent";
      statusColor = Colors.grey;
    }

    // Format time display - ALWAYS show both times if clocked out
    String timeDisplay;
    if (!hasClockIn) {
      timeDisplay = "-";
    } else {
      // Extract HH:MM from clock_in (handle both "HH:MM:SS" and "HH:MM" formats)
      final clockInTimeParts = r.clock_in.split(":");
      final clockInTime = clockInTimeParts.length >= 2
          ? clockInTimeParts.take(2).join(":")
          : r.clock_in;

      if (hasClockOut) {
        // ALWAYS show both clock-in and clock-out times when clocked out
        final clockOutTimeParts = r.clock_out.split(":");
        final clockOutTime = clockOutTimeParts.length >= 2
            ? clockOutTimeParts.take(2).join(":")
            : r.clock_out;
        timeDisplay = "$clockInTime - $clockOutTime";
      } else {
        // Only clock-in (not clocked out yet)
        timeDisplay = "$clockInTime -";
      }
    }
    print("🎯 [HOME] Final timeDisplay: '$timeDisplay', status: '$status'");

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(children: [
              const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeDisplay,
                        style: const TextStyle(color: textMuted, fontSize: 12),
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          )
        ],
      ),
    );
  }

  // ───────────────── HELPERS ─────────────────

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgSurface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 4))
        ],
      ),
      child: child,
    );
  }

  String _weekday(int d) =>
      ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][d - 1];
  String _month(int m) => [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec"
      ][m - 1];
}

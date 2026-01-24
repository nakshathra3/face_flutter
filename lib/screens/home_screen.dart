import 'package:flutter/material.dart';
import 'dart:async'; // Add this import for Timer
import '../services/api_service.dart';
import '../models/attendance.dart';
import '../widgets/bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List<dynamic> _records = [];
  bool _loading = true;
  DateTime _currentTime = DateTime.now(); // Add current time state
  Timer? _timer; // Add timer for live updates
  String _thoughtDescription = "Success is the sum of small efforts repeated day in and day out.";
  String _thoughtName = "";
  late AnimationController _bellAnimationController;
  late Animation<double> _bellAnimation;
  late Animation<double> _bellOpacityAnimation;

  static const bgBase = Color(0xFF000000);
  static const bgSurface = Color(0xFF1C1A1A);
  static const primary = Color(0xFF57C200);
  static const secondary = Color(0xFF72BF45);
  static const textMuted = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    _loadNoticeboard();
    // Start timer to update clock every second
    _startClockTimer();
    // Initialize bell animation - pulsing "emerging arches" effect
    _bellAnimationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(); // No reverse for a constant outward pulse
    
    _bellAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _bellAnimationController,
        curve: Curves.easeOut,
      ),
    );
    
    _bellOpacityAnimation = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(
        parent: _bellAnimationController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel timer when widget is disposed
    _bellAnimationController.dispose(); // Dispose bell animation controller
    super.dispose();
  }

  // Start timer to update clock every second and refresh notification card
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

  Future<void> _handleRefresh() async {
    await Future.wait([
      _loadAttendance(),
      _loadNoticeboard(),
    ]);
  }

  Future<void> _loadAttendance() async {
    try {
      print("🔍 [HOME] Fetching roster and attendance...");
      final results = await Future.wait([
        ApiService.fetchFullRoster(),
        ApiService.fetchAttendance(),
      ]);

      final roster = results[0] as List<Attendance>;
      final activities = results[1] as List<Attendance>;

      print("📊 [HOME] Roster: ${roster.length}, Activities today: ${activities.length}");

      final today = DateTime.now();
      final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      // Map activities by employee ID (uuid or code)
      final activityMap = <String, Attendance>{};
      for (var act in activities) {
        if (act.date.contains(todayStr)) {
          activityMap[act.uuid.isNotEmpty ? act.uuid : act.code] = act;
        }
      }

      // Merge roster with activities
      final mergedRows = <dynamic>[];
      for (var emp in roster) {
        final activity = activityMap[emp.uuid.isNotEmpty ? emp.uuid : emp.code];
        if (activity != null) {
          mergedRows.add(activity);
        } else {
          // Absent employee - create a placeholder record
          mergedRows.add({
            'name': emp.name,
            'code': emp.code,
            'uuid': emp.uuid,
            'type': emp.type, // Added role
            'clock_in': '',
            'clock_out': '',
            'date': todayStr,
            'isAbsentPlaceholder': true, // Meta flag
          });
        }
      }

      // Sorting Logic: Priority (WFH during hours > Present > Absent)
      final now = DateTime.now();
      final isWFHWindow = now.hour >= 10 && now.hour < 19;

      mergedRows.sort((a, b) {
        int getPriority(dynamic r) {
          String bStatus = '';
          String cIn = '';
          if (r is Attendance) {
            bStatus = r.status.toLowerCase();
            cIn = r.clock_in;
          } else if (r is Map) {
            bStatus = (r['status'] ?? '').toString().toLowerCase();
            cIn = r['clock_in'] ?? '';
          }
          
          final isWFH = bStatus == "work_from_home";
          
          if (isWFH && isWFHWindow) return 0; // WFH during hours (Top)
          if (cIn.isNotEmpty && !isWFH) return 1; // Present at office
          if (isWFH && !isWFHWindow) return 2; // WFH outside hours
          return 3; // Absent
        }

        final pA = getPriority(a);
        final pB = getPriority(b);

        if (pA != pB) return pA.compareTo(pB);

        // Within same priority, sort by role (employee before intern) then alphabetical/time
        if (pA < 3) {
          // For active priorities: sort by most recent activity
          final timeA = _getMostRecentTimestamp(a, todayStr) ?? DateTime(2000);
          final timeB = _getMostRecentTimestamp(b, todayStr) ?? DateTime(2000);
          if (timeA != timeB) return timeB.compareTo(timeA);
        }
        
        // Final tier sorting (Absent or Activity with same timestamp)
        final String typeA = (a is Attendance) ? a.type : (a is Map ? a['type'] : '');
        final String typeB = (b is Attendance) ? b.type : (b is Map ? b['type'] : '');
        
        // Group by role: "employee" before "intern"
        if (typeA.toLowerCase() != typeB.toLowerCase()) {
           return typeA.toLowerCase().compareTo(typeB.toLowerCase());
        }

        final String nameA = (a is Attendance) ? a.name : (a is Map ? a['name'] : '');
        final String nameB = (b is Attendance) ? b.name : (b is Map ? b['name'] : '');
        return nameA.compareTo(nameB);
      });

      setState(() {
        _records = mergedRows;
        _loading = false;
      });
    } catch (e, stackTrace) {
      print("❌ [HOME] Error loading attendance: $e");
      print("❌ [HOME] Stack trace: $stackTrace");
      setState(() => _loading = false);
    }
  }

  Future<void> _loadNoticeboard() async {
    try {
      print("🔍 [HOME] Fetching noticeboard data...");
      final data = await ApiService.fetchNoticeboard();
      if (data != null) {
        setState(() {
          _thoughtDescription = data['description'] ?? _thoughtDescription;
          _thoughtName = data['name'] ?? "";
        });
        print("✅ [HOME] Noticeboard loaded: ${data['description']} by ${data['name']}");
      } else {
        print("⚠️ [HOME] No noticeboard data received");
      }
    } catch (e) {
      print("❌ [HOME] Error loading noticeboard: $e");
    }
  }

  // Helper to get the most recent timestamp (clock-in or clock-out)
  DateTime? _getMostRecentTimestamp(dynamic r, String dateStr) {
    DateTime? clockInTime;
    DateTime? clockOutTime;

    try {
      if (r is Map && r['isAbsentPlaceholder'] == true) return null;

      String cIn = (r is Attendance) ? r.clock_in : (r is Map ? r['clock_in'] : '');
      String cOut = (r is Attendance) ? r.clock_out : (r is Map ? r['clock_out'] : '');

      if (cIn.isNotEmpty && cIn != "null") {
        String clockInStr = cIn;

        // Check if clock_in already contains full date-time (e.g., "2026-01-08 13:22")
        if (!clockInStr.contains(dateStr)) {
          // If not, prepend the date
          clockInStr = "$dateStr $clockInStr";
        }

        clockInTime = _parseDateTime(clockInStr);
      }

      if (cOut.isNotEmpty &&
          cOut != "null" &&
          cOut.trim().isNotEmpty) {
        String clockOutStr = cOut;

        // Check if clock_out already contains full date-time
        if (!clockOutStr.contains(dateStr)) {
          // If not, prepend the date
          clockOutStr = "$dateStr $clockOutStr";
        }

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
                    onRefresh: _handleRefresh,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

  String _getFormattedDate() {
    final now = DateTime.now();
    final weekday = _weekday(now.weekday);
    final day = now.day;
    final month = _month(now.month);
    final year = now.year;
    return "$weekday, $day $month $year";
  }

  // ───────────────── CLOCK CARD ─────────────────

  Widget _buildClockCard() {
    // Use the live current time
    final timeString = _formatTimeWithSeconds(_currentTime);

    return _glassCard(
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Live clock with seconds
          Text(
            timeString,
            style: const TextStyle(
                fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _getFormattedDate(),
            style: const TextStyle(color: textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ───────────────── THOUGHT CARD ─────────────────

  Widget _buildThoughtCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgSurface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primary,
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  // Static inner bell
                  const Icon(Icons.notifications_rounded,
                      color: primary, size: 18),
                  // Pulsing outward arches
                  AnimatedBuilder(
                    animation: _bellAnimationController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _bellOpacityAnimation.value,
                        child: Transform.scale(
                          scale: _bellAnimation.value,
                          child: const Icon(Icons.notifications_active_rounded,
                              color: primary, size: 18),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Text("NOTIFICATION",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _thoughtDescription,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (_thoughtName.isNotEmpty) ...[
            const SizedBox(height: 8),
          Text(
              "— $_thoughtName",
            textAlign: TextAlign.center,
              style: const TextStyle(
                color: textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
          ),
          ],
        ],
      ),
    );
  }

  // ───────────────── ACTIVITY LIST ─────────────────

  Widget _buildRecentActivity() {
    debugPrint("DEBUG_LIST: Building activity list with ${_records.length} records");
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
    final String employeeName = (r is Attendance) ? r.name : (r is Map ? r['name'] : '');
    String clockInRaw = '';
    String clockOutRaw = '';
    if (r is Attendance) {
      clockInRaw = r.clock_in;
      clockOutRaw = r.clock_out;
    } else if (r is Map) {
      clockInRaw = r['clock_in'] ?? '';
      clockOutRaw = r['clock_out'] ?? '';
    }

    final hasClockIn = clockInRaw.isNotEmpty;
    final hasClockOut = clockOutRaw.isNotEmpty &&
        clockOutRaw != "null" &&
        clockOutRaw.trim().isNotEmpty;

    // Determine status: Present, WFH, or Absent
    String status;
    Color statusColor;

    String backendStatus = '';
    if (r is Attendance) {
      backendStatus = r.status.toLowerCase();
    } else if (r is Map) {
      backendStatus = (r['status'] ?? '').toString().toLowerCase();
    }

    if (backendStatus == "work_from_home") {
      status = "WFH";
      statusColor = Colors.blue;
    } else if (hasClockIn) {
      status = "Present";
      statusColor = primary;
    } else {
      status = "Absent";
      statusColor = Colors.grey;
    }

    // Move this logic to the end

    // Format time display - ALWAYS show both times if clocked out
    String timeDisplay;
    if (!hasClockIn) {
      timeDisplay = "-";
    } else {
      // Extract HH:MM from clock_in (handle both "HH:MM:SS" and "HH:MM" formats)
      final clockInTimeParts = clockInRaw.split(":");
      final clockInTime = clockInTimeParts.length >= 2
          ? clockInTimeParts.take(2).join(":")
          : clockInRaw;

      if (hasClockOut) {
        // ALWAYS show both clock-in and clock-out times when clocked out
        final clockOutTimeParts = clockOutRaw.split(":");
        final clockOutTime = clockOutTimeParts.length >= 2
            ? clockOutTimeParts.take(2).join(":")
            : clockOutRaw;
        timeDisplay = "$clockInTime - $clockOutTime";
      } else {
        // Only clock-in (not clocked out yet)
        timeDisplay = "$clockInTime -";
      }
    }
    // --- STATIC OVERRIDE FOR TESTING (Easy to remove) ---
    final List<String> _plannedLeaveNames = ["Abinaya S"];
    final List<String> _sickLeaveNames = ["Naveen JD"];
    final List<String> _firstHalfNames = ["Naveenya Mohanraj"];
    final List<String> _secondHalfNames = ["Nandhakishore P B"];

    bool matches(List<String> list) =>
        list.any((name) => name.trim().toLowerCase() == employeeName.trim().toLowerCase());

    if (matches(_plannedLeaveNames)) {
      status = "Planned Leave";
      statusColor = Colors.orange;
    } else if (matches(_sickLeaveNames)) {
      status = "Sick Leave";
      statusColor = Colors.red;
    } else if (matches(_firstHalfNames)) {
      status = "First Half";
      statusColor = Colors.purple;
    } else if (matches(_secondHalfNames)) {
      status = "Second Half";
      statusColor = Colors.teal;
    }
    // ----------------------------------------------------

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
                        (r is Attendance) ? r.name : (r is Map ? r['name'] : ''),
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

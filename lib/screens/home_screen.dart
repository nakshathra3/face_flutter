import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../models/attendance.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Data State
  List<Attendance> _activeRecords = [];
  bool _isLoadingActivity = true;
  bool _isPageLoading = true;

  DateTime _currentTime = DateTime.now();
  Timer? _timer;

  // Notification Data
  String _noticeMessage = "";
  String _noticeAuthor = "";
  bool _isApiNotification = false;
  String? _eventMessage;

  // ✅ ADD THIS LIST OF 30 QUOTES
  final List<String> _fallbackQuotes = [
    "Success is the sum of small efforts repeated day in and day out.",
    "The only way to do great work is to love what you do.",
    "Quality means doing it right when no one is looking.",
    "Believe you can and you're halfway there.",
    "Don't watch the clock; do what it does. Keep going.",
    "The future depends on what you do today.",
    "Opportunities don't happen. You create them.",
    "Success is not final, failure is not fatal: It is the courage to continue that counts.",
    "Hard work beats talent when talent doesn't work hard.",
    "It always seems impossible until it's done.",
    "Dream big and dare to fail.",
    "Your attitude, not your aptitude, will determine your altitude.",
    "Whatever you are, be a good one.",
    "If you want to lift yourself up, lift up someone else.",
    "Act as if what you do makes a difference. It does.",
    "Success usually comes to those who are too busy to be looking for it.",
    "Don't be afraid to give up the good to go for the great.",
    "I find that the harder I work, the more luck I seem to have.",
    "The secret of getting ahead is getting started.",
    "Focus on being productive instead of busy.",
    "Excellence is not a skill. It is an attitude.",
    "The way to get started is to quit talking and begin doing.",
    "Your limitation—it's only your imagination.",
    "Push yourself, because no one else is going to do it for you.",
    "Great things never come from comfort zones.",
    "Dream it. Wish it. Do it.",
    "Success doesn’t just find you. You have to go out and get it.",
    "The harder you work for something, the greater you’ll feel when you achieve it.",
    "Dream bigger. Do bigger.",
    "Don’t stop when you’re tired. Stop when you’re done.",
    "Work hard in silence, let your success be your noise."
  ];

  @override
  void initState() {
    super.initState();

    // ⚡ CHANGED: Use Day of Month to pick the quote (Consistent for the whole day)
    final int quoteIndex = DateTime.now().day % _fallbackQuotes.length;
    _noticeMessage = _fallbackQuotes[quoteIndex];

    // 1. Bell Animation
    _bellController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    
    _bellAnimation = Tween<double>(begin: -0.3, end: 0.3).animate(
      CurvedAnimation(parent: _bellController, curve: Curves.easeInOutSine),
    );

    // 2. Cake Animation
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: -1, end: -4).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOut),
    );

    _startClockTimer();
    _initialLoad(); // Ensure you are calling _initialLoad or _refreshData here
  }
  
  // Carousel Index
  int _currentMsgIndex = 0; 

  // Animations
  late AnimationController _bellController;
  late Animation<double> _bellAnimation;

  late AnimationController _bounceController; // ⚡ NEW: For Cake Jump
  late Animation<double> _bounceAnimation;

  static const bgBase = Color(0xFF000000);
  static const bgSurface = Color(0xFF1C1A1A);
  static const primary = Color(0xFF57C200);
  static const secondary = Color(0xFF72BF45);
  static const textMuted = Color(0xFF9CA3AF);

  // ⚡ NEW FUNCTION
  Future<void> _initialLoad() async {
    await _refreshData();
    if (mounted) {
      setState(() {
        _isPageLoading = false; // Hide full screen loader
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshData();
  }

  Future<void> _refreshData() async {
    await Future.wait([  
      _loadCelebrations(),
      _loadNoticeboard(),
      _loadRecentActivity(),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bellController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _startClockTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
        
        // ⚡ REFRESH CARD EVERY SECOND
        _loadNoticeboard(); 
        // Note: We don't call _loadCelebrations() every second as the list is huge,
        // but checking the noticeboard is lighter.
      }
    });
  }

  String _formatTimeWithSeconds(DateTime dateTime) {
    return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}";
  }

  // --- DATA LOADING ---

  Future<void> _loadCelebrations() async {
    try {
      final response = await http.get(
        Uri.parse('https://dev-workforce.dsignzmedia.com/api/active'),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        final data = jsonResponse['data'];
        
        List<dynamic> allEmployees = [];
        if (data is Map) {
          allEmployees = [...?data['employees'], ...?data['interns']];
        } else if (data is List) {
          allEmployees = data;
        }

        final List<Attendance> fullList = allEmployees
            .map((item) => Attendance.fromJson(item))
            .toList();

        String? calculatedEvent = _calculateTomorrowEvents(fullList);
        
        if (mounted) {
          setState(() {
            _eventMessage = calculatedEvent;
            // If event found, switch to it immediately
            if (_eventMessage != null) _currentMsgIndex = 0;
          });
        }
      }
    } catch (e) {
      print("⚠️ Celebration check failed: $e");
    }
  }

  Future<void> _loadRecentActivity() async {
    try {
      print("🔍 [HOME] Fetching full activity list (Multiple Entries allowed)...");
      
      // 1. Fetch Today's Attendance (Contains multiple entries per person)
      final List<dynamic> attendanceRaw = await ApiService.fetchAttendance();
      final List<Attendance> attendanceList = attendanceRaw
          .where((item) => item is Attendance || item is Map)
          .map((item) => item is Attendance ? item : Attendance.fromJson(item))
          .toList();

      // Collect UUIDs of everyone who is Present/WFH today
      final Set<String> presentUuids = attendanceList
          .map((e) => e.uuid)
          .where((id) => id.isNotEmpty)
          .toSet();

      // 2. Fetch ALL Active Employees (To find Absentees)
      final response = await http.get(Uri.parse('https://dev-workforce.dsignzmedia.com/api/active'));
      List<Attendance> allEmployees = [];
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        final data = jsonResponse['data'];
        List<dynamic> rawList = [];
        if (data is Map) {
          rawList = [...?data['employees'], ...?data['interns']];
        } else if (data is List) {
          rawList = data;
        }
        allEmployees = rawList.map((item) => Attendance.fromJson(item)).toList();
      }

      // 3. Create the Combined List
      // Start with ALL attendance records (Present/WFH) - Keeps duplicates/multiple sessions
      final combinedList = List<Attendance>.from(attendanceList);

      // Add Absentees (People in Active list who are NOT in presentUuids)
      for (var emp in allEmployees) {
        if (!presentUuids.contains(emp.uuid)) {
          // This person has 0 records today, so they are Absent
          combinedList.add(emp);
        }
      }

      // 4. Sort: Present/WFH at Top (by Time), Absent at Bottom (Alphabetical)
      combinedList.sort((a, b) {
         // Get latest time for A
         String timeA = (a.clock_out.isNotEmpty && a.clock_out != "null" && a.clock_out != "00:00:00") 
             ? a.clock_out : a.clock_in;
         // Get latest time for B
         String timeB = (b.clock_out.isNotEmpty && b.clock_out != "null" && b.clock_out != "00:00:00") 
             ? b.clock_out : b.clock_in;

         bool isPresentA = timeA.isNotEmpty && timeA != "null" && timeA != "00:00:00";
         bool isPresentB = timeB.isNotEmpty && timeB != "null" && timeB != "00:00:00";

         if (isPresentA && !isPresentB) return -1; // A is Present, B is Absent -> A goes up
         if (!isPresentA && isPresentB) return 1;  // A is Absent, B is Present -> B goes up

         if (isPresentA && isPresentB) {
            // Both Present: Sort by latest time descending (Newest first)
            return timeB.compareTo(timeA);
         } else {
            // Both Absent: Sort by Name alphabetical
            return a.name.compareTo(b.name);
         }
      });

      if (mounted) {
        setState(() {
          _activeRecords = combinedList;
          _isLoadingActivity = false;
        });
      }
    } catch (e) {
      print("❌ Activity Error: $e");
      if (mounted) setState(() => _isLoadingActivity = false);
    }
  }

  Future<void> _loadNoticeboard() async {
    try {
      final data = await ApiService.fetchNoticeboard();
      if (data != null && mounted) {
        String? apiMessage = data['description'];
        String? apiAuthor = data['name'];

        setState(() {
          if (apiMessage != null && apiMessage.trim().isNotEmpty) {
            // Real Notification from API
            _noticeMessage = apiMessage;
            _noticeAuthor = apiAuthor ?? "";
            _isApiNotification = true;
          } else {
            // ⚡ CHANGED: Fallback to Daily Quote (if API is empty)
            _isApiNotification = false;
            final int quoteIndex = DateTime.now().day % _fallbackQuotes.length;
            _noticeMessage = _fallbackQuotes[quoteIndex];
            _noticeAuthor = "";
          }
        });
      }
    } catch (e) {
      // ⚡ CHANGED: Error Fallback (Use Daily Quote)
      if (mounted && (_noticeMessage.isEmpty || _isApiNotification)) {
        setState(() {
           _isApiNotification = false;
           final int quoteIndex = DateTime.now().day % _fallbackQuotes.length;
           _noticeMessage = _fallbackQuotes[quoteIndex];
        });
      }
    }
  }

  String? _calculateTomorrowEvents(List<Attendance> employees) {
    if (employees.isEmpty) return null;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    List<String> events = [];

    for (var emp in employees) {
      String? dobStr = emp.dob;
      String? dojStr = emp.dateOfJoining;
      String name = emp.name;

      if (dojStr != null && dojStr.isNotEmpty && dojStr != "null") {
        try {
          final doj = DateTime.parse(dojStr);
          if (doj.month == tomorrow.month && doj.day == tomorrow.day) {
            int years = tomorrow.year - doj.year;
            if (years > 0) {
              String firstName = name.split(" ")[0];
              String suffix = _getOrdinalSuffix(years);
              events.add("$firstName has $years$suffix anniversary");
            }
          }
        } catch (_) {}
      }

      if (dobStr != null && dobStr.isNotEmpty && dobStr != "null") {
        try {
          final dob = DateTime.parse(dobStr);
          if (dob.month == tomorrow.month && dob.day == tomorrow.day) {
            String firstName = name.split(" ")[0];
            events.add("$firstName has birthday");
          }
        } catch (_) {}
      }
    }

    if (events.isEmpty) return null;
    return "Tomorrow ${events.join(' and ')}";
  }

  String _getOrdinalSuffix(int number) {
    if (number % 100 >= 11 && number % 100 <= 13) return 'th';
    switch (number % 10) {
      case 1: return 'st year';
      case 2: return 'nd year';
      case 3: return 'rd year';
      default: return 'th year';
    }
  }

  // --- WIDGET BUILD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgBase,
      bottomNavigationBar: const BottomNav(index: 0),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 420,
            child: _isPageLoading 
              ? const Center(child: CircularProgressIndicator(color: primary)) // ⚡ SHOW THIS ON STARTUP
              : RefreshIndicator(
                  onRefresh: _refreshData,
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

  // ───────────────── DYNAMIC CARD WITH JUMPING CAKE ─────────────────
  Widget _buildThoughtCard() {
    List<Map<String, String>> messages = [];
    
    // 1. Event (Highest Priority)
    if (_eventMessage != null) {
      messages.add({"msg": _eventMessage!, "author": "Celebrations", "type": "event"});
    }
    
    // 2. Notice / Thought
    messages.add({"msg": _noticeMessage, "author": _noticeAuthor.isNotEmpty ? "— $_noticeAuthor" : "", "type": "notice"});

    if (_currentMsgIndex >= messages.length) _currentMsgIndex = 0;
    final item = messages[_currentMsgIndex];
    final type = item['type'];

    // ⚡ DETERMINE UI STYLE BASED ON TYPE
    String titleText = "";
    IconData iconData = Icons.notifications; // Default
    Color iconColor = primary;
    Color borderColor = primary;
    Widget iconWidget;

    if (type == 'event') {
      titleText = "CELEBRATION";
      iconData = Icons.cake;
      iconColor = Colors.blue;
      borderColor = Colors.blue;
      
      // Jumping Cake Animation
      iconWidget = AnimatedBuilder(
        animation: _bounceAnimation,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _bounceAnimation.value),
          child: Icon(iconData, color: iconColor, size: 20),
        ),
      );
    } 
    else { // type == 'notice'
      if (_isApiNotification) {
        // 🔔 REAL NOTIFICATION
        titleText = "NOTIFICATION";
        iconData = Icons.notifications;
        iconColor = primary; // Green
        borderColor = primary;

        // Swinging Bell Animation
        iconWidget = AnimatedBuilder(
          animation: _bellAnimation,
          builder: (context, child) => Transform.rotate(
            angle: _bellAnimation.value,
            alignment: Alignment.topCenter,
            child: Icon(iconData, color: iconColor, size: 20),
          ),
        );
      } else {
        // 💡 THOUGHT OF THE DAY (Fallback)
        titleText = "THOUGHT OF THE DAY";
        iconData = Icons.lightbulb; // Changed Icon
        iconColor = Colors.amber;   // Changed Color
        borderColor = Colors.amber;

        // Static or Pulse (No Swing for Lightbulb)
        iconWidget = Icon(iconData, color: iconColor, size: 20);
      }
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (messages.length > 1) {
          setState(() {
            _currentMsgIndex = (_currentMsgIndex + 1) % messages.length;
          });
        }
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: bgSurface.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 2), // Dynamic Border Color
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 4))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconWidget, // ⚡ Dynamic Icon Widget
                  const SizedBox(width: 8),
                  Text(
                    titleText, // ⚡ Dynamic Title
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: iconColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item['msg']!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
              ),
              if (item['author']!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item['author']!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: textMuted, fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
              
              // Dots Indicator
              if (messages.length > 1) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(messages.length, (index) {
                    bool isActive = index == _currentMsgIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 12 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? borderColor : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Recent Activity", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_isLoadingActivity) 
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: primary)))
        else if (_activeRecords.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No activity yet today", style: TextStyle(color: textMuted))))
        else
          ..._activeRecords.map(_buildActivityItem),
      ],
    );
  }

  Widget _buildActivityItem(Attendance r) {
    String name = r.name;
    String clockIn = r.clock_in;
    String clockOut = r.clock_out;
    
    final hasClockIn = clockIn.isNotEmpty && clockIn != "null" && clockIn != "00:00:00";
    final hasClockOut = clockOut.isNotEmpty && clockOut != "null" && clockOut != "00:00:00";
    
    // 1. STATUS LOGIC
    String status = "Absent"; // Default
    Color statusColor = Colors.redAccent.withOpacity(0.8); // Default Red for Absent

    if (r.status == "work_from_home") { 
      status = "WFH";
      statusColor = Colors.blue; 
    } else if (hasClockIn) {
      status = "Present";
      statusColor = primary;
    }

    // 2. TIME FORMAT LOGIC
    String timeDisplay = "-";
    if (hasClockIn) {
      try {
        final DateTime inDt = DateTime.parse(clockIn); 
        final String datePart = "${inDt.year}-${inDt.month.toString().padLeft(2,'0')}-${inDt.day.toString().padLeft(2,'0')}";
        final String startTime = "${inDt.hour.toString().padLeft(2,'0')}:${inDt.minute.toString().padLeft(2,'0')}";
        
        timeDisplay = "$datePart $startTime";

        if (hasClockOut) {
          final DateTime outDt = DateTime.parse(clockOut);
          final String endTime = "${outDt.hour.toString().padLeft(2,'0')}:${outDt.minute.toString().padLeft(2,'0')}";
          timeDisplay += " - $endTime";
        } else {
          timeDisplay += " -";
        }
      } catch (e) {
        timeDisplay = clockIn; 
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bgSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(children: [
              const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(timeDisplay, style: const TextStyle(color: textMuted, fontSize: 12)),
              ])),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
            decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(999)), 
            child: Text(status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600))
          )
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_getGreeting(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ]),
        const CircleAvatar(radius: 22, backgroundColor: bgSurface, child: Icon(Icons.person, color: Colors.white)),
      ],
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning";
    if (hour < 16) return "Good Afternoon";
    return "Good Evening";
  }

  Widget _buildClockCard() {
    final timeString = _formatTimeWithSeconds(_currentTime);
    final now = DateTime.now();
    final dateStr = "${_weekday(now.weekday)}, ${now.day} ${_month(now.month)} ${now.year}";

    return _glassCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: primary.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.circle, size: 8, color: primary),
              SizedBox(width: 6),
              Text("Ready to Clock In", style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 12),
          Text(timeString, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(dateStr, style: const TextStyle(color: textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgSurface.withOpacity(0.9), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 4))]),
      child: child,
    );
  }

  String _weekday(int d) => ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][d - 1];
  String _month(int m) => ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1];
}
import 'package:flutter/material.dart';
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

  static const bgBase = Color(0xFF000000);
  static const bgSurface = Color(0xFF1C1A1A);
  static const primary = Color(0xFF57C200);
  static const secondary = Color(0xFF72BF45);
  static const textMuted = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    try {
      final data = await ApiService.fetchAttendance();
      setState(() {
        _records = data.reversed.toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
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
    final date =
        "${_weekday(now.weekday)}, ${now.day} ${_month(now.month)}";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(date,
              style: const TextStyle(
                  color: textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text("Good Morning",
              style: TextStyle(
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

  // ───────────────── CLOCK CARD ─────────────────

  Widget _buildClockCard() {
    final now = TimeOfDay.now();

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
                  style: TextStyle(
                      color: primary, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            "${now.format(context)}",
            style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white),
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
    final isOut = r["clock_out"] != null;

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
          Row(children: [
            const CircleAvatar(
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r["name"],
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
              Text(
                isOut
                    ? "Checked out • ${r["clock_out"]}"
                    : "Checked in • ${r["clock_in"]}",
                style: const TextStyle(color: textMuted, fontSize: 12),
              ),
            ]),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isOut ? Colors.blue : primary).withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isOut ? "Completed" : "On Time",
              style: TextStyle(
                  color: isOut ? Colors.blue : primary,
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
          BoxShadow(
              color: Colors.black54, blurRadius: 20, offset: Offset(0, 4))
        ],
      ),
      child: child,
    );
  }

  String _weekday(int d) =>
      ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][d - 1];
  String _month(int m) =>
      ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1];
}

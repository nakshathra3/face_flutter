import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/clock_screen.dart';
import '../screens/enrollment_screen.dart';
import '../theme/app_theme.dart';

class BottomNav extends StatelessWidget {
  final int index;
  const BottomNav({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: index,
      backgroundColor: AppTheme.surface,
      selectedItemColor: AppTheme.primary,
      unselectedItemColor: Colors.grey,
      onTap: (i) {
        if (i == index) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => i == 0
                ? const HomeScreen()
                : i == 1
                    ? const ClockScreen()
                    : const EnrollmentScreen(),
          ),
        );
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.schedule), label: "Clock"),
        BottomNavigationBarItem(icon: Icon(Icons.group), label: "Enroll"),
      ],
    );
  }
}

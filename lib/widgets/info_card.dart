import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class InfoCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String status;

  const InfoCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.muted, fontSize: 12)),
              ],
            ),
          ),
          Text(status, style: const TextStyle(color: AppTheme.primary))
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final String label;

  const StatusChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: AppTheme.primary.withOpacity(0.15),
      labelStyle: const TextStyle(color: AppTheme.primary),
    );
  }
}

import 'package:flutter/material.dart';

// StudentDashboardActivityTile displays a recent activity with icon, title, and subtitle.
class StudentDashboardActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const StudentDashboardActivityTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: colorScheme.surface,
      shadowColor: colorScheme.shadow.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary,
          child: Icon(icon, color: colorScheme.onPrimary),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
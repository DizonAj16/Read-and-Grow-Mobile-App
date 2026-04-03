import 'package:flutter/material.dart';

class StudentDashboardHorizontalCard extends StatelessWidget {
  final String title;
  final String value;
  final List<Color> gradientColors;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? textColor;

  const StudentDashboardHorizontalCard({
    Key? key,
    required this.title,
    required this.value,
    required this.gradientColors,
    required this.icon,
    this.onPressed,
    this.iconColor,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Use provided colors or fallback to theme-appropriate colors
    final effectiveIconColor = iconColor ?? colorScheme.onPrimary;
    final effectiveTextColor = textColor ?? colorScheme.onPrimary;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      shadowColor: colorScheme.shadow.withOpacity(0.3),
      color: Colors.transparent, // Make card transparent to show gradient
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        splashColor: effectiveTextColor.withOpacity(0.2),
        highlightColor: Colors.transparent,
        child: Container(
          width: 170,
          height: 150,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.1, 0.9],
            ),
            borderRadius: BorderRadius.circular(20),
            // Optional: Add subtle border for depth
            border: Border.all(
              color: effectiveTextColor.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: effectiveTextColor.withOpacity(0.95),
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.w800,
                        color: effectiveTextColor,
                        height: 0.9,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: effectiveTextColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: effectiveTextColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 40,
                      color: effectiveIconColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
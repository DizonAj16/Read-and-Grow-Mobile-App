import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class EmptyClassesWidget extends StatelessWidget {
  final VoidCallback onJoinClassPressed;
  final VoidCallback onRefreshPressed;

  const EmptyClassesWidget({
    Key? key,
    required this.onJoinClassPressed,
    required this.onRefreshPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.1),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEmptyAnimation(),
            _buildTitleText(colorScheme),
            const SizedBox(height: 12),
            _buildDescriptionText(colorScheme),
            const SizedBox(height: 12),
            _buildActionButtons(theme, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAnimation() {
    return SizedBox(
      width: 220,
      height: 220,
      child: Lottie.asset(
        'assets/animation/empty_box.json',
        fit: BoxFit.contain,
        repeat: true,
      ),
    );
  }

  Widget _buildTitleText(ColorScheme colorScheme) {
    return Text(
      "No Classrooms Yet!",
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: colorScheme.primary,
        height: 1.3,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDescriptionText(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        'Ask your teacher for a class code then tap the '
        '"Join Class" button below! 👇',
        style: TextStyle(
          fontSize: 16,
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: onJoinClassPressed,
          icon: const Icon(Icons.school, size: 22),
          label: const Text(
            "Join Class Now",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
            shadowColor: colorScheme.primary.withOpacity(0.3),
          ),
        ),
        TextButton.icon(
          onPressed: onRefreshPressed,
          icon: Icon(
            Icons.refresh,
            color: colorScheme.primary,
            size: 20,
          ),
          label: Text(
            "Try Again",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
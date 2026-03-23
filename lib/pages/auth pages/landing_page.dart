import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../widgets/appbar/theme_toggle_button.dart';
import '../../widgets/navigation/page_transition.dart';
import '../auth pages/parent/parent_signup_page.dart';
import '../auth pages/student/student_signup_page.dart';
import '../auth pages/teacher/teacher_signup_page.dart';
import 'choose_role_page.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kBackgroundAsset =
    'assets/background/480681008_1020230633459316_6070422237958140538_n.jpg';
const _kLottieAsset = 'assets/animation/hello.json';

const _kStudentIconPath = 'assets/icons/graduating-student.png';
const _kTeacherIconPath = 'assets/icons/teacher.png';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Holds configuration for a single sign-up button.
class _SignUpButtonConfig {
  const _SignUpButtonConfig({
    required this.label,
    required this.page,
    required this.backgroundColor,
    required this.foregroundColor,
    this.iconPath,
    this.icon,
  }) : assert(
          iconPath != null || icon != null,
          'Must provide either iconPath or icon',
        );

  final String label;
  final Widget page;
  final Color backgroundColor;
  final Color foregroundColor;

  /// Path to an image asset icon. Mutually exclusive with [icon].
  final String? iconPath;

  /// A pre-built icon widget. Mutually exclusive with [iconPath].
  final Widget? icon;
}

// ---------------------------------------------------------------------------
// LandingPage
// ---------------------------------------------------------------------------

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _LandingBackground(),
          _LandingScrollContent(),
          const _ThemeToggleOverlay(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

class _LandingBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.primary.withOpacity(0.7),
        BlendMode.softLight,
      ),
      child: Opacity(
        opacity: 0.25,
        child: Image.asset(
          _kBackgroundAsset,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}

class _ThemeToggleOverlay extends StatelessWidget {
  const _ThemeToggleOverlay();

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      top: 40,
      right: 16,
      child: ThemeToggleButton(iconColor: Colors.white),
    );
  }
}

class _LandingScrollContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 80),
          const _HeroAnimation(),
          const _HeroText(),
          const SizedBox(height: 40),
          _ActionCard(),
        ],
      ),
    );
  }
}

class _HeroAnimation extends StatelessWidget {
  const _HeroAnimation();

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      _kLottieAsset,
      height: 360,
      fit: BoxFit.contain,
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Read & Grow',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Mobile Reading App For Elementary School Learners',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withOpacity(0.92),
              ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WelcomeSection(),
            const SizedBox(height: 32),
            const _LoginButton(),
            const SizedBox(height: 24),
            _SignUpButtonList(),
          ],
        ),
      ),
    );
  }
}

class _WelcomeSection extends StatelessWidget {
  const _WelcomeSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Start your reading journey today with our platform.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                height: 1.4,
              ),
        ),
      ],
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => Navigator.push(
        context,
        PageTransition(page: const ChooseRolePage(isLoginFlow: true)),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 3,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        'Login',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SignUpButtonList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final buttons = <_SignUpButtonConfig>[
      _SignUpButtonConfig(
        label: 'Sign up as Student',
        iconPath: _kStudentIconPath,
        page: const StudentSignUpPage(),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      _SignUpButtonConfig(
        label: 'Sign up as Teacher',
        iconPath: _kTeacherIconPath,
        page: const TeacherSignUpPage(),
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
      ),
      _SignUpButtonConfig(
        label: 'Sign up as Parent',
        icon: const Icon(Icons.family_restroom, size: 32),
        page: const ParentSignUpPage(),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
      ),
    ];

    return Column(
      children: buttons
          .map(
            (config) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SignUpButton(config: config),
            ),
          )
          .toList(),
    );
  }
}

class _SignUpButton extends StatelessWidget {
  const _SignUpButton({required this.config});

  final _SignUpButtonConfig config;

  Widget _resolveIcon() {
    if (config.icon != null) return config.icon!;
    return Image.asset(config.iconPath!, width: 32, height: 32);
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () =>
          Navigator.push(context, PageTransition(page: config.page)),
      icon: _resolveIcon(),
      label: Text(
        config.label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: config.backgroundColor,
        foregroundColor: config.foregroundColor,
        elevation: 3,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        minimumSize: const Size(double.infinity, 64),
      ),
    );
  }
}
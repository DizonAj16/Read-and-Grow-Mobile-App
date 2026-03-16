import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../constants.dart';
import '../../widgets/appbar/theme_toggle_button.dart';
import '../../widgets/navigation/page_transition.dart';
import '../auth pages/parent/parent_signup_page.dart';
import '../auth pages/student/student_signup_page.dart';
import '../auth pages/teacher/teacher_signup_page.dart';
import 'choose_role_page.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background layer
          _buildBackground(context),

          // Main scrollable content
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 80),
                _buildHeaderAnimation(),
                _buildHeaderText(context),
                const SizedBox(height: 40),

                // Action card
                Container(
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
                        _buildWelcomeSection(context),
                        const SizedBox(height: 32),
                        _buildLoginButton(context),
                        const SizedBox(height: 24),
                        _buildSignUpButtons(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Theme toggle
          Positioned(
            top: 40,
            right: 16,
            child: ThemeToggleButton(iconColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.primary.withOpacity(0.7),
        BlendMode.softLight,
      ),
      child: Opacity(
        opacity: 0.25,
        child: Image.asset(
          'assets/background/480681008_1020230633459316_6070422237958140538_n.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }

  Widget _buildHeaderAnimation() {
    return Lottie.asset(
      'assets/animation/hello.json',
      height: 360,
      fit: BoxFit.contain,
    );
  }

  Widget _buildHeaderText(BuildContext context) {
    return Column(
      children: [
        Text(
          "Read & Grow",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          "Mobile Reading App For Elementary School Learners",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withOpacity(0.92),
              ),
        ),
        // const SizedBox(height: 6),
        // Text(
        //   kAppVersion,
        //   style: Theme.of(context).textTheme.bodySmall?.copyWith(
        //         color: Colors.white70,
        //         letterSpacing: 1.1,
        //       ),
        // ),
      ],
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome",
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          "Start your reading journey today with our platform.",
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                height: 1.4,
              ),
        ),
      ],
    );
  }

  Widget _buildLoginButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        Navigator.push(
          context,
          PageTransition(page: const ChooseRolePage(isLoginFlow: true)),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 3,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        "Login",
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildSignUpButtons(BuildContext context) {
    final buttons = [
      _SignUpButtonConfig(
        label: "Sign up as Student",
        iconPath: 'assets/icons/graduating-student.png',
        page: const StudentSignUpPage(),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      _SignUpButtonConfig(
        label: "Sign up as Teacher",
        iconPath: 'assets/icons/teacher.png',
        page: const TeacherSignUpPage(),
        backgroundColor: Theme.of(context).colorScheme.secondary,
        foregroundColor: Theme.of(context).colorScheme.onSecondary,
      ),
      _SignUpButtonConfig(
        label: "Sign up as Parent",
        icon: const Icon(Icons.family_restroom, size: 32),
        page: const ParentSignUpPage(),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
      ),
    ];

    return Column(
      children: buttons
          .asMap()
          .entries
          .map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildSignUpButton(context, entry.value),
              ))
          .toList(),
    );
  }

  Widget _buildSignUpButton(BuildContext context, _SignUpButtonConfig config) {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(context, PageTransition(page: config.page));
      },
      icon: config.icon ??
          Image.asset(
            config.iconPath!,
            width: 32,
            height: 32,
          ),
      label: Text(
        config.label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
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

class _SignUpButtonConfig {
  final String label;
  final String? iconPath;
  final Widget? icon;
  final Widget page;
  final Color backgroundColor;
  final Color foregroundColor;

  _SignUpButtonConfig({
    required this.label,
    this.iconPath,
    this.icon,
    required this.page,
    required this.backgroundColor,
    required this.foregroundColor,
  }) : assert(iconPath != null || icon != null, "Must provide either iconPath or icon");
}
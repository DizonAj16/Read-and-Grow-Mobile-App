import 'package:flutter/material.dart';

import '../../widgets/navigation/page_transition.dart';
import '../auth pages/login_page.dart';
import '../auth pages/student/student_signup_page.dart';
import '../auth pages/teacher/teacher_signup_page.dart';

enum RoleType {
  student,
  teacher,
  admin,
  parent,
}

class RoleOption {
  final RoleType type;
  final IconData icon;
  final String label;
  final Color color;
  final Widget destinationPage;

  const RoleOption({
    required this.type,
    required this.icon,
    required this.label,
    required this.color,
    required this.destinationPage,
  });

  String get routeName => '$type'; // useful for debugging / analytics
}

class ChooseRolePage extends StatelessWidget {
  final bool isLoginFlow;

  const ChooseRolePage({
    super.key,
    this.isLoginFlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final roleOptions = _buildRoleOptions(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image with overlay
          _buildBackground(context),
          // Semi-transparent dark overlay
          Container(color: Colors.black.withOpacity(0.35)),
          // Content
          SafeArea(
            child: Column(
              children: [
                _buildBackButton(context),
                Expanded(
                  child: _buildMainContent(context, roleOptions),
                ),
              ],
            ),
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

  Widget _buildBackButton(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, top: 8),
        child: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Back',
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, List<RoleOption> options) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isLoginFlow ? "Login as" : "Sign Up as",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ...options.map((option) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ChooseRoleCard(
                    icon: option.icon,
                    label: option.label,
                    color: option.color,
                    onTap: () => _navigateTo(context, option.destinationPage),
                  ),
                )),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<RoleOption> _buildRoleOptions(BuildContext context) {
    if (isLoginFlow) {
      return [
        RoleOption(
          type: RoleType.student,
          icon: Icons.school_outlined,
          label: 'Student',
          color: Colors.blue,
          destinationPage: const LoginPage(loginType: LoginType.student),
        ),
        RoleOption(
          type: RoleType.teacher,
          icon: Icons.person_2_outlined,
          label: 'Teacher',
          color: Colors.orange,
          destinationPage: const LoginPage(loginType: LoginType.teacher),
        ),
        RoleOption(
          type: RoleType.admin,
          icon: Icons.admin_panel_settings_outlined,
          label: 'Admin',
          color: Colors.green,
          destinationPage: const LoginPage(loginType: LoginType.admin),
        ),
        RoleOption(
          type: RoleType.parent,
          icon: Icons.family_restroom,
          label: 'Parent',
          color: Colors.purple,
          destinationPage: const LoginPage(loginType: LoginType.parent),
        ),
      ];
    } else {
      return [
        RoleOption(
          type: RoleType.student,
          icon: Icons.school_outlined,
          label: 'Student',
          color: Colors.blue,
          destinationPage: const StudentSignUpPage(),
        ),
        RoleOption(
          type: RoleType.teacher,
          icon: Icons.person_2_outlined,
          label: 'Teacher',
          color: Colors.orange,
          destinationPage: const TeacherSignUpPage(),
        ),
      ];
    }
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageTransition(page: page),
    );
  }
}

class ChooseRoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ChooseRoleCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        splashColor: color.withOpacity(0.12),
        highlightColor: color.withOpacity(0.08),
        child: Container(
          width: 280, // slightly wider → better touch target
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 38),
              const SizedBox(width: 20),
              Text(
                label,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
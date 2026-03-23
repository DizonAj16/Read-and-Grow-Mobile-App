import 'package:flutter/material.dart';

import '../../widgets/navigation/page_transition.dart';
import '../auth pages/login_page.dart';
import '../auth pages/student/student_signup_page.dart';
import '../auth pages/teacher/teacher_signup_page.dart';

// ---------------------------------------------------------------------------
// Enums & Models
// ---------------------------------------------------------------------------

enum RoleType { student, teacher, admin, parent }

class RoleOption {
  const RoleOption({
    required this.type,
    required this.icon,
    required this.label,
    required this.color,
    required this.destinationPage,
  });

  final RoleType type;
  final IconData icon;
  final String label;
  final Color color;
  final Widget destinationPage;

  /// Useful for debugging / analytics.
  String get routeName => '$type';
}

// ---------------------------------------------------------------------------
// Role option definitions
// ---------------------------------------------------------------------------

/// Role options shown during the **login** flow.
const _loginRoleIcons = <RoleType, IconData>{
  RoleType.student: Icons.school_outlined,
  RoleType.teacher: Icons.person_2_outlined,
  RoleType.admin: Icons.admin_panel_settings_outlined,
  RoleType.parent: Icons.family_restroom,
};

const _roleColors = <RoleType, Color>{
  RoleType.student: Colors.blue,
  RoleType.teacher: Colors.orange,
  RoleType.admin: Colors.green,
  RoleType.parent: Colors.purple,
};

const _roleLabels = <RoleType, String>{
  RoleType.student: 'Student',
  RoleType.teacher: 'Teacher',
  RoleType.admin: 'Admin',
  RoleType.parent: 'Parent',
};

List<RoleOption> _buildLoginOptions() => [
      RoleType.student,
      RoleType.teacher,
      RoleType.admin,
      RoleType.parent,
    ]
        .map(
          (type) => RoleOption(
            type: type,
            icon: _loginRoleIcons[type]!,
            label: _roleLabels[type]!,
            color: _roleColors[type]!,
            destinationPage: LoginPage(loginType: _loginTypeFor(type)),
          ),
        )
        .toList();

List<RoleOption> _buildSignupOptions() => [
      RoleOption(
        type: RoleType.student,
        icon: _loginRoleIcons[RoleType.student]!,
        label: _roleLabels[RoleType.student]!,
        color: _roleColors[RoleType.student]!,
        destinationPage: const StudentSignUpPage(),
      ),
      RoleOption(
        type: RoleType.teacher,
        icon: _loginRoleIcons[RoleType.teacher]!,
        label: _roleLabels[RoleType.teacher]!,
        color: _roleColors[RoleType.teacher]!,
        destinationPage: const TeacherSignUpPage(),
      ),
    ];

LoginType _loginTypeFor(RoleType role) {
  switch (role) {
    case RoleType.student:
      return LoginType.student;
    case RoleType.teacher:
      return LoginType.teacher;
    case RoleType.admin:
      return LoginType.admin;
    case RoleType.parent:
      return LoginType.parent;
  }
}

// ---------------------------------------------------------------------------
// ChooseRolePage
// ---------------------------------------------------------------------------

class ChooseRolePage extends StatelessWidget {
  const ChooseRolePage({super.key, this.isLoginFlow = true});

  final bool isLoginFlow;

  @override
  Widget build(BuildContext context) {
    final options =
        isLoginFlow ? _buildLoginOptions() : _buildSignupOptions();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _RolePageBackground(),
          _DarkOverlay(),
          SafeArea(
            child: Column(
              children: [
                _BackButton(),
                Expanded(
                  child: _RoleSelectionContent(
                    title: isLoginFlow ? 'Login as' : 'Sign Up as',
                    options: options,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets (scoped to this file)
// ---------------------------------------------------------------------------

class _RolePageBackground extends StatelessWidget {
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
          'assets/background/480681008_1020230633459316_6070422237958140538_n.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}

class _DarkOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Colors.black.withOpacity(0.35));
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
}

class _RoleSelectionContent extends StatelessWidget {
  const _RoleSelectionContent({
    required this.title,
    required this.options,
  });

  final String title;
  final List<RoleOption> options;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TitleText(title),
            const SizedBox(height: 40),
            ...options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: ChooseRoleCard(
                  icon: option.icon,
                  label: option.label,
                  color: option.color,
                  onTap: () => _navigateTo(context, option.destinationPage),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.of(context).push(PageTransition(page: page));
  }
}

class _TitleText extends StatelessWidget {
  const _TitleText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
      textAlign: TextAlign.center,
    );
  }
}

// ---------------------------------------------------------------------------
// ChooseRoleCard  (public — reusable if needed elsewhere)
// ---------------------------------------------------------------------------

class ChooseRoleCard extends StatelessWidget {
  const ChooseRoleCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  static const double _cardWidth = 280;
  static const double _iconSize = 38;
  static const double _fontSize = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        splashColor: color.withOpacity(0.12),
        highlightColor: color.withOpacity(0.08),
        child: SizedBox(
          width: _cardWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: _iconSize),
                const SizedBox(width: 20),
                Text(
                  label,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: _fontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
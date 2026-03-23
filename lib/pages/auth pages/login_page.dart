import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/supabase_auth_service.dart';
import '../../widgets/appbar/theme_toggle_button.dart';
import '../../widgets/navigation/page_transition.dart';
import '../admin pages/admin_page.dart';
import '../parent pages/parent_dashboard_page.dart';
import '../student pages/student_page.dart';
import '../teacher pages/teacher_page.dart';
import 'auth buttons widgets/login_button.dart';
import 'form fields widgets/password_text_field.dart';
import 'parent/parent_signup_page.dart';
import 'student/student_signup_page.dart';
import 'teacher/teacher_signup_page.dart';

enum LoginType { universal, student, teacher, parent, admin }

class LoginPage extends StatefulWidget {
  final LoginType loginType;

  const LoginPage({
    super.key,
    this.loginType = LoginType.universal,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _autoValidate = false;

  late final LoginRoleConfig _config;

  @override
  void initState() {
    super.initState();
    _config = LoginRoleConfig.forType(widget.loginType);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onPrimary),
        actions: [ThemeToggleButton(iconColor: Theme.of(context).colorScheme.onPrimary)],
      ),
      body: Stack(
        children: [
          _buildBackground(context),
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height - kToolbarHeight,
                ),
                child: Column(
                  children: [
                    _buildHeaderSection(context),
                    _buildFormCard(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  //  Background & Visuals
  // ────────────────────────────────────────────────

  Widget _buildBackground(BuildContext context) {
    final showImageBg = widget.loginType == LoginType.universal ||
        widget.loginType == LoginType.student ||
        widget.loginType == LoginType.teacher;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showImageBg)
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.primary.withOpacity(0.68),
              BlendMode.softLight,
            ),
            child: Opacity(
              opacity: 0.24,
              child: Image.asset(
                'assets/background/480681008_1020230633459316_6070422237958140538_n.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.4),
                Theme.of(context).colorScheme.secondary.withOpacity(0.4),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────
  //  Header (avatar + title + subtitle + instruction)
  // ────────────────────────────────────────────────

  Widget _buildHeaderSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Column(
        children: [
          if (_config.showInstructionBanner) _buildInstructionBanner(context),
          const SizedBox(height: 32),
          _buildAvatar(context),
          const SizedBox(height: 24),
          Text(
            _config.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _config.subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.92),
                  fontStyle: FontStyle.italic,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.white70, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Login Instruction",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15.5),
                ),
                const SizedBox(height: 6),
                Text(
                  _config.instructionText,
                  style: const TextStyle(color: Colors.white70, height: 1.35, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return CircleAvatar(
      radius: 76,
      backgroundColor: Colors.white.withOpacity(0.92),
      child: _config.iconAsset != null
          ? Image.asset(
              _config.iconAsset!,
              width: _config.iconSize,
              height: _config.iconSize,
              fit: BoxFit.contain,
            )
          : Icon(
              _config.icon,
              size: _config.iconSize,
              color: Theme.of(context).colorScheme.primary,
            ),
    );
  }

  // ────────────────────────────────────────────────
  //  Form Card
  // ────────────────────────────────────────────────

  Widget _buildFormCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
        child: Form(
          key: _formKey,
          autovalidateMode: _autoValidate ? AutovalidateMode.always : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUsernameField(context),
              const SizedBox(height: 28),
              PasswordTextField(
                labelText: 'Password',
                controller: _passwordCtrl,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Password is required' : null,
              ),
              const SizedBox(height: 8),
              _buildForgotPasswordLink(context),
              const SizedBox(height: 24),
              LoginButton(text: "Login", onPressed: _attemptLogin),
              if (_config.showSignupSection) ...[
                const SizedBox(height: 32),
                _buildSignupSection(context),
              ],
              const SizedBox(height: 32),
              _buildHelpNotice(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsernameField(BuildContext context) {
    return TextFormField(
      controller: _usernameCtrl,
      keyboardType: _config.keyboardType,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: _config.inputLabel,
        hintText: _config.inputHint,
        prefixIcon: Icon(_config.inputIcon),
        filled: true,
        fillColor: Colors.grey.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      ),
      validator: _validateInput,
    );
  }

  Widget _buildForgotPasswordLink(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () {}, // TODO: implement forgot password
        child: Text(
          'Forgot Password?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  Widget _buildSignupSection(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 32),
        const Text("or", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        const Text(
          "Don't have an account? Sign up below:",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13.5),
        ),
        const SizedBox(height: 20),
        _SignUpOptionButton(
          label: "Sign up as Student",
          iconPath: 'assets/icons/graduating-student.png',
          color: Theme.of(context).colorScheme.primary,
          onTap: () => Navigator.push(context, PageTransition(page: const StudentSignUpPage())),
        ),
        const SizedBox(height: 12),
        _SignUpOptionButton(
          label: "Sign up as Teacher",
          iconPath: 'assets/icons/teacher.png',
          color: Theme.of(context).colorScheme.secondary,
          onTap: () => Navigator.push(context, PageTransition(page: const TeacherSignUpPage())),
        ),
        const SizedBox(height: 12),
        _SignUpOptionButton(
          label: "Sign up as Parent",
          icon: const Icon(Icons.family_restroom, size: 30),
          color: Colors.purple.shade700,
          textColor: Colors.white,
          onTap: () => Navigator.push(context, PageTransition(page: const ParentSignUpPage())),
        ),
      ],
    );
  }

  Widget _buildHelpNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _config.helpTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  _config.helpText,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  //  Logic
  // ────────────────────────────────────────────────

  String? _validateInput(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _config.validationMessage;
    }

    final input = value.trim();

    if (widget.loginType == LoginType.teacher) {
      if (!input.contains('@') || !input.endsWith('@gmail.com')) {
        return 'Use format: username@gmail.com';
      }
    }

    if (widget.loginType == LoginType.parent) {
      if (!input.endsWith('@parent.app')) {
        return 'Use format: username@parent.app';
      }
    }

    return null;
  }

  Future<void> _attemptLogin() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _autoValidate = true);
      return;
    }

    _showLoadingOverlay("Logging in...");

    try {
      final result = await SupabaseAuthService.login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text.trim(),
      );

      final user = result['user'] as Map<String, dynamic>?;
      final role = (result['role'] as String?) ?? 'student';

      if (user == null || user['id'] == null) throw Exception('Invalid user data');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('id', user['id']);
      await prefs.setString('role', role);

      if (!mounted) return;

      Navigator.pop(context); // close loading
      await _showSuccessDialog();

      if (!mounted) return;
      _navigateToDashboard(role, user['id']);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading

      String msg = e.toString().replaceAll('Exception: ', '').trim();

      if (msg.contains('pending approval')) {
        msg = 'Your teacher account is pending approval from an administrator.';
      } else if (msg.contains('deactivated') || msg.contains('inactive') || msg.contains('not active')) {
        msg = 'Your account is currently inactive. Please contact an administrator.';
      }

      _showErrorDialog(title: 'Login Failed', message: msg);
      debugPrint('Login error: $e');
    }
  }

  Future<void> _showSuccessDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset('assets/animation/success.json', width: 120, height: 120),
            const SizedBox(height: 20),
            const Text(
              'Login Successful!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 2200));
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  void _navigateToDashboard(String role, String userId) {
    final page = switch (role) {
      'student' => const StudentPage(),
      'teacher' => const TeacherPage(),
      'admin' => const AdminPage(),
      'parent' => ParentDashboardPage(parentId: userId),
      _ => null,
    };

    if (page == null) {
      debugPrint("Unknown role: $role");
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      PageTransition(page: page),
      (_) => false,
    );
  }

void _showLoadingOverlay(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Material( // Added Material wrapper
          type: MaterialType.transparency, // Keeps the background clear
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            margin: const EdgeInsets.symmetric(horizontal: 40), // Prevents touching edges
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset(
                  'assets/animation/loading_rainbow.json', 
                  width: 90, 
                  height: 90,
                  // Ensure lottie doesn't crash if file is missing during dev
                  errorBuilder: (context, error, stackTrace) => 
                      const CircularProgressIndicator(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 16, 
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none, // Explicitly remove underline
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showErrorDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_rounded, color: Theme.of(context).colorScheme.error, size: 32),
            const SizedBox(width: 12),
            Flexible(child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────
//  Configuration per role
// ────────────────────────────────────────────────

class LoginRoleConfig {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? iconAsset;
  final double iconSize;
  final String inputLabel;
  final String inputHint;
  final IconData inputIcon;
  final TextInputType keyboardType;
  final String validationMessage;
  final bool showSignupSection;
  final String instructionText;
  final String helpTitle;
  final String helpText;
  final bool showInstructionBanner;

  LoginRoleConfig({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconAsset,
    this.iconSize = 100,
    required this.inputLabel,
    required this.inputHint,
    required this.inputIcon,
    this.keyboardType = TextInputType.text,
    required this.validationMessage,
    this.showSignupSection = false,
    this.instructionText = '',
    this.helpTitle = 'Need help?',
    this.helpText = '',
    this.showInstructionBanner = false,
  });

  factory LoginRoleConfig.forType(LoginType type) {
    switch (type) {
      case LoginType.student:
        return LoginRoleConfig(
          title: 'Student Login',
          subtitle: 'Welcome back! Continue your reading journey',
          icon: Icons.school,
          iconAsset: 'assets/icons/graduating-student.png',
          iconSize: 110,
          inputLabel: 'Username or Email',
          inputHint: 'username  or  username@student.app',
          inputIcon: Icons.account_circle,
          validationMessage: 'Username or email is required',
          showSignupSection: true,
          showInstructionBanner: true,
          instructionText: 'You can use either your plain username\nor username@student.app',
          helpTitle: 'Login formats',
          helpText: '• juandelacruz\n• juandelacruz@student.app',
        );

      case LoginType.teacher:
        return LoginRoleConfig(
          title: 'Teacher Login',
          subtitle: 'Manage your classes and students',
          icon: Icons.person,
          iconAsset: 'assets/icons/teacher.png',
          iconSize: 110,
          inputLabel: 'Email Address',
          inputHint: 'username@gmail.com',
          inputIcon: Icons.email,
          keyboardType: TextInputType.emailAddress,
          validationMessage: 'Email is required',
          showSignupSection: true,
          showInstructionBanner: true,
          instructionText: 'Use your registered email address\n(username@gmail.com)',
          helpTitle: 'Example',
          helpText: 'juandelacruz@gmail.com',
        );

      case LoginType.parent:
        return LoginRoleConfig(
          title: 'Parent Login',
          subtitle: "Monitor your child's reading progress",
          icon: Icons.family_restroom,
          iconSize: 90,
          inputLabel: 'Email',
          inputHint: 'username@parent.app',
          inputIcon: Icons.email,
          keyboardType: TextInputType.emailAddress,
          validationMessage: 'Email is required',
          showSignupSection: false,
          showInstructionBanner: true,
          instructionText: 'Use your assigned email\n(username@parent.app)',
          helpTitle: 'Credentials',
          helpText: 'Contact your school admin if you don’t have login details.',
        );

      case LoginType.admin:
        return LoginRoleConfig(
          title: 'Admin Login',
          subtitle: 'System administration panel',
          icon: Icons.admin_panel_settings,
          iconSize: 90,
          inputLabel: 'Admin Email',
          inputHint: 'admin@domain.com',
          inputIcon: Icons.email,
          keyboardType: TextInputType.emailAddress,
          validationMessage: 'Email is required',
          showSignupSection: false,
          showInstructionBanner: false,
          helpTitle: 'Security Note',
          helpText: 'Access is strictly limited to authorized personnel.',
        );

      case LoginType.universal:
      return LoginRoleConfig(
          title: 'Login',
          subtitle: 'Sign in to your account',
          icon: Icons.login,
          iconSize: 90,
          inputLabel: 'Username or Email',
          inputHint: 'Enter username or email',
          inputIcon: Icons.account_circle,
          validationMessage: 'Username or email is required',
          showSignupSection: true,
          showInstructionBanner: false,
          helpTitle: 'Need help?',
          helpText: 'Use your username or registered email address.',
        );
    }
  }
}

// ────────────────────────────────────────────────
//  Reusable signup button widget
// ────────────────────────────────────────────────

class _SignUpOptionButton extends StatelessWidget {
  final String label;
  final String? iconPath;
  final Widget? icon;
  final Color color;
  final Color? textColor;
  final VoidCallback onTap;

  const _SignUpOptionButton({
    required this.label,
    this.iconPath,
    this.icon,
    required this.color,
    this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: icon ??
          (iconPath != null
              ? Image.asset(iconPath!, width: 30, height: 30)
              : const Icon(Icons.person_add)),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: textColor ?? Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor ?? Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        minimumSize: const Size.fromHeight(58),
      ),
    );
  }
}
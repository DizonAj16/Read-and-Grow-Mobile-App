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
        onPressed: _showForgotPasswordDialog,
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
        return 'Please enter a valid email address (e.g., username@gmail.com)';
      }
    }

    if (widget.loginType == LoginType.parent) {
      if (!input.endsWith('@parent.app')) {
        return 'Please enter your parent email in the format: username@parent.app';
      }
    }

    return null;
  }

  /// Convert technical error messages to user-friendly messages
  String _getUserFriendlyErrorMessage(String error) {
    final errorLower = error.toLowerCase();

    // Authentication errors
    if (errorLower.contains('invalid login credentials') ||
        errorLower.contains('invalid credentials') ||
        errorLower.contains('wrong password') ||
        errorLower.contains('incorrect password')) {
      return 'Incorrect username or password. Please try again.';
    }
    
    if (errorLower.contains('email not confirmed') || 
        errorLower.contains('email not verified')) {
      return 'Please verify your email address before logging in. Check your inbox for a verification link.';
    }
    
    if (errorLower.contains('user not found')) {
      return 'No account found with these credentials. Please check your username/email or sign up.';
    }
    
    // Account status errors
    if (errorLower.contains('pending approval')) {
      return 'Your account is pending approval. You will receive an email once approved.';
    }
    
    if (errorLower.contains('deactivated') || 
        errorLower.contains('inactive')) {
      return 'This account has been deactivated. Please contact an administrator for assistance.';
    }
    
    if (errorLower.contains('not active')) {
      return 'Your account is not active. Please contact support for assistance.';
    }
    
    // Network and connection errors
    if (errorLower.contains('network') || 
        errorLower.contains('connection') ||
        errorLower.contains('timeout') ||
        errorLower.contains('failed to connect')) {
      return 'Unable to connect to the server. Please check your internet connection and try again.';
    }
    
    // Server errors
    if (errorLower.contains('500') || 
        errorLower.contains('internal server error')) {
      return 'Our server encountered an issue. Please try again in a few minutes.';
    }
    
    if (errorLower.contains('503') || 
        errorLower.contains('service unavailable')) {
      return 'The service is temporarily unavailable. Please try again later.';
    }
    
    // Rate limiting
    if (errorLower.contains('too many requests') || 
        errorLower.contains('rate limit')) {
      return 'Too many login attempts. Please wait a few minutes before trying again.';
    }
    
    // Session errors
    if (errorLower.contains('session') || 
        errorLower.contains('token')) {
      return 'Session error. Please try logging in again.';
    }
    
    // Validation errors
    if (errorLower.contains('invalid email') || 
        errorLower.contains('email format')) {
      return 'Please enter a valid email address.';
    }
    
    if (errorLower.contains('password too weak')) {
      return 'Your password does not meet security requirements. Please reset your password.';
    }
    
    // Default fallback - hide technical details from users
    return 'Unable to sign in. Please check your credentials and try again, or contact support if the problem persists.';
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

      if (user == null || user['id'] == null) {
        throw Exception('Invalid user data received');
      }

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
      
      // Close loading overlay
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Convert technical error to user-friendly message
      final errorMessage = _getUserFriendlyErrorMessage(e.toString());
      
      _showErrorDialog(
        title: 'Sign In Failed',
        message: errorMessage,
      );
      
      debugPrint('Login error details: $e');
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Forgot your password?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _config.forgotPasswordMessage,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.contact_support, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _config.contactMessage,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
            const SizedBox(height: 8),
            Text(
              'Welcome back!',
              style: TextStyle(color: Colors.grey.shade600),
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
      _showErrorDialog(
        title: 'Login Error',
        message: 'Unable to determine your account type. Please contact support.',
      );
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
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            margin: const EdgeInsets.symmetric(horizontal: 40),
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
                    decoration: TextDecoration.none,
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
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
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
  final String forgotPasswordMessage;
  final String contactMessage;

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
    this.forgotPasswordMessage = 'Please contact your administrator to reset your password.',
    this.contactMessage = 'For assistance, please contact your school administrator.',
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
          forgotPasswordMessage: 'If you forgot your password, please contact your teacher or school administrator to reset it.',
          contactMessage: 'Your teacher can help you reset your password.',
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
          forgotPasswordMessage: 'If you forgot your password, use the "Forgot Password" option in your email provider or contact your school administrator.',
          contactMessage: 'Contact your school IT department for password assistance.',
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
          helpText: 'Contact your school admin if you don\'t have login details.',
          forgotPasswordMessage: 'Parent accounts require administrator assistance for password resets.',
          contactMessage: 'Please contact your child\'s school administrator for password assistance.',
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
          forgotPasswordMessage: 'Please contact the system administrator for password reset assistance.',
          contactMessage: 'Contact the primary system administrator for help.',
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
          forgotPasswordMessage: 'If you forgot your password, please contact your school administrator.',
          contactMessage: 'For assistance, please contact support.',
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
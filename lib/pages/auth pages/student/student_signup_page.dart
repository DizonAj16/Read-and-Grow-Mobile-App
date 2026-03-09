import 'package:deped_reading_app_laravel/pages/auth%20pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/appbar/theme_toggle_button.dart';
import '../../../widgets/navigation/page_transition.dart';
import '../auth buttons widgets/signup_button.dart';
import '../form fields widgets/password_text_field.dart';

class StudentSignUpPage extends StatefulWidget {
  const StudentSignUpPage({super.key});

  @override
  State<StudentSignUpPage> createState() => _StudentSignUpPageState();
}

class _StudentSignUpPageState extends State<StudentSignUpPage> {
  // ────────────────────────────────────────────
  // Controllers & Form
  // ────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  bool _autoValidate = false;

  final _nameController = TextEditingController();
  final _lrnController = TextEditingController();
  final _gradeController = TextEditingController();
  final _sectionController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // ────────────────────────────────────────────
  // Constants & Options
  // ────────────────────────────────────────────
  static const _availableGrades = ['1', '2', '3', '4', '5'];
  String? _notSetReadingLevelId;

  @override
  void initState() {
    super.initState();
    _loadNotSetReadingLevel();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lrnController.dispose();
    _gradeController.dispose();
    _sectionController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────
  // Data Loading
  // ────────────────────────────────────────────
  Future<void> _loadNotSetReadingLevel() async {
    try {
      final data =
          await Supabase.instance.client
              .from('reading_levels')
              .select('id')
              .eq('level_number', 0)
              .maybeSingle();

      if (data != null && mounted) {
        setState(() => _notSetReadingLevelId = data['id'] as String);
      }
    } catch (e) {
      debugPrint('Error loading default reading level: $e');
    }
  }

  // ────────────────────────────────────────────
  // Business Logic – Registration Flow
  // ────────────────────────────────────────────
  Future<void> _registerStudent() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _autoValidate = true);
      return;
    }

    _showLoadingDialog("Creating your account...");

    try {
      final supabase = Supabase.instance.client;

      final name = _nameController.text.trim();
      final lrn = _lrnController.text.trim();
      final grade = _gradeController.text.trim();
      final section = _sectionController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      final email = '$username@student.app';

      // 1. Check for duplicates
      if (await _usernameExists(username)) {
        _showError("Username already exists. Please choose another.");
        return;
      }

      if (await _lrnExists(lrn)) {
        _showError("LRN is already registered.");
        return;
      }

      // 2. Create auth user
      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'username': username, 'name': name},
      );

      final user = authResponse.user;
      if (user == null) {
        _showError("Failed to create authentication account.");
        return;
      }

      // 3. Insert user record
      await supabase.from('users').insert({
        'id': user.id,
        'username': username,
        'password':
            password, // Consider: do you really need to store plain password?
        'role': 'student',
      });

      // 4. Insert student record
      final studentData = {
        'id': user.id,
        'username': username,
        'student_name': name,
        'student_lrn': lrn,
        if (grade.isNotEmpty) 'student_grade': grade,
        if (section.isNotEmpty) 'student_section': section,
        'reading_level_updated_at': DateTime.now().toIso8601String(),
        if (_notSetReadingLevelId != null)
          'current_reading_level_id': _notSetReadingLevelId,
      };

      await supabase.from('students').insert(studentData);

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      await _showSuccessAndLoginInfoDialog(
        username: username,
        email: email,
        password: password,
      );
    } catch (e, stack) {
      debugPrint('Registration failed: $e\n$stack');

      // Best effort rollback
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          await Supabase.instance.client.from('users').delete().eq('id', uid);
          await Supabase.instance.client.auth.admin.deleteUser(uid);
        }
      } catch (rollbackErr) {
        debugPrint('Rollback failed: $rollbackErr');
      }
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // ensure loading is closed
      }
      _showError(
        "Registration failed. Please try again.\n${_friendlyErrorMessage(e)}",
      );
    } finally {}
  }

  Future<bool> _usernameExists(String username) async {
    final res =
        await Supabase.instance.client
            .from('users')
            .select('id')
            .eq('username', username)
            .maybeSingle();
    return res != null;
  }

  Future<bool> _lrnExists(String lrn) async {
    final res =
        await Supabase.instance.client
            .from('students')
            .select('id')
            .eq('student_lrn', lrn)
            .maybeSingle();
    return res != null;
  }

  String _friendlyErrorMessage(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('duplicate') || msg.contains('unique')) {
      return "Username or LRN already taken.";
    }
    if (msg.contains('constraint') || msg.contains('foreign key')) {
      return "Invalid data provided.";
    }
    return "An unexpected error occurred.";
  }

  // ────────────────────────────────────────────
  // UI – Dialogs
  // ────────────────────────────────────────────
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => Center(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Lottie.asset(
                      'assets/animation/loading_rainbow.json',
                      height: 80,
                      width: 80,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _showSuccessAndLoginInfoDialog({
    required String username,
    required String email,
    required String password,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.all(24),
            content: SingleChildScrollView(
              child: SuccessLoginInfoContent(
                username: username,
                email: email,
                password: password,
                onProceed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                  _goToLogin();
                },
              ),
            ),
          ),
    );
  }

  void _showError(String message, {String title = "Registration Failed"}) {
    if (!mounted) return;
    Navigator.pop(context); // close loading if open

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 28),
                const SizedBox(width: 12),
                Text(title, style: const TextStyle(color: Colors.red)),
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

  Future<void> _goToLogin() async {
    if (!mounted) return;

    // Use pushAndRemoveUntil to clear the navigation stack
    Navigator.pushAndRemoveUntil(
      context,
      PageTransition(page: const LoginPage(loginType: LoginType.student)),
      (route) => false, // This removes all previous routes
    );
  }

  // ────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        actions: [
          ThemeToggleButton(iconColor: Theme.of(context).colorScheme.onPrimary),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildFormCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildInfoBanner(),
        const SizedBox(height: 32),
        CircleAvatar(
          radius: 70,
          backgroundColor: Colors.white.withOpacity(0.9),
          child: Image.asset('assets/icons/graduating-student.png', width: 100),
        ),
        const SizedBox(height: 16),
        Text(
          "Student Sign Up",
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Create your account to begin your reading journey",
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.white70, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "Important",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Just enter your desired username.\n@student.app is added automatically.",
                  style: TextStyle(color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        autovalidateMode:
            _autoValidate ? AutovalidateMode.always : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNameField(),
            const SizedBox(height: 20),
            _buildLrnField(),
            const SizedBox(height: 20),
            _buildGradeDropdown(),
            const SizedBox(height: 20),
            _buildSectionField(),
            const SizedBox(height: 24),
            _buildUsernameField(),
            const SizedBox(height: 20),
            PasswordTextField(
              labelText: "Password",
              controller: _passwordController,
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            PasswordTextField(
              labelText: "Confirm Password",
              controller: _confirmPasswordController,
              validator: (v) {
                if (v?.trim().isEmpty ?? true) return 'Required';
                if (v != _passwordController.text)
                  return "Passwords don't match";
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildReadingLevelNote(),
            const SizedBox(height: 24),
            SignUpButton(text: "Sign Up", onPressed: _registerStudent),
            const SizedBox(height: 16),
            _buildLoginLink(),
          ],
        ),
      ),
    );
  }

  // ─── Form Fields ────────────────────────────────────────

  Widget _buildNameField() => _textFormField(
    controller: _nameController,
    label: "Full Name",
    icon: Icons.person,
    hint: "e.g. Juan Dela Cruz",
    validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
  );

  Widget _buildLrnField() => _textFormField(
    controller: _lrnController,
    label: "Learner Reference Number (LRN)",
    icon: Icons.confirmation_number,
    hint: "12-digit number",
    validator: (v) {
      final val = v?.trim();
      if (val == null || val.isEmpty) return 'Required';
      if (!RegExp(r'^\d{12}$').hasMatch(val)) {
        return 'Must be exactly 12 digits';
      }
      return null;
    },
  );

  Widget _buildGradeDropdown() => DropdownButtonFormField<String>(
    value: _gradeController.text.isNotEmpty ? _gradeController.text : null,
    items:
        _availableGrades
            .map((g) => DropdownMenuItem(value: g, child: Text("Grade $g")))
            .toList(),
    onChanged: (v) => setState(() => _gradeController.text = v ?? ''),
    validator: (v) => v == null ? 'Required' : null,
    decoration: InputDecoration(
      labelText: "Grade Level",
      prefixIcon: const Icon(Icons.school),
      filled: true,
      fillColor: Colors.grey.withOpacity(0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _buildSectionField() => _textFormField(
    controller: _sectionController,
    label: "Section",
    icon: Icons.group,
    hint: "e.g. Rose, Section A",
    validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
  );

  Widget _buildUsernameField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _textFormField(
        controller: _usernameController,
        label: "Username",
        icon: Icons.account_circle,
        hint: "e.g. juandelacruz123",
        validator: (v) {
          final val = v?.trim();
          if (val == null || val.isEmpty) return 'Required';
          if (val.contains('@')) {
            return "Don't include @student.app";
          }
          if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(val)) {
            return 'Letters, numbers, underscore only';
          }
          return null;
        },
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12, top: 6),
        child: Text(
          "→ Login as: yourusername@student.app",
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    ],
  );

  Widget _buildReadingLevelNote() {
    if (_notSetReadingLevelId == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Initial reading level: Not Set",
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginLink() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text("Already have an account?  "),
      TextButton(
        onPressed:
            () => Navigator.push(
              context,
              PageTransition(
                page: const LoginPage(loginType: LoginType.student),
              ),
            ),
        child: const Text("Sign In"),
      ),
    ],
  );

  Widget _textFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.grey.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      validator: validator,
    );
  }
}

// ────────────────────────────────────────────
// Extracted Widget: Success + Login Info
// ────────────────────────────────────────────
class SuccessLoginInfoContent extends StatelessWidget {
  final String username;
  final String email;
  final String password;
  final VoidCallback onProceed;

  const SuccessLoginInfoContent({
    super.key,
    required this.username,
    required this.email,
    required this.password,
    required this.onProceed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        const Text(
          "Account Created!",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        _infoCard(context),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onProceed,
          icon: const Icon(Icons.login),
          label: const Text("Go to Login"),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow(Icons.email, "Email", email, true),
          const Divider(height: 24),
          _infoRow(Icons.lock, "Password", password, true),
          const Divider(height: 24),
          _infoRow(Icons.person, "Username", username, false),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, bool important) {
    return Row(
      children: [
        Icon(icon, color: important ? Colors.blue : Colors.grey, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontWeight: important ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

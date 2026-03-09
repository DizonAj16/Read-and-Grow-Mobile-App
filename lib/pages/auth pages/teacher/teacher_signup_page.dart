import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/appbar/theme_toggle_button.dart';
import '../../../widgets/navigation/page_transition.dart';
import '../auth buttons widgets/signup_button.dart';
import '../form fields widgets/password_text_field.dart';
import '../login_page.dart';

class TeacherSignUpPage extends StatefulWidget {
  const TeacherSignUpPage({super.key});

  @override
  State<TeacherSignUpPage> createState() => _TeacherSignUpPageState();
}

class _TeacherSignUpPageState extends State<TeacherSignUpPage> {
  // ────────────────────────────────────────────
  // Controllers & Form
  // ────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  bool _autoValidate = false;

  final _nameCtrl         = TextEditingController();
  final _positionCtrl     = TextEditingController();
  final _emailUsernameCtrl = TextEditingController(); // only the part before @gmail.com
  final _usernameCtrl     = TextEditingController();
  final _passwordCtrl     = TextEditingController();
  final _confirmCtrl      = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _emailUsernameCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────
  // Registration Flow
  // ────────────────────────────────────────────
  Future<void> _registerTeacher() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _autoValidate = true);
      return;
    }

    _showLoading("Creating teacher account...");

    final supabase = Supabase.instance.client;
    String? authUid;

    try {
      final name     = _nameCtrl.text.trim();
      final position = _positionCtrl.text.trim();
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text.trim();

      // Email logic: backend appends @gmail.com
      String emailUsername = _emailUsernameCtrl.text.trim();
      if (emailUsername.isEmpty) throw Exception('Email username required');

      if (emailUsername.contains('@')) {
        if (emailUsername.endsWith('@gmail.com')) {
          _showError("Don't include @gmail.com — just enter the username part.");
          return;
        }
        _showError("Only enter your Gmail username (without @gmail.com).");
        return;
      }

      final email = '$emailUsername@gmail.com';

      // 1. Check duplicates
      if (await _usernameExists(username)) {
        _showError("Username already taken.");
        return;
      }

      if (await _emailExists(email)) {
        _showError("This Gmail account is already registered.");
        return;
      }

      // 2. Create auth user
      final authRes = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          'name': name,
          'position': position,
        },
      );

      final user = authRes.user;
      if (user == null) throw Exception('Auth signup failed');

      authUid = user.id;

      // 3. Insert users record
      await supabase.from('users').insert({
        'id': authUid,
        'username': username,
        'password': password, // Note: consider hashing or removing this field
        'role': 'teacher',
      });

      // 4. Insert teachers record
      await supabase.from('teachers').insert({
        'id': authUid,
        'teacher_name': name,
        'teacher_email': email,
        'teacher_position': position,
        'account_status': 'pending',
      });

      if (!mounted) return;

      Navigator.pop(context); // close loading

      await _showSuccessDialog(
        username: username,
        email: email,
        password: password,
        position: position,
      );
    } catch (e, st) {
      debugPrint('Teacher registration failed:\n$e\n$st');

      if (authUid != null) await _rollback(authUid);

      if (mounted) {
        Navigator.pop(context);
        _showError(_friendlyErrorMessage(e.toString()));
      }
    }
  }

  Future<bool> _usernameExists(String username) async {
    final res = await Supabase.instance.client
        .from('users')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    return res != null;
  }

  Future<bool> _emailExists(String email) async {
    final res = await Supabase.instance.client
        .from('teachers')
        .select('id')
        .eq('teacher_email', email)
        .maybeSingle();
    return res != null;
  }

  Future<void> _rollback(String uid) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase.from('teachers').delete().eq('id', uid);
      await supabase.from('users').delete().eq('id', uid);
      await supabase.auth.admin.deleteUser(uid);
    } catch (e) {
      debugPrint('Rollback failed: $e');
    }
  }

  String _friendlyErrorMessage(String error) {
    final msg = error.toLowerCase();
    if (msg.contains('duplicate') || msg.contains('unique')) {
      return "Username or email already in use.";
    }
    if (msg.contains('constraint') || msg.contains('foreign key')) {
      return "Invalid information provided.";
    }
    return "Registration failed. Please try again.";
  }

  // ────────────────────────────────────────────
  // Dialogs
  // ────────────────────────────────────────────
  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset('assets/animation/loading_rainbow.json', height: 80),
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

  Future<void> _showSuccessDialog({
    required String username,
    required String email,
    required String password,
    required String position,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: TeacherSuccessContent(
          username: username,
          email: email,
          password: password,
          position: position,
          onProceed: () {
            Navigator.pop(context);
            _goToLogin();
          },
        ),
      ),
    );
  }

  Future<void> _goToLogin() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageTransition(page: const LoginPage(loginType: LoginType.teacher)),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    Navigator.maybePop(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text("Error", style: TextStyle(color: Colors.red)),
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

  // ────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onPrimary),
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
                  _Header(),
                  const SizedBox(height: 24),
                  _FormCard(
                    formKey: _formKey,
                    autoValidate: _autoValidate,
                    nameCtrl: _nameCtrl,
                    positionCtrl: _positionCtrl,
                    emailUsernameCtrl: _emailUsernameCtrl,
                    usernameCtrl: _usernameCtrl,
                    passwordCtrl: _passwordCtrl,
                    confirmCtrl: _confirmCtrl,
                    onSignUp: _registerTeacher,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────
// Widgets
// ────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        _InfoBanner(),
        const SizedBox(height: 32),
        CircleAvatar(
          radius: 70,
          backgroundColor: Colors.white.withOpacity(0.9),
          child: Image.asset('assets/icons/teacher.png', width: 100),
        ),
        const SizedBox(height: 16),
        Text(
          "Teacher Sign Up",
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          "Create your account to manage classes and students",
          style: TextStyle(color: Colors.white.withOpacity(0.85)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white70),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "Important",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  "Enter only your Gmail username.\n@gmail.com is added automatically.",
                  style: TextStyle(color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool autoValidate;
  final TextEditingController nameCtrl;
  final TextEditingController positionCtrl;
  final TextEditingController emailUsernameCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final VoidCallback onSignUp;

  const _FormCard({
    required this.formKey,
    required this.autoValidate,
    required this.nameCtrl,
    required this.positionCtrl,
    required this.emailUsernameCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 5)),
        ],
      ),
      child: Form(
        key: formKey,
        autovalidateMode: autoValidate ? AutovalidateMode.always : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _textField(
              controller: nameCtrl,
              label: "Full Name",
              icon: Icons.person,
              hint: "e.g. Maria Santos",
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            _textField(
              controller: positionCtrl,
              label: "Position / Role",
              icon: Icons.work,
              hint: "e.g. Grade 5 Adviser • English Coordinator",
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            _textField(
              controller: usernameCtrl,
              label: "Username",
              icon: Icons.account_circle,
              hint: "e.g. maria_santos_2025",
              validator: (v) {
                final val = v?.trim() ?? '';
                if (val.isEmpty) return 'Required';
                if (val.contains('@')) return "Don't include @gmail.com here";
                if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(val)) {
                  return 'Letters, numbers, underscore only';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _EmailUsernameField(controller: emailUsernameCtrl),
            const SizedBox(height: 20),
            PasswordTextField(
              labelText: "Password",
              controller: passwordCtrl,
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            PasswordTextField(
              labelText: "Confirm Password",
              controller: confirmCtrl,
              validator: (v) {
                if (v?.trim().isEmpty ?? true) return 'Required';
                if (v != passwordCtrl.text) return "Passwords don't match";
                return null;
              },
            ),
            const SizedBox(height: 16),
            _EmailFormatNote(),
            const SizedBox(height: 32),
            SignUpButton(text: "Sign Up", onPressed: onSignUp),
            const SizedBox(height: 16),
            _LoginLink(),
          ],
        ),
      ),
    );
  }

  Widget _textField({
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

class _EmailUsernameField extends StatelessWidget {
  final TextEditingController controller;

  const _EmailUsernameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Gmail Username",
            hintText: "e.g. juan.delacruz",
            prefixIcon: const Icon(Icons.email),
            filled: true,
            fillColor: Colors.grey.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (v) {
            final val = v?.trim() ?? '';
            if (val.isEmpty) return 'Required';
            if (val.contains('@')) {
              return val.endsWith('@gmail.com')
                  ? "Don't include @gmail.com"
                  : "Only enter the part before @gmail.com";
            }
            if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(val)) {
              return 'Letters, numbers, dots, underscore only';
            }
            return null;
          },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 6),
          child: Text(
            "→ Full email becomes: yourusername@gmail.com",
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmailFormatNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                "Email format",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Enter only the username part.\nThe system automatically adds @gmail.com.",
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}

class _LoginLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Already have an account? "),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            PageTransition(page: const LoginPage(loginType: LoginType.teacher)),
          ),
          child: const Text("Sign In"),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────
// Success Dialog Content
// ────────────────────────────────────────────
class TeacherSuccessContent extends StatelessWidget {
  final String username;
  final String email;
  final String password;
  final String position;
  final VoidCallback onProceed;

  const TeacherSuccessContent({
    super.key,
    required this.username,
    required this.email,
    required this.password,
    required this.position,
    required this.onProceed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        const Text(
          "Account Created!",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "($position)",
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(Icons.info, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Your account is pending admin approval.\nYou will be notified once activated.",
                  style: TextStyle(color: Colors.blue.shade800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _CredentialsCard(
          username: username,
          email: email,
          password: password,
        ),
        const SizedBox(height: 24),
        _Instructions(),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.login),
            label: const Text("Go to Login"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onProceed,
          ),
        ),
      ],
    );
  }
}

class _CredentialsCard extends StatelessWidget {
  final String username, email, password;

  const _CredentialsCard({
    required this.username,
    required this.email,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          _CredentialRow(Icons.email, "Email", email, true),
          const Divider(height: 24),
          _CredentialRow(Icons.lock, "Password", password, true),
          const Divider(height: 24),
          _CredentialRow(Icons.person, "Username", username, false),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text("Copy Email & Password"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: "Email: $email\nPassword: $password"));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Copied!"), backgroundColor: Colors.green),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _CredentialRow(IconData icon, String label, String value, bool important) {
    return Row(
      children: [
        Icon(icon, color: important ? Colors.blue : Colors.grey[700]),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontWeight: important ? FontWeight.bold : null)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Instructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      "Your account is currently pending approval",
      "Save your login credentials securely",
      "Use the email and password above once approved",
      "Email format (@gmail.com) cannot be changed",
      "Contact the system admin if you need help",
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
               Text(
                "Important Notes",
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.amber[900]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("• ", style: TextStyle(color: Colors.amber.shade800)),
                  Expanded(child: Text(text)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
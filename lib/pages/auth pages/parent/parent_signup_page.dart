import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/appbar/theme_toggle_button.dart';
import '../../../widgets/navigation/page_transition.dart';
import '../auth buttons widgets/signup_button.dart';
import '../form fields widgets/password_text_field.dart';
import '../login_page.dart';

class ParentSignUpPage extends StatefulWidget {
  const ParentSignUpPage({super.key});

  @override
  State<ParentSignUpPage> createState() => _ParentSignUpPageState();
}

class _ParentSignUpPageState extends State<ParentSignUpPage> {
  // ────────────────────────────────────────────
  // Form & Controllers
  // ────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  bool _autoValidate = false;

  final _parentNameCtrl = TextEditingController();
  final _studentLrnCtrl = TextEditingController();
  final _usernameCtrl   = TextEditingController();
  final _passwordCtrl   = TextEditingController();
  final _confirmCtrl    = TextEditingController();

  // LRN validation state
  bool _validatingLrn = false;
  String? _linkedStudentName;
  String? _linkedStudentId;
  bool _lrnNotFound = false;

  @override
  void dispose() {
    _parentNameCtrl.dispose();
    _studentLrnCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────
  // LRN Real-time Validation
  // ────────────────────────────────────────────
  Future<void> _validateLrn(String value) async {
    final lrn = value.trim();

    // Quick client-side rejection
    if (lrn.isEmpty || lrn.length != 12 || !RegExp(r'^\d{12}$').hasMatch(lrn)) {
      setState(() {
        _linkedStudentName = null;
        _linkedStudentId   = null;
        _lrnNotFound       = lrn.isNotEmpty && lrn.length == 12;
      });
      return;
    }

    setState(() {
      _validatingLrn = true;
      _lrnNotFound   = false;
    });

    try {
      final row = await Supabase.instance.client
          .from('students')
          .select('id, student_name')
          .eq('student_lrn', lrn)
          .maybeSingle();

      if (row != null && mounted) {
        setState(() {
          _linkedStudentName = row['student_name'] as String?;
          _linkedStudentId   = row['id'] as String?;
          _lrnNotFound       = false;
        });
      } else if (mounted) {
        setState(() {
          _linkedStudentName = null;
          _linkedStudentId   = null;
          _lrnNotFound       = true;
        });
      }
    } catch (e) {
      debugPrint('LRN lookup failed: $e');
      if (mounted) {
        setState(() {
          _linkedStudentName = null;
          _linkedStudentId   = null;
          _lrnNotFound       = false; // don't show not-found when error
        });
      }
    } finally {
      if (mounted) setState(() => _validatingLrn = false);
    }
  }

  // ────────────────────────────────────────────
  // Registration Flow
  // ────────────────────────────────────────────
  Future<void> _registerParent() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _autoValidate = true);
      return;
    }

    if (_linkedStudentId == null || _linkedStudentName == null) {
      _showError("Please enter a valid, existing student LRN.");
      return;
    }

    _showLoading("Creating parent account...");

    final supabase = Supabase.instance.client;
    String? authUid;

    try {
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text.trim();
      final fullName = _parentNameCtrl.text.trim();
      final email    = '$username@parent.app';

      // 1. Username uniqueness check
      if (await _usernameAlreadyExists(username)) {
        _showError("Username already taken. Please choose another.");
        return;
      }

      // 2. Create auth user
      final authRes = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final user = authRes.user;
      if (user == null) throw Exception('Authentication signup failed');

      authUid = user.id;

      // 3. Create user record (role = parent)
      await supabase.from('users').insert({
        'id': authUid,
        'username': username,
        'role': 'parent',
      });

      // 4. Split name (very simple heuristic)
      final nameParts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      final firstName = nameParts.isNotEmpty ? nameParts.first : fullName;
      final lastName  = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      // 5. Create parent profile
      await supabase.from('parents').insert({
        'id': authUid,
        'first_name': firstName,
        'last_name': lastName.isNotEmpty ? lastName : null,
        'parent_name': fullName,
        'username': username,
        'email': email,
      });

      // 6. Link to student (best effort — non-blocking)
      try {
        await supabase.from('parent_student_relationships').insert({
          'parent_id': authUid,
          'student_id': _linkedStudentId,
          'relationship_type': 'parent', // can be 'guardian', 'mother', etc. later
        });
      } catch (linkErr) {
        debugPrint('Could not create parent-student link (non-fatal): $linkErr');
      }

      if (!mounted) return;

      Navigator.pop(context); // close loading

      await _showSuccessDialog(
        username: username,
        email: email,
        password: password,
        studentName: _linkedStudentName!,
      );
    } catch (e, st) {
      debugPrint('Parent registration failed:\n$e\n$st');

      // Attempt rollback
      if (authUid != null) {
        await _rollbackUser(authUid);
      }

      if (mounted) {
        Navigator.pop(context); // ensure loading is closed
        _showError(_humanFriendlyError(e.toString()));
      }
    }
  }

  Future<bool> _usernameAlreadyExists(String username) async {
    final res = await Supabase.instance.client
        .from('users')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    return res != null;
  }

  Future<void> _rollbackUser(String uid) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase.from('parents').delete().eq('id', uid);
      await supabase.from('users').delete().eq('id', uid);
      await supabase.auth.admin.deleteUser(uid);
    } catch (e) {
      debugPrint('Rollback incomplete: $e');
    }
  }

  String _humanFriendlyError(String error) {
    final msg = error.toLowerCase();
    if (msg.contains('duplicate') || msg.contains('unique constraint')) {
      return "Username already exists.";
    }
    if (msg.contains('foreign key') || msg.contains('constraint')) {
      return "Invalid data provided. Please check your input.";
    }
    return "Registration failed. Please try again later.";
  }

  // ────────────────────────────────────────────
  // Dialog Helpers
  // ────────────────────────────────────────────
  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset('assets/animation/loading_rainbow.json', height: 80),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
    required String studentName,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: SuccessContent(
          username: username,
          email: email,
          password: password,
          studentName: studentName,
          onContinue: () {
            Navigator.pop(context);
            _navigateToLogin();
          },
        ),
      ),
    );
  }

  Future<void> _navigateToLogin() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageTransition(page: const LoginPage(loginType: LoginType.parent)),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    Navigator.maybePop(context); // close loading if open

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
                    parentNameCtrl: _parentNameCtrl,
                    studentLrnCtrl: _studentLrnCtrl,
                    usernameCtrl: _usernameCtrl,
                    passwordCtrl: _passwordCtrl,
                    confirmCtrl: _confirmCtrl,
                    validatingLrn: _validatingLrn,
                    linkedStudentName: _linkedStudentName,
                    lrnNotFound: _lrnNotFound,
                    onLrnChanged: _validateLrn,
                    onSignUp: _registerParent,
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
        _InfoNoteBanner(),
        const SizedBox(height: 32),
        CircleAvatar(
          radius: 70,
          backgroundColor: Colors.white.withOpacity(0.9),
          child: Icon(
            Icons.family_restroom,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Parent Sign Up",
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          "Link to your child and create your account",
          style: TextStyle(color: Colors.white.withOpacity(0.85)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _InfoNoteBanner extends StatelessWidget {
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
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Just enter your username.\n@parent.app is added automatically.",
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
  final TextEditingController parentNameCtrl;
  final TextEditingController studentLrnCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool validatingLrn;
  final String? linkedStudentName;
  final bool lrnNotFound;
  final ValueChanged<String> onLrnChanged;
  final VoidCallback onSignUp;

  const _FormCard({
    required this.formKey,
    required this.autoValidate,
    required this.parentNameCtrl,
    required this.studentLrnCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.validatingLrn,
    required this.linkedStudentName,
    required this.lrnNotFound,
    required this.onLrnChanged,
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
            _field(
              controller: parentNameCtrl,
              label: "Parent Full Name",
              icon: Icons.person,
              hint: "e.g. Juan Santos",
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            _LrnField(
              controller: studentLrnCtrl,
              validating: validatingLrn,
              linkedName: linkedStudentName,
              notFound: lrnNotFound,
              onChanged: onLrnChanged,
            ),
            if (linkedStudentName != null) ...[
              const SizedBox(height: 12),
              _SuccessBanner(name: linkedStudentName!),
            ],
            if (lrnNotFound && studentLrnCtrl.text.trim().length == 12) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: "No student found with this LRN"),
            ],
            const SizedBox(height: 24),
            _UsernameField(controller: usernameCtrl),
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
            const SizedBox(height: 32),
            SignUpButton(text: "Sign Up", onPressed: onSignUp),
            const SizedBox(height: 16),
            _LoginLink(),
          ],
        ),
      ),
    );
  }

  Widget _field({
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

class _LrnField extends StatelessWidget {
  final TextEditingController controller;
  final bool validating;
  final String? linkedName;
  final bool notFound;
  final ValueChanged<String> onChanged;

  const _LrnField({
    required this.controller,
    required this.validating,
    required this.linkedName,
    required this.notFound,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget? suffix;

    if (validating) {
      suffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    } else if (linkedName != null) {
      suffix = const Icon(Icons.check_circle, color: Colors.green);
    } else if (notFound) {
      suffix = const Icon(Icons.error_outline, color: Colors.red);
    }

    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: "Student LRN (12 digits)",
        hintText: "123456789012",
        prefixIcon: const Icon(Icons.confirmation_number),
        suffixIcon: suffix,
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
        if (val.length != 12 || !RegExp(r'^\d{12}$').hasMatch(val)) {
          return 'Must be exactly 12 digits';
        }
        if (linkedName == null && notFound) return 'Student not found';
        return null;
      },
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String name;
  const _SuccessBanner({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Student found: $name",
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsernameField extends StatelessWidget {
  final TextEditingController controller;

  const _UsernameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Username",
            hintText: "e.g. juanparent2023",
            prefixIcon: const Icon(Icons.account_circle),
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
            if (val.contains('@')) return "Don't include @parent.app";
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(val)) {
              return 'Letters, numbers, underscore only';
            }
            return null;
          },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 6),
          child: Text(
            "→ Login with: yourusername@parent.app",
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
            PageTransition(page: const LoginPage(loginType: LoginType.parent)),
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
class SuccessContent extends StatelessWidget {
  final String username;
  final String email;
  final String password;
  final String studentName;
  final VoidCallback onContinue;

  const SuccessContent({
    super.key,
    required this.username,
    required this.email,
    required this.password,
    required this.studentName,
    required this.onContinue,
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
        const SizedBox(height: 24),
        _LinkedStudentCard(studentName: studentName),
        const SizedBox(height: 20),
        _CredentialsSection(
          username: username,
          email: email,
          password: password,
        ),
        const SizedBox(height: 24),
        _Instructions(studentName: studentName),
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
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}

class _LinkedStudentCard extends StatelessWidget {
  final String studentName;
  const _LinkedStudentCard({required this.studentName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.school, color: Colors.purple.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Linked to",
                  style: TextStyle(color: Colors.purple.shade800, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  studentName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialsSection extends StatelessWidget {
  final String username, email, password;

  const _CredentialsSection({
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
          _CredentialLine(Icons.email, "Email", email, true),
          const Divider(height: 28),
          _CredentialLine(Icons.lock, "Password", password, true),
          const Divider(height: 28),
          _CredentialLine(Icons.person, "Username", username, false),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text("Copy Email + Password"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: "Email: $email\nPassword: $password"));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Copied to clipboard"),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _CredentialLine(IconData icon, String label, String value, bool important) {
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
              Text(
                value,
                style: TextStyle(fontWeight: important ? FontWeight.bold : null),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Instructions extends StatelessWidget {
  final String studentName;

  const _Instructions({required this.studentName});

  @override
  Widget build(BuildContext context) {
    final items = [
      "You are now linked to $studentName",
      "Use the email & password above to log in",
      "Save your credentials securely",
      "@parent.app format cannot be changed",
      "Monitor your child's reading progress in the dashboard",
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                "Next steps",
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue),
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
                  Text("• ", style: TextStyle(color: Colors.blue.shade700)),
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
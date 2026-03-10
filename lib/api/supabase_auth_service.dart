import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupabaseAuthService {
  static final _supabase = Supabase.instance.client;

  /// Login with email + password using Supabase Auth
  /// Supports both email and username (auto-detects role and converts format)
  static Future<Map<String, dynamic>> login(
    String emailOrUsername,
    String password,
  ) async {
    String email = emailOrUsername;

    // If input doesn't contain @, try to detect role and convert format
    if (!emailOrUsername.contains('@')) {
      // Try to find user in database to determine role
      final userCheck =
          await _supabase
              .from('users')
              .select('id, role, username')
              .eq('username', emailOrUsername)
              .maybeSingle();

      if (userCheck != null) {
        final role = userCheck['role'] as String?;

        // Determine email format based on role
        switch (role) {
          case 'student':
            email = '$emailOrUsername@student.app';
            break;
          case 'teacher':
            // Try to get teacher email from teachers table
            final teacherCheck =
                await _supabase
                    .from('teachers')
                    .select('teacher_email')
                    .eq('id', userCheck['id'])
                    .maybeSingle();

            if (teacherCheck != null && teacherCheck['teacher_email'] != null) {
              email = teacherCheck['teacher_email'] as String;
            } else {
              // Fallback to gmail format
              email = '$emailOrUsername@gmail.com';
            }
            break;
          case 'parent':
            email = '$emailOrUsername@parent.app';
            break;
          case 'admin':
            // For admin, we need the actual email
            throw Exception(
              'Please use your full email address for admin login',
            );
          default:
            // Default to student format
            email = '$emailOrUsername@student.app';
        }
      } else {
        // User not found in database, default to student format
        email = '$emailOrUsername@student.app';
      }
    }

    // Final attempt with determined email (or original if it already contained @)
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Login failed. No user returned.');
    }

    final roleRow =
        await _supabase
            .from('users')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();

    final role = roleRow?['role'] ?? 'student';

    // Check if teacher account status is active before allowing login
    if (role == 'teacher') {
      final teacherCheck =
          await _supabase
              .from('teachers')
              .select('account_status')
              .eq('id', user.id)
              .maybeSingle();

      final accountStatus =
          teacherCheck?['account_status'] as String? ?? 'pending';

      if (accountStatus == 'pending') {
        // Sign out the user since they shouldn't be logged in
        await _supabase.auth.signOut();
        throw Exception(
          'Your account is pending approval. Please contact an administrator to approve your account before logging in.',
        );
      }

      if (accountStatus == 'inactive') {
        // Sign out the user if account is inactive
        await _supabase.auth.signOut();
        throw Exception(
          'Your account has been deactivated. Please contact an administrator for assistance.',
        );
      }

      if (accountStatus != 'active') {
        // Sign out the user if account is not active (any other status)
        await _supabase.auth.signOut();
        throw Exception(
          'Your account is not active. Please contact an administrator for assistance.',
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('id', user.id);
    await prefs.setString('role', role);

    return {'user': user.toJson(), 'role': role};
  }

  /// Logout with Supabase
  static Future<void> logout() async {
    await _supabase.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Get current session profile (from Supabase Auth + custom users table + role-specific table)
  static Future<Map<String, dynamic>?> getAuthProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('No logged in user');

    // Get user data from users table
    final userProfile =
        await _supabase.from('users').select().eq('id', user.id).maybeSingle();

    // Get role-specific profile data
    Map<String, dynamic>? roleProfile;
    final role = userProfile?['role'] as String?;

    if (role == 'teacher') {
      roleProfile =
          await _supabase
              .from('teachers')
              .select()
              .eq('id', user.id)
              .maybeSingle();
    } else if (role == 'student') {
      roleProfile =
          await _supabase
              .from('students')
              .select()
              .eq('id', user.id)
              .maybeSingle();
    } else if (role == 'parent') {
      roleProfile =
          await _supabase
              .from('parents')
              .select()
              .eq('id', user.id)
              .maybeSingle();
    } else if (role == 'admin') {
      roleProfile = userProfile;
    }

    return {'user': user.toJson(), 'profile': roleProfile ?? userProfile};
  }

  /// Check if user is logged in
  static bool isLoggedIn() {
    return _supabase.auth.currentUser != null;
  }

  /// Get current user ID
  static String? getCurrentUserId() {
    return _supabase.auth.currentUser?.id;
  }

  /// Get current user role
  static Future<String?> getCurrentUserRole() async {
    final userId = getCurrentUserId();
    if (userId == null) return null;

    final roleRow =
        await _supabase
            .from('users')
            .select('role')
            .eq('id', userId)
            .maybeSingle();

    return roleRow?['role'] as String?;
  }
}

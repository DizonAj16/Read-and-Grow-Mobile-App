import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service class for handling authentication operations with Supabase
/// Manages login, logout, session management, and user profile retrieval
class SupabaseAuthService {
  // Supabase client instance
  static final _supabase = Supabase.instance.client;

  // Constants for role-based email domains
  static const String _studentEmailDomain = '@student.app';
  static const String _parentEmailDomain = '@parent.app';
  static const String _teacherEmailFallback = '@gmail.com';

  /// Login with email + password using Supabase Auth
  /// Supports both email and username (auto-detects role and converts format)
  /// 
  /// Parameters:
  ///   - emailOrUsername: Can be either a full email or a username
  ///   - password: User's password
  /// 
  /// Returns: Map containing user data and role
  /// Throws: Exception if login fails or account is not active
  static Future<Map<String, dynamic>> login(
    String emailOrUsername,
    String password,
  ) async {
    // Convert username to email format if needed
    final email = await _convertToEmail(emailOrUsername);
    
    // Attempt authentication with Supabase
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Login failed. No user returned.');
    }

    // Get user role from database
    final role = await _getUserRole(user.id);
    
    // Validate teacher account status if applicable
    await _validateTeacherAccountStatus(user.id, role);

    // Save user data to SharedPreferences
    await _saveUserToPrefs(user.id, role);

    return {'user': user.toJson(), 'role': role};
  }

  /// Convert username to email format based on user role
  /// 
  /// Parameters:
  ///   - input: Can be email or username
  /// 
  /// Returns: Properly formatted email address
  static Future<String> _convertToEmail(String input) async {
    // If input already contains @, it's likely already an email
    if (input.contains('@')) {
      return input;
    }

    // Try to find user in database to determine role
    final userCheck = await _supabase
        .from('users')
        .select('id, role, username')
        .eq('username', input)
        .maybeSingle();

    if (userCheck != null) {
      final role = userCheck['role'] as String?;
      return await _formatEmailByRole(input, role);
    }

    // User not found in database, default to student format
    return '$input$_studentEmailDomain';
  }

  /// Format email based on user role
  /// 
  /// Parameters:
  ///   - username: The username to format
  ///   - role: User's role (student, teacher, parent, admin)
  /// 
  /// Returns: Formatted email address for the role
  static Future<String> _formatEmailByRole(String username, String? role) async {
    switch (role) {
      case 'student':
        return '$username$_studentEmailDomain';
        
      case 'teacher':
        // Try to get teacher email from teachers table
        final teacherEmail = await _getTeacherEmail(username);
        if (teacherEmail != null) {
          return teacherEmail;
        }
        // Fallback to gmail format
        return '$username$_teacherEmailFallback';
        
      case 'parent':
        return '$username$_parentEmailDomain';
        
      case 'admin':
        // Admin must use full email
        throw Exception(
          'Please use your full email address for admin login',
        );
        
      default:
        // Default to student format
        return '$username$_studentEmailDomain';
    }
  }

  /// Get teacher's email from teachers table
  /// 
  /// Parameters:
  ///   - username: Teacher's username
  /// 
  /// Returns: Teacher's email if found, null otherwise
  static Future<String?> _getTeacherEmail(String username) async {
    try {
      // First find user by username
      final user = await _supabase
          .from('users')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (user == null) return null;

      // Then get teacher's email
      final teacher = await _supabase
          .from('teachers')
          .select('teacher_email')
          .eq('id', user['id'])
          .maybeSingle();

      return teacher?['teacher_email'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get user role from database
  /// 
  /// Parameters:
  ///   - userId: The user's ID
  /// 
  /// Returns: User's role as string, defaults to 'student' if not found
  static Future<String> _getUserRole(String userId) async {
    final roleRow = await _supabase
        .from('users')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    return roleRow?['role'] as String? ?? 'student';
  }

  /// Validate teacher account status before allowing login
  /// 
  /// Parameters:
  ///   - userId: The teacher's user ID
  ///   - role: User's role (only checks if role is 'teacher')
  /// 
  /// Throws: Exception if account is pending, inactive, or not active
  static Future<void> _validateTeacherAccountStatus(
    String userId,
    String role,
  ) async {
    if (role != 'teacher') return;

    final teacherCheck = await _supabase
        .from('teachers')
        .select('account_status')
        .eq('id', userId)
        .maybeSingle();

    final accountStatus = teacherCheck?['account_status'] as String? ?? 'pending';

    switch (accountStatus) {
      case 'pending':
        await _supabase.auth.signOut();
        throw Exception(
          'Your account is pending approval. Please contact an administrator to approve your account before logging in.',
        );
        
      case 'inactive':
        await _supabase.auth.signOut();
        throw Exception(
          'Your account has been deactivated. Please contact an administrator for assistance.',
        );
        
      case 'active':
        // Account is active, allow login
        break;
        
      default:
        await _supabase.auth.signOut();
        throw Exception(
          'Your account is not active. Please contact an administrator for assistance.',
        );
    }
  }

  /// Save user data to SharedPreferences
  /// 
  /// Parameters:
  ///   - userId: The user's ID
  ///   - role: User's role
  static Future<void> _saveUserToPrefs(String userId, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('id', userId);
    await prefs.setString('role', role);
  }

  /// Logout user and clear session data
  static Future<void> logout() async {
    await _supabase.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Get current session profile (from Supabase Auth + custom users table + role-specific table)
  /// 
  /// Returns: Map containing user data and role-specific profile
  /// Throws: Exception if no user is logged in
  static Future<Map<String, dynamic>?> getAuthProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('No logged in user');

    // Get user data from users table
    final userProfile = await _supabase
        .from('users')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    // Get role-specific profile data
    final roleProfile = await _getRoleSpecificProfile(
      user.id,
      userProfile?['role'] as String?,
    );

    return {
      'user': user.toJson(),
      'profile': roleProfile ?? userProfile,
    };
  }

  /// Get role-specific profile data from appropriate table
  /// 
  /// Parameters:
  ///   - userId: The user's ID
  ///   - role: User's role (student, teacher, parent, admin)
  /// 
  /// Returns: Role-specific profile data or null
  static Future<Map<String, dynamic>?> _getRoleSpecificProfile(
    String userId,
    String? role,
  ) async {
    switch (role) {
      case 'teacher':
        return await _supabase
            .from('teachers')
            .select()
            .eq('id', userId)
            .maybeSingle();
            
      case 'student':
        return await _supabase
            .from('students')
            .select()
            .eq('id', userId)
            .maybeSingle();
            
      case 'parent':
        return await _supabase
            .from('parents')
            .select()
            .eq('id', userId)
            .maybeSingle();
            
      case 'admin':
        // Admin profile is the same as user profile
        return null;
        
      default:
        return null;
    }
  }

  /// Check if user is currently logged in
  /// 
  /// Returns: True if user is logged in, false otherwise
  static bool isLoggedIn() {
    return _supabase.auth.currentUser != null;
  }

  /// Get current user ID
  /// 
  /// Returns: User ID if logged in, null otherwise
  static String? getCurrentUserId() {
    return _supabase.auth.currentUser?.id;
  }

  /// Get current user role
  /// 
  /// Returns: User role as string, null if not logged in or role not found
  static Future<String?> getCurrentUserRole() async {
    final userId = getCurrentUserId();
    if (userId == null) return null;

    final roleRow = await _supabase
        .from('users')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    return roleRow?['role'] as String?;
  }
}
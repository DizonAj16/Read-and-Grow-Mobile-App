import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_model.dart';
import '../models/teacher_model.dart';
import '../utils/data_validators.dart';
import '../utils/database_helpers.dart';
import '../utils/file_validator.dart';
import '../utils/validators.dart';

class UserService {

  // ── Supabase client instance ───────────────
  static final _sb = Supabase.instance.client;

  // ── Private helpers ────────────────────────

  /// Returns the stored base URL, falling back to the Android emulator localhost.
  static Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('base_url') ?? 'http://10.0.2.2:8000/api';
  }

  /// Builds standard auth headers for HTTP requests.
  static Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Accept':        'application/json',
    'Content-Type':  'application/json',
  };

  // ── Local storage helpers ──────────────────

  /// Saves teacher details to SharedPreferences from a raw JSON map.
  static Future<void> storeTeacherDetails(Map<String, dynamic> details) async {
    try {
      final teacher = Teacher.fromJson(details);
      await teacher.saveToPrefs();
    } catch (e) {
      debugPrint('Error storing teacher details: $e');
    }
  }

  /// Saves student details to SharedPreferences from a raw JSON map.
  static Future<void> storeStudentDetails(Map<String, dynamic> details) async {
    try {
      final student = Student.fromJson(details);
      await student.saveToPrefs();
    } catch (e) {
      debugPrint('Error storing student details: $e');
    }
  }

  // ── Student registration ───────────────────

  /// Registers a new student: validates inputs, creates auth account,
  /// inserts user and student records. Rolls back on partial failure.
  static Future<Map<String, dynamic>?> registerStudent(Map<String, dynamic> data) async {
    try {
      // Validate student data before registration
      final studentData = {
        'student_name': data['student_name'],
        'student_lrn':  data['student_lrn'],
        'username':     data['student_username'],
      };

      final validationErrors = DataValidators.validateStudentData(studentData);
      if (DataValidators.hasErrors(validationErrors)) {
        return {'error': DataValidators.getErrorMessage(validationErrors)};
      }

      // Validate username
      final usernameError = Validators.validateUsername(data['student_username'] as String?);
      if (usernameError != null) return {'error': usernameError};

      // Validate password
      final passwordError = Validators.validatePassword(data['student_password'] as String?);
      if (passwordError != null) return {'error': passwordError};

      // Check for duplicate username
      final usernameExists = await DatabaseHelpers.safeExists(
        supabase: _sb,
        table:    'users',
        filters:  {'username': data['student_username']},
      );
      if (usernameExists) return {'error': 'Username already exists'};

      // Check for duplicate LRN
      final lrnExists = await DatabaseHelpers.safeExists(
        supabase: _sb,
        table:    'students',
        filters:  {'student_lrn': data['student_lrn']},
      );
      if (lrnExists) return {'error': 'LRN already exists'};

      // Step 1: Create Supabase Auth account first
      final authEmail = "${data['student_username']}@student.app";
      String? userId;

      try {
        final authResponse = await _sb.auth.signUp(
          email:    authEmail,
          password: data['student_password'] as String,
          data: {
            'username': data['student_username'],
            'name':     data['student_name'],
          },
        );

        if (authResponse.user == null) {
          return {'error': 'Failed to create authentication account'};
        }
        userId = authResponse.user!.id;
      } catch (e) {
        debugPrint('❌ Auth signup error: $e');
        return {'error': 'Failed to create authentication account: $e'};
      }

      // Step 2: Create user record
      final userData = {
        'id':       userId,
        'username': data['student_username'],
        'password': data['student_password'],
        'role':     'student',
      };

      final userResponse = await DatabaseHelpers.safeInsert(
        supabase: _sb,
        table:    'users',
        data:     userData,
      );

      if (userResponse == null || userResponse.containsKey('error')) {
        // Rollback: delete auth user if user record creation failed
        try {
          await _sb.auth.admin.deleteUser(userId);
        } catch (e) {
          debugPrint('Error rolling back auth user: $e');
        }
        return userResponse ?? {'error': 'Failed to create user account'};
      }

      // Step 3: Create student record linked to the user
      final studentDataMap = <String, dynamic>{
        'id':              userId,
        'student_name':    data['student_name'],
        'student_lrn':     data['student_lrn'],
        'student_grade':   data['student_grade']?.toString().trim(),
        'student_section': data['student_section']?.toString().trim(),
        'username':        data['student_username'],
      };

      // Remove null/empty values
      studentDataMap.removeWhere((key, value) => value == null || value.toString().isEmpty);

      final studentResponse = await DatabaseHelpers.safeInsert(
        supabase: _sb,
        table:    'students',
        data:     studentDataMap,
      );

      if (studentResponse == null || studentResponse.containsKey('error')) {
        // Rollback: delete user record if student creation failed
        try {
          await _sb.from('users').delete().eq('id', userId);
        } catch (e) {
          debugPrint('Error rolling back user creation: $e');
        }
        return studentResponse ?? {'error': 'Failed to create student profile'};
      }

      debugPrint('✅ Student created successfully!');
      return studentResponse;

    } on PostgrestException catch (e) {
      debugPrint('❌ Supabase error: ${e.message}');
      return {'error': e.message};
    } catch (e) {
      debugPrint('❌ Error registering student: $e');
      return {'error': e.toString()};
    }
  }

  // ── Teacher registration ───────────────────

  /// Validates and inserts a new teacher record into the database.
  static Future<Map<String, dynamic>?> registerTeacher(Map<String, dynamic> body) async {
    final supabase = Supabase.instance.client;
    try {
      // Validate teacher data
      final validationErrors = DataValidators.validateTeacherData(body);
      if (DataValidators.hasErrors(validationErrors)) {
        return {'error': DataValidators.getErrorMessage(validationErrors)};
      }

      // Check for duplicate email
      final emailExists = await DatabaseHelpers.safeExists(
        supabase: supabase,
        table:    'teachers',
        filters:  {'teacher_email': body['teacher_email']},
      );
      if (emailExists) return {'error': 'Email already exists'};

      // Clean data - remove null values
      final cleanBody = Map<String, dynamic>.from(
        body..removeWhere((key, value) => value == null || value.toString().trim().isEmpty),
      );

      final response = await DatabaseHelpers.safeInsert(
        supabase: supabase,
        table:    'teachers',
        data:     cleanBody,
      );

      if (response != null && response.containsKey('error')) return response;

      return response;
    } catch (e) {
      debugPrint('Error registering teacher: $e');
      return {'error': e.toString()};
    }
  }

  // ── Fetch methods ──────────────────────────

  /// Fetches all students from Supabase.
  static Future<List<Student>> fetchAllStudents() async {
    final supabase = Supabase.instance.client;
    try {
      final response = await supabase.from('students').select();

      return (response as List)
          .map((json) => Student.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      debugPrint('Error fetching students: $e');
      throw Exception('Failed to load students');
    }
  }

  /// Fetches all teachers from Supabase, enriched with usernames from the users table.
  /// Falls back to the HTTP API if Supabase fails.
  static Future<List<Teacher>> fetchAllTeachers() async {
    final supabase = Supabase.instance.client;
    try {
      // Fetch teachers directly from Supabase to ensure we get is_approved field
      // Use a simpler approach - fetch all fields and handle username separately if needed
      final response = await supabase
          .from('teachers')
          .select('*')
          .order('created_at', ascending: false);

      if (response.isEmpty) {
        debugPrint('No teachers found in database');
        return [];
      }

      // Convert to Teacher objects
      final teachersList = <Teacher>[];

      // Fetch usernames individually (more reliable)
      // Note: Batch fetching with .in_() may not be available in all Supabase versions
      final usernameMap = <String, String>{};

      // Try to fetch usernames in parallel for better performance
      final userIds = response
          .map((json) => json['id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      if (userIds.isNotEmpty && userIds.length <= 50) { // Limit to avoid too many queries
        try {
          // Fetch usernames in parallel
          final futures = userIds.map((userId) async {
            try {
              final userData = await supabase
                  .from('users')
                  .select('id, username')
                  .eq('id', userId)
                  .maybeSingle();
              if (userData != null && userData['username'] != null) {
                return MapEntry(userId, userData['username'].toString());
              }
            } catch (e) {
              debugPrint('Could not fetch username for user $userId: $e');
            }
            return null;
          });

          final results = await Future.wait(futures);
          for (final entry in results) {
            if (entry != null) usernameMap[entry.key] = entry.value;
          }
        } catch (e) {
          debugPrint('Could not fetch usernames: $e');
          // Continue without usernames - they're optional
        }
      }

      for (final json in response) {
        try {
          final data = Map<String, dynamic>.from(json);

          // Add username if available
          final userId = data['id']?.toString();
          if (userId != null && usernameMap.containsKey(userId)) {
            data['username'] = usernameMap[userId];
          }

          // Ensure account_status defaults to 'pending' if null
          if (data['account_status'] == null) {
            data['account_status'] = 'pending';
          }

          // Derive is_approved from account_status for backward compatibility (if model needs it)
          // Only set if is_approved field doesn't exist in data
          if (!data.containsKey('is_approved')) {
            data['is_approved'] = data['account_status'] == 'active';
          }

          // Handle teacher_id field if id is not present
          if (data['id'] == null && data['teacher_id'] != null) {
            data['id'] = data['teacher_id'];
          }

          teachersList.add(Teacher.fromJson(data));
        } catch (e, stackTrace) {
          debugPrint('Error parsing teacher data: $e');
          debugPrint('Stack trace: $stackTrace');
          debugPrint('Problematic JSON: $json');
          // Skip this teacher and continue with others
          continue;
        }
      }

      debugPrint('✅ Successfully fetched ${teachersList.length} teachers');
      return teachersList;

    } catch (e) {
      debugPrint('❌ Error fetching teachers from Supabase: $e');

      // Fallback to HTTP API if Supabase fails
      try {
        debugPrint('Attempting HTTP API fallback...');

        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token == null) {
          debugPrint('No auth token found for HTTP fallback');
          throw Exception('No auth token found');
        }

        final baseUrl = await _getBaseUrl();
        final url     = Uri.parse('$baseUrl/teachers/');
        debugPrint('Fetching from: $url');

        final response = await http.get(url, headers: _authHeaders(token));
        debugPrint('HTTP Response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data     = jsonDecode(response.body);
          final teachers = (data['teachers'] as List? ?? data as List)
              .map((json) => Teacher.fromJson(Map<String, dynamic>.from(json)))
              .toList();
          debugPrint('✅ Successfully fetched ${teachers.length} teachers from HTTP API');
          return teachers;
        } else {
          debugPrint('HTTP API returned error: ${response.statusCode} - ${response.body}');
          throw Exception('Failed to load teachers: HTTP ${response.statusCode}');
        }
      } catch (fallbackError) {
        debugPrint('❌ Error in fallback HTTP fetch: $fallbackError');
        // Return empty list instead of throwing to prevent UI crash
        debugPrint('Returning empty teacher list');
        return [];
      }
    }
  }

  // ── HTTP user management ───────────────────

  /// Deletes a user via the HTTP API (role-aware endpoint).
  static Future<http.Response> deleteUser(dynamic userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('No auth token found');

    final role = prefs.getString('role');
    final base = await _getBaseUrl();
    final url  = role == 'teacher'
        ? '$base/teachers/users/$userId'
        : '$base/admins/users/$userId';

    return http.delete(Uri.parse(url), headers: _authHeaders(token));
  }

  /// Updates a user via the HTTP API (role-aware endpoint).
  static Future<http.Response> updateUser({
    required dynamic userId,
    required Map<String, dynamic> body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('No auth token found');

    final role = prefs.getString('role');
    final base = await _getBaseUrl();
    final url  = role == 'teacher'
        ? '$base/teachers/users/$userId'
        : '$base/admins/users/$userId';

    return http.put(
      Uri.parse(url),
      headers: _authHeaders(token),
      body:    jsonEncode(body),
    );
  }

  // ── Profile picture upload ─────────────────

  /// Uploads a profile picture to Supabase Storage and updates the DB record.
  /// On web, [fileBytes] must be provided. On mobile, [filePath] is used.
  static Future<String?> uploadProfilePicture({
    required String    userId,
    required String    role,
    required String    filePath,
    Uint8List?         fileBytes, // ✅ ADD THIS for web support
  }) async {
    final supabase = Supabase.instance.client;

    try {
      debugPrint('📸 [UPLOAD_PROFILE] Starting upload - User: $userId, Role: $role');

      // 1️⃣ Validate inputs
      if (userId.isEmpty || !Validators.isValidUUID(userId)) {
        debugPrint('❌ [UPLOAD_PROFILE] Invalid user ID: $userId');
        return null;
      }
      if (role != 'teacher' && role != 'student') {
        debugPrint('❌ [UPLOAD_PROFILE] Invalid role: $role');
        return null;
      }

      // 2️⃣ Get file bytes — web uses passed bytes, mobile reads from file
      late Uint8List bytes;

      if (kIsWeb) {
        // ✅ On web, bytes must be passed in directly
        if (fileBytes == null || fileBytes.isEmpty) {
          debugPrint('❌ [UPLOAD_PROFILE] No file bytes provided for web upload');
          return null;
        }
        bytes = fileBytes;
      } else {
        // ✅ On mobile, read from file path
        final originalFile = File(filePath);
        if (!await originalFile.exists()) {
          debugPrint('❌ [UPLOAD_PROFILE] File does not exist: $filePath');
          return null;
        }

        // Validate file size on mobile
        final sizeValidation = await validateFileSize(
          originalFile,
          limitMB: FileValidator.defaultMaxSizeMB,
        );
        if (!sizeValidation.isValid) {
          debugPrint('❌ [UPLOAD_PROFILE] File too large: ${sizeValidation.getDetailedInfo()}');
          throw FileSizeLimitException(
            FileValidator.backendLimitMessage(FileValidator.defaultMaxSizeMB),
            actualSizeMB: sizeValidation.actualSizeMB,
            limitMB:      sizeValidation.limitMB,
          );
        }

        bytes = await originalFile.readAsBytes();
      }

      debugPrint('📸 [UPLOAD_PROFILE] Got ${bytes.length} bytes');

      // 3️⃣ Determine file extension
      final fileExtension  = filePath.contains('.') ? filePath.split('.').last.toLowerCase() : 'png';
      final validExtension = ['jpg', 'jpeg', 'png'].contains(fileExtension) ? fileExtension : 'png';

      // 4️⃣ Create unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName  = '$userId-$timestamp.$validExtension';

      // 5️⃣ Determine content type
      final contentType = validExtension == 'png' ? 'image/png' : 'image/jpeg';

      // 6️⃣ Upload to Supabase Storage
      const bucket = 'materials';
      debugPrint('📸 [UPLOAD_PROFILE] Uploading to storage...');
      await supabase.storage.from(bucket).uploadBinary(
        fileName,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
      debugPrint('✅ [UPLOAD_PROFILE] File uploaded to storage');

      // 7️⃣ Get public URL
      final publicUrl = supabase.storage.from(bucket).getPublicUrl(fileName);
      if (publicUrl.isEmpty) {
        throw Exception('Failed to get public URL for uploaded file');
      }
      debugPrint('✅ [UPLOAD_PROFILE] Public URL: $publicUrl');

      // 8️⃣ Update database record
      final table        = role == 'teacher' ? 'teachers' : 'students';
      final updateResult = await supabase.from(table).update({
        'profile_picture': publicUrl,
        'updated_at':      DateTime.now().toIso8601String(),
      }).eq('id', userId).select();

      debugPrint('📸 [UPLOAD_PROFILE] Update result: ${updateResult.length} rows updated');

      if (updateResult.isEmpty) {
        throw Exception('Failed to update profile picture in database');
      }

      debugPrint('✅ [UPLOAD_PROFILE] Profile picture uploaded successfully: $publicUrl');
      return publicUrl;

    } on FileSizeLimitException {
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('❌ [UPLOAD_PROFILE] Error uploading profile picture: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  // ── Student self-update ────────────────────

  /// Allows a student to update their own profile fields and username.
  static Future<Map<String, dynamic>?> updateStudentSelf({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    final supabase = Supabase.instance.client;
    try {
      // Update username in users table if provided
      if (data.containsKey('username')) {
        await supabase.from('users').update({'username': data['username']}).eq('id', userId);
      }

      // Build update payload from known fields
      final updatePayload = <String, dynamic>{};
      if (data.containsKey('student_name'))    updatePayload['student_name']    = data['student_name'];
      if (data.containsKey('student_lrn'))     updatePayload['student_lrn']     = data['student_lrn'];
      if (data.containsKey('student_grade'))   updatePayload['student_grade']   = data['student_grade'];
      if (data.containsKey('student_section')) updatePayload['student_section'] = data['student_section'];

      if (updatePayload.isNotEmpty) {
        final updated = await supabase
            .from('students')
            .update(updatePayload)
            .eq('id', userId)
            .select()
            .single();
        return Map<String, dynamic>.from(updated);
      }

      return {};
    } catch (e) {
      debugPrint('Error updating student self: $e');
      return null;
    }
  }

  // ── Admin student management ───────────────

  /// Allows an admin to update a student's profile and username.
  static Future<bool> updateStudentByAdmin({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    final supabase = Supabase.instance.client;
    try {
      // Update username in users table if provided
      if (data.containsKey('username')) {
        await supabase.from('users').update({'username': data['username']}).eq('id', userId);
      }

      // Build update payload from known fields
      final updatePayload = <String, dynamic>{};
      if (data.containsKey('student_name'))    updatePayload['student_name']    = data['student_name'];
      if (data.containsKey('student_lrn'))     updatePayload['student_lrn']     = data['student_lrn'];
      if (data.containsKey('student_grade'))   updatePayload['student_grade']   = data['student_grade'];
      if (data.containsKey('student_section')) updatePayload['student_section'] = data['student_section'];

      if (updatePayload.isNotEmpty) {
        await supabase.from('students').update(updatePayload).eq('id', userId);
      }

      return true;
    } catch (e) {
      debugPrint('Error admin updating student: $e');
      return false;
    }
  }

  /// Deletes a student and all their associated records (cascading delete).
  static Future<bool> deleteStudentByAdmin({required String userId}) async {
    final supabase = Supabase.instance.client;
    try {
      // Fetch students.id for this user
      final studentRow = await supabase
          .from('students')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      final String? studentId = studentRow?['id'] as String?;

      // Delete dependent rows
      if (studentId != null) {
        await supabase.from('student_enrollments').delete().eq('student_id', studentId);
        await supabase.from('student_task_progress').delete().eq('student_id', studentId);
      }

      // student_submissions references users.id
      await supabase.from('student_submissions').delete().eq('student_id', userId);

      // Delete student row, then user row
      await supabase.from('students').delete().eq('id', userId);
      await supabase.from('users').delete().eq('id', userId);

      return true;
    } catch (e) {
      debugPrint('Error admin deleting student: $e');
      return false;
    }
  }

  /// Assigns a reading level to a student by updating their record.
  static Future<bool> assignReadingLevelToStudent({
    required String userId,
    required String readingLevelId,
  }) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase
          .from('students')
          .update({'current_reading_level_id': readingLevelId})
          .eq('id', userId);
      return true;
    } catch (e) {
      debugPrint('Error assigning reading level: $e');
      return false;
    }
  }

  // ── Teacher approval ───────────────────────

  /// Approve or reject a teacher account
  /// Sets account_status to 'active' if approved, 'pending' if rejected.
  static Future<bool> updateTeacherApprovalStatus({
    required String teacherId,
    required bool   isApproved,
  }) async {
    final supabase = Supabase.instance.client;
    try {
      // Set account_status based on approval: 'active' if approved, 'pending' if rejected
      final accountStatus = isApproved ? 'active' : 'pending';

      final result = await supabase
          .from('teachers')
          .update({
            'account_status': accountStatus,
            'updated_at':     DateTime.now().toIso8601String(),
          })
          .eq('id', teacherId)
          .select();

      if (result.isEmpty) {
        debugPrint('No teacher found with ID: $teacherId');
        return false;
      }

      debugPrint('✅ Teacher approval status updated successfully: account_status=$accountStatus');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating teacher approval status: $e');
      return false;
    }
  }
}
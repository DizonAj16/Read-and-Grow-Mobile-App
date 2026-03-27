import 'dart:convert';
import 'dart:io';
import 'package:deped_reading_app_laravel/models/announcement_model.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/classroom_model.dart';
import '../models/student_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/validators.dart';
import '../utils/database_helpers.dart';
import '../utils/file_validator.dart';

class ClassroomService {
  static Future<Map<String, dynamic>?> createClassV2({
    required String className,
    required String gradeLevel,
    required String section,
    required String schoolYear,
    required String classroomCode,
  }) async {
    final supabase = Supabase.instance.client;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        print('No logged-in teacher found');
        return null;
      }

      final teacher =
          await supabase
              .from('teachers')
              .select('id')
              .eq('id', currentUser.id)
              .single();

      if (teacher['id'] == null) {
        print('Teacher record not found');
        return null;
      }

      final response =
          await supabase
              .from('class_rooms')
              .insert({
                'teacher_id': teacher['id'],
                'class_name': className,
                'grade_level': gradeLevel,
                'section': section,
                'school_year': schoolYear,
                'classroom_code': classroomCode,
              })
              .select()
              .single();

      return response;
    } catch (e) {
      print('Error inserting class_room: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchStudentQuizzes(
    String studentId,
  ) async {
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('student_enrollments')
        .select('''
        class_room_id,
        class_room:class_rooms(
          class_name,
          assignments(
            id,
            task:tasks(
              id,
              title,
              quizzes(id, title)
            )
          )
        )
      ''')
        .eq('student_id', studentId);

    List<Map<String, dynamic>> results = [];

    for (var enrollment in response) {
      final classRoom = enrollment['class_room'];
      final className = classRoom['class_name'];
      final assignments = classRoom['assignments'] ?? [];

      for (var assignment in assignments) {
        final task = assignment['task'];
        if (task == null) continue;

        final quizzes = task['quizzes'] ?? [];
        for (var quiz in quizzes) {
          results.add({
            'assignment_id': assignment['id'],
            'quiz_id': quiz['id'],
            'quiz_title': quiz['title'],
            'class_name': className,
            'task_title': task['title'],
          });
        }
      }
    }

    return results;
  }

  static Future<Map<String, dynamic>?> updateClass({
    required String classId,

    required Map<String, dynamic> body,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      final response =
          await supabase
              .from('class_rooms')
              .update(body)
              .eq('id', classId)
              .select()
              .single();

      return response;
    } catch (e) {
      print('Error updating class: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> deleteClass(String classId) async {
    final supabase = Supabase.instance.client;

    try {
      debugPrint('🗑️ [DELETE_CLASS] Starting deletion for class: $classId');

      final response = await supabase.rpc(
        'admin_delete_class',
        params: {'p_class_id': classId},
      );

      debugPrint('✅ [DELETE_CLASS] Successfully deleted class via RPC');
      return response is Map<String, dynamic> ? response : {'id': classId};
    } catch (e) {
      debugPrint('❌ [DELETE_CLASS] Error deleting class: $e');
      // Re-throw the error so the UI can display it
      throw Exception('Failed to delete class: ${e.toString()}');
    }
  }

  static Future<Map<String, dynamic>> getClassDetails(String classId) async {
    final supabase = Supabase.instance.client;

    try {
      final response =
          await supabase
              .from('class_rooms')
              .select(
                '*, student_enrollments(*), teacher:teachers(teacher_name)',
              )
              .eq('id', classId)
              .maybeSingle();

      if (response == null) return {};

      final classDetails = Map<String, dynamic>.from(response as Map);

      final studentCount =
          (classDetails['student_enrollments'] as List<dynamic>?)?.length ?? 0;
      classDetails['student_count'] = studentCount;
      final teacher = classDetails['teacher'];
      classDetails['teacher_name'] =
          teacher != null ? teacher['teacher_name'] ?? 'N/A' : 'N/A';

      return classDetails;
    } catch (e) {
      print('Error fetching class details: $e');
      return {};
    }
  }

  static Future<List<Classroom>> fetchTeacherClasses() async {
    final supabase = Supabase.instance.client;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No logged-in teacher');

      final teacher =
          await supabase
              .from('teachers')
              .select('id')
              .eq('id', currentUser.id)
              .single();

      final teacherId = teacher['id'];
final response = await supabase
    .from('class_rooms')
    .select(
      'id, class_name, grade_level, section, teacher_id, school_year, background_image, student_enrollments(student_id)',
    )
    .eq('teacher_id', teacherId);

      return (response as List<dynamic>).map((json) {
        final data = Map<String, dynamic>.from(json);
        // Count enrollments properly - get the list of enrollments and count them
        final enrollments = data['student_enrollments'] as List?;
        final studentCount =
            (enrollments != null && enrollments.isNotEmpty)
                ? enrollments.length
                : 0;

        data['student_count'] = studentCount;
        return Classroom.fromJson(data);
      }).toList();
    } catch (e) {
      print('Error fetching teacher classes: $e');
      return [];
    }
  }

  static Future<int> fetchStudentCount(String classId) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('class_students')
          .select('id')
          .eq('class_room_id', classId);

      return response.length;
    } catch (e) {
      print('Error fetching student count for class $classId: $e');
      return 0;
    }
  }

  static Future<List<Classroom>> getStudentClasses() async {
    final supabase = Supabase.instance.client;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("No logged-in student");

      final student =
          await supabase
              .from('students')
              .select('id')
              .eq('id', user.id)
              .single();

      final studentId = student['id'];
      final response = await supabase
          .from('student_enrollments')
          .select('''
      class_room_id,
      class_rooms (
        id,
        class_name,
        grade_level,
        section,
        school_year,
        teacher_id,
        background_image,
        teacher:teachers (
          teacher_name,
          teacher_email,
          teacher_position,
          profile_picture
        ),
        student_enrollments (student_id)
      )
    ''')
          .eq('student_id', studentId);

      return (response as List<dynamic>).map((item) {
        final classRoom = Map<String, dynamic>.from(item['class_rooms'] ?? {});
        final teacher = classRoom['teacher'] ?? {};
        final enrollments = classRoom['student_enrollments'] as List? ?? [];

        classRoom['student_count'] = enrollments.length;
        classRoom['teacher_name'] = teacher['teacher_name'];
        classRoom['teacher_email'] = teacher['teacher_email'];
        classRoom['teacher_position'] = teacher['teacher_position'];
        classRoom['teacher_avatar'] = teacher['profile_picture'];

        return Classroom.fromJson(classRoom);
      }).toList();
    } catch (e) {
      print('Error fetching student classes: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> assignStudent({
    required String studentId,
    required String classRoomId,
  }) async {
    final supabase = Supabase.instance.client;

    try {
      debugPrint(
        '📝 [ASSIGN_STUDENT] Starting assignment - Student: $studentId, Class: $classRoomId',
      );

      // 1️⃣ Validate inputs
      if (studentId.isEmpty || !Validators.isValidUUID(studentId)) {
        debugPrint('❌ [ASSIGN_STUDENT] Invalid student ID: $studentId');
        return {'error': 'Invalid student ID provided.'};
      }

      if (classRoomId.isEmpty || !Validators.isValidUUID(classRoomId)) {
        debugPrint('❌ [ASSIGN_STUDENT] Invalid class room ID: $classRoomId');
        return {'error': 'Invalid class room ID provided.'};
      }

      // 2️⃣ Verify student exists
      final studentExists =
          await supabase
              .from('students')
              .select('id, student_name')
              .eq('id', studentId)
              .maybeSingle();

      if (studentExists == null) {
        debugPrint('❌ [ASSIGN_STUDENT] Student not found: $studentId');
        return {'error': 'Student not found.'};
      }

      // 3️⃣ Verify class exists
      final classExists =
          await supabase
              .from('class_rooms')
              .select('id, class_name')
              .eq('id', classRoomId)
              .maybeSingle();

      if (classExists == null) {
        debugPrint('❌ [ASSIGN_STUDENT] Class room not found: $classRoomId');
        return {'error': 'Class room not found.'};
      }

      debugPrint(
        '✅ [ASSIGN_STUDENT] Student "${studentExists['student_name']}" and class "${classExists['class_name']}" verified',
      );

      // 4️⃣ Check if student is already enrolled in ANY class
      final existingEnrollments = await supabase
          .from('student_enrollments')
          .select('class_room_id, class_rooms(class_name)')
          .eq('student_id', studentId);

      if (existingEnrollments.isNotEmpty) {
        final existingEnrollment = existingEnrollments.first;
        final existingClassId = existingEnrollment['class_room_id'] as String?;
        final existingClassName =
            existingEnrollment['class_rooms']?['class_name'] as String?;

        debugPrint(
          '⚠️ [ASSIGN_STUDENT] Student already enrolled in class: $existingClassId ($existingClassName)',
        );

        // If already enrolled in this class, return success
        if (existingClassId == classRoomId) {
          debugPrint(
            '✅ [ASSIGN_STUDENT] Student already enrolled in this class - returning success',
          );
          return {
            'student_id': studentId,
            'class_room_id': classRoomId,
            'message': 'Student already enrolled in this class',
          };
        }

        // If enrolled in a different class, prevent assignment
        debugPrint(
          '❌ [ASSIGN_STUDENT] Cannot assign - student enrolled in different class',
        );
        return {
          'error':
              'Student is already enrolled in "${existingClassName ?? 'another class'}". Please unassign them first.',
          'existing_class_id': existingClassId,
          'existing_class_name': existingClassName,
        };
      }

      // 5️⃣ Proceed with assignment if no existing enrollment
      debugPrint(
        '📝 [ASSIGN_STUDENT] No existing enrollment found - proceeding with assignment',
      );

      final enrollmentDate = DateTime.now().toIso8601String();
      final response =
          await supabase
              .from('student_enrollments')
              .insert({
                'student_id': studentId,
                'class_room_id': classRoomId,
                'enrollment_date': enrollmentDate,
              })
              .select()
              .single();

      debugPrint('✅ [ASSIGN_STUDENT] Successfully assigned student to class');
      return response;
    } catch (e, stackTrace) {
      debugPrint('❌ [ASSIGN_STUDENT] Error assigning student: $e');
      debugPrint('Stack trace: $stackTrace');

      // Check if error is due to duplicate enrollment (database constraint)
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('duplicate') ||
          errorString.contains('unique') ||
          errorString.contains('violates unique constraint') ||
          errorString.contains('primary key')) {
        debugPrint('⚠️ [ASSIGN_STUDENT] Duplicate enrollment detected');
        return {'error': 'Student is already enrolled in this class.'};
      }

      // Check for foreign key violations
      if (errorString.contains('foreign key') ||
          errorString.contains('constraint')) {
        debugPrint('⚠️ [ASSIGN_STUDENT] Foreign key constraint violation');
        return {'error': 'Invalid student or class room ID.'};
      }

      return {
        'error': 'Failed to assign student. Please try again.',
        'details': e.toString(),
      };
    }
  }

  static Future<http.Response> unassignStudent({
    required String studentId,
    required String classRoomId,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase
          .from('student_enrollments')
          .delete()
          .eq('student_id', studentId)
          .eq('class_room_id', classRoomId);

      return http.Response(
        '{"message": "Student unassigned successfully"}',
        200,
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error unassigning student: $e');
      return http.Response(
        '{"error": "Failed to unassign student"}',
        500,
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  static Future<Set<String>> getAssignedStudentIdsForClass(
    String classRoomId,
  ) async {
    try {
      final supabase = Supabase.instance.client;

      final assignedResponse = await supabase
          .from('student_enrollments')
          .select('student_id')
          .eq('class_room_id', classRoomId);

      final assignedIds =
          (assignedResponse as List)
              .map((e) => e['student_id'] as String)
              .toSet();

      return assignedIds;
    } catch (e) {
      print('Error fetching assigned student IDs for class: $e');
      throw Exception('Failed to fetch assigned students');
    }
  }

  static Future<Set<String>> getGloballyAssignedStudentIds() async {
    try {
      final supabase = Supabase.instance.client;

      final assignedResponse = await supabase
          .from('student_enrollments')
          .select('student_id');

      final assignedIds =
          (assignedResponse as List)
              .map((e) => e['student_id'] as String)
              .toSet();

      return assignedIds;
    } catch (e) {
      print('Error fetching globally assigned student IDs: $e');
      throw Exception('Failed to fetch assigned students');
    }
  }

  static Future<List<Student>> getAssignedStudents() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.from('students').select();

      final List<dynamic> list = response;
      return list
          .map((json) => Student.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      print('Error fetching assigned students: $e');
      throw Exception('Failed to fetch assigned students');
    }
  }

  static Future<List<Student>> getUnassignedStudents() async {
    try {
      final supabase = Supabase.instance.client;
      final assignedResponse = await supabase
          .from('student_enrollments')
          .select('student_id');

      final assignedIds =
          (assignedResponse as List)
              .map((e) => e['student_id'] as String)
              .toList();
      final response = await supabase
          .from('students')
          .select()
          .filter('id', 'not.in', '(${assignedIds.join(',')})');

      final List<dynamic> list = response;
      return list
          .map((json) => Student.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      print('Error fetching unassigned students: $e');
      throw Exception('Failed to fetch unassigned students');
    }
  }

  static Future<List<Student>> getAllStudents() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.from('students').select();

      final List<dynamic> list = response;
      return list
          .map((json) => Student.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      print('Error fetching all students: $e');
      throw Exception('Failed to fetch students');
    }
  }

  /// Get students enrolled in a specific class (for classmates view)
  static Future<List<Student>> getStudentsByClass(String classRoomId) async {
    try {
      final supabase = Supabase.instance.client;

      debugPrint(
        '👥 [GET_CLASSMATES] Fetching students for class: $classRoomId',
      );

      // Get all enrollments for this class
      final enrollmentsResponse = await supabase
          .from('student_enrollments')
          .select('student_id')
          .eq('class_room_id', classRoomId);

      if (enrollmentsResponse.isEmpty) {
        debugPrint('⚠️ [GET_CLASSMATES] No students enrolled in this class');
        return [];
      }

      // Extract student IDs
      final studentIds =
          (enrollmentsResponse as List)
              .map((e) => e['student_id'] as String)
              .toList();

      debugPrint(
        '✅ [GET_CLASSMATES] Found ${studentIds.length} enrolled students',
      );

      // Fetch student details
      if (studentIds.isEmpty) {
        return [];
      }

      // Fetch students by IDs using inFilter
      final studentsResponse = await supabase
          .from('students')
          .select()
          .inFilter('id', studentIds);

      final List<dynamic> list = studentsResponse;
      final students =
          list
              .map((json) => Student.fromJson(Map<String, dynamic>.from(json)))
              .toList();

      debugPrint(
        '✅ [GET_CLASSMATES] Retrieved ${students.length} student records',
      );
      return students;
    } catch (e) {
      debugPrint('❌ [GET_CLASSMATES] Error fetching students by class: $e');
      throw Exception('Failed to fetch classmates');
    }
  }

  static Future<Map<String, dynamic>> joinClass(String classCode) async {
    final supabase = Supabase.instance.client;

    try {
      // Validate class code
      final trimmedCode = classCode.trim();
      if (trimmedCode.isEmpty) {
        return {'success': false, 'message': 'Class code cannot be empty.'};
      }

      if (trimmedCode.length < 4) {
        return {'success': false, 'message': 'Invalid class code format.'};
      }

      // 1️⃣ Find the class by its code using safe helpers
      final classData = await DatabaseHelpers.safeGetList(
        supabase: supabase,
        table: 'class_rooms',
        filters: {'classroom_code': trimmedCode},
        limit: 1,
      );

      if (classData.isEmpty) {
        return {
          'success': false,
          'message': 'Class not found for the given code.',
        };
      }

      final classRoom = classData.first;
      final classRoomId = DatabaseHelpers.safeStringFromResult(classRoom, 'id');

      if (classRoomId.isEmpty) {
        return {'success': false, 'message': 'Invalid class data.'};
      }

      // 2️⃣ Get the current user's corresponding student record
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        return {'success': false, 'message': 'User not authenticated.'};
      }

      // Validate user ID
      if (!Validators.isValidUUID(userId)) {
        return {'success': false, 'message': 'Invalid user ID.'};
      }

      final studentData = await DatabaseHelpers.safeGetSingle(
        supabase: supabase,
        table: 'students',
        id: userId,
      );

      if (studentData == null) {
        return {'success': false, 'message': 'Student record not found.'};
      }

      // 3️⃣ Check if already enrolled using safe helpers
      final existingEnrollments = await DatabaseHelpers.safeGetList(
        supabase: supabase,
        table: 'student_enrollments',
        filters: {'student_id': userId, 'class_room_id': classRoomId},
        limit: 1,
      );

      if (existingEnrollments.isNotEmpty) {
        return {
          'success': false,
          'message': 'You are already enrolled in this class.',
        };
      }

      // 4️⃣ Insert new enrollment using safe insert
      final enrollmentData = {
        'student_id': userId,
        'class_room_id': classRoomId,
        'enrollment_date': DateTime.now().toIso8601String(),
      };

      final insertResult = await DatabaseHelpers.safeInsert(
        supabase: supabase,
        table: 'student_enrollments',
        data: enrollmentData,
      );

      if (insertResult != null && insertResult.containsKey('error')) {
        return {
          'success': false,
          'message': insertResult['error'] ?? 'Failed to join class.',
        };
      }

      return {
        'success': true,
        'class': classRoom,
        'enrollment': insertResult,
        'message': 'Successfully joined the class!',
      };
    } catch (e) {
      debugPrint("❌ Error joining class: $e");
      return {
        'success': false,
        'message':
            'An error occurred while joining the class. Please try again.',
      };
    }
  }

static Future<http.Response?> uploadClassBackground({
  required String classId,
  required Uint8List fileBytes,       // ← bytes instead of path
  required String fileName,           // ← original filename for extension
  double sizeLimitMB = FileValidator.defaultMaxSizeMB,
}) async {
  try {
    final supabase = Supabase.instance.client;

    // Validate size from bytes directly (no File needed)
    final sizeValidation = validateFileSizeFromBytes(fileBytes, limitMB: sizeLimitMB);
    if (!sizeValidation.isValid) {
      throw FileSizeLimitException(
        FileValidator.backendLimitMessage(sizeLimitMB),
        actualSizeMB: sizeValidation.actualSizeMB,
        limitMB: sizeLimitMB,
      );
    }

    final storagePath =
        'class_backgrounds/$classId-${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Upload bytes directly — works on web + mobile
    try {
      await supabase.storage
          .from('materials')
          .uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );
    } catch (storageError) {
      print('Error uploading file to storage: $storageError');
      return null;
    }

    final publicUrl = supabase.storage
        .from('materials')
        .getPublicUrl(storagePath);

    try {
      await supabase
          .from('class_rooms')
          .update({'background_image': publicUrl})
          .eq('id', classId);

      print('✅ Successfully updated class_rooms table with background_image');
    } catch (dbError) {
      print('⚠️ Warning: Could not update class_rooms.background_image column: $dbError');
    }

    return http.Response(
      jsonEncode({'background_image': publicUrl}),
      200,
      headers: {'content-type': 'application/json'},
    );
  } on FileSizeLimitException {
    rethrow;
  } catch (e) {
    print('❌ Error uploading class background: $e');
    return null;
  }
}

/// Create a new announcement
static Future<Announcement?> createAnnouncement({
  required String classRoomId,
  required String title,
  required String content,
  Uint8List? imageBytes, // ← replaces imagePath
  String? imageName,     // ← original filename (for extension)
}) async {
  final supabase = Supabase.instance.client;

  try {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      debugPrint('❌ No logged-in user found');
      return null;
    }

    debugPrint('📝 Creating announcement for class: $classRoomId');

    String? imageUrl;
    if (imageBytes != null && imageName != null) {
      imageUrl = await _uploadAnnouncementImage(
        imageBytes,
        imageName,
        classRoomId,
      );
      debugPrint('📸 Image uploaded: $imageUrl');
    }

    final announcementData = <String, dynamic>{
      'class_room_id': classRoomId,
      'teacher_id': currentUser.id,
      'title': title,
      'content': content,
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
    };

    debugPrint('📝 Announcement data to insert: $announcementData');

    final response = await supabase
        .from('announcements')
        .insert(announcementData)
        .select('''
          *,
          teacher:teachers(
            teacher_name,
            profile_picture
          )
        ''')
        .single();

    debugPrint('✅ Announcement created successfully');
    return Announcement.fromJson(response);
  } catch (e) {
    debugPrint('❌ Error creating announcement: $e');
    return null;
  }
}

  // Update the select query in getClassAnnouncements to include image_url
  static Future<List<Announcement>> getClassAnnouncements(
    String classRoomId,
  ) async {
    final supabase = Supabase.instance.client;

    try {
      debugPrint('📝 Fetching announcements for class: $classRoomId');

      final response = await supabase
          .from('announcements')
          .select('''
            *,
            teacher:teachers(
              teacher_name,
              profile_picture
            )
          ''')
          .eq('class_room_id', classRoomId)
          .order('created_at', ascending: false);

      debugPrint('✅ Found ${response.length} announcements');

      return (response as List<dynamic>)
          .map((json) => Announcement.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching announcements: $e');
      return [];
    }
  }

  /// Get a single announcement by ID
  static Future<Announcement?> getAnnouncementById(
    String announcementId,
  ) async {
    final supabase = Supabase.instance.client;

    try {
      final response =
          await supabase
              .from('announcements')
              .select('''
            *,
            teacher:teachers(
              teacher_name,
              profile_picture
            )
          ''')
              .eq('id', announcementId)
              .maybeSingle();

      if (response == null) return null;

      return Announcement.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error fetching announcement: $e');
      return null;
    }
  }

/// Update an existing announcement with optional image
static Future<Announcement?> updateAnnouncement({
  required String announcementId,
  required String title,
  required String content,
  Uint8List? imageBytes, // ← replaces imagePath
  String? imageName,     // ← original filename (for extension)
  bool removeImage = false,
}) async {
  final supabase = Supabase.instance.client;

  try {
    final shouldUpdateImage = imageBytes != null && imageName != null;

    String? imageUrl;
    if (shouldUpdateImage) {
      final current = await getAnnouncementById(announcementId);
      if (current != null) {
        imageUrl = await _uploadAnnouncementImage(
          imageBytes,
          imageName,
          current.classRoomId,
        );
        debugPrint('📸 New image uploaded: $imageUrl');
      }
    }

    final updateData = <String, dynamic>{
      'title': title,
      'content': content,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (removeImage) {
      final current = await getAnnouncementById(announcementId);
      if (current?.imageUrl != null && current!.imageUrl!.isNotEmpty) {
        await _deleteAnnouncementImage(current.imageUrl);
      }
      updateData['image_url'] = null;
      debugPrint('🗑️ Removing image from announcement');
    } else if (shouldUpdateImage && imageUrl != null && imageUrl.isNotEmpty) {
      final current = await getAnnouncementById(announcementId);
      if (current?.imageUrl != null && current!.imageUrl!.isNotEmpty) {
        await _deleteAnnouncementImage(current.imageUrl);
      }
      updateData['image_url'] = imageUrl;
      debugPrint('📝 Setting new image_url: $imageUrl');
    }

    final response = await supabase
        .from('announcements')
        .update(updateData)
        .eq('id', announcementId)
        .select('''
          *,
          teacher:teachers(
            teacher_name,
            profile_picture
          )
        ''')
        .single();

    debugPrint('✅ Announcement updated successfully');
    return Announcement.fromJson(response);
  } catch (e) {
    debugPrint('❌ Error updating announcement: $e');
    return null;
  }
}

  /// Delete an announcement
  /// Delete announcement with image cleanup
  static Future<bool> deleteAnnouncement(String announcementId) async {
    final supabase = Supabase.instance.client;

    try {
      // Get announcement first to check for image
      final announcement = await getAnnouncementById(announcementId);

      if (announcement != null && announcement.imageUrl != null) {
        // Delete image from storage
        await _deleteAnnouncementImage(announcement.imageUrl);
      }

      // Delete announcement from database
      await supabase.from('announcements').delete().eq('id', announcementId);

      debugPrint('✅ Announcement deleted successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting announcement: $e');
      return false;
    }
  }

  /// Get announcements for student (across all enrolled classes)
  static Future<List<Announcement>> getStudentAnnouncements() async {
    final supabase = Supabase.instance.client;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("No logged-in student");

      // Get student's enrolled classes
      final enrollmentsResponse = await supabase
          .from('student_enrollments')
          .select('class_room_id')
          .eq('student_id', user.id);

      if (enrollmentsResponse.isEmpty) return [];

      final classIds =
          (enrollmentsResponse as List<dynamic>)
              .map((e) => e['class_room_id'] as String)
              .toList();

      // Get announcements from all enrolled classes
      final announcementsResponse = await supabase
          .from('announcements')
          .select('''
            *,
            teacher:teachers(
              teacher_name,
              profile_picture
            ),
            class_rooms:class_room_id(
              class_name
            )
          ''')
          .inFilter('class_room_id', classIds)
          .order('created_at', ascending: false);

      debugPrint(
        '✅ Found ${announcementsResponse.length} announcements for student',
      );

      // Convert to Announcement objects and add class name
      return (announcementsResponse as List<dynamic>).map((json) {
        final announcement = Announcement.fromJson(json);
        // Add class name if available
        final classRoom = json['class_rooms'];
        return announcement;
      }).toList();
    } catch (e) {
      debugPrint('❌ Error fetching student announcements: $e');
      return [];
    }
  }

  static Future<int> getAnnouncementsCount(String classRoomId) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('announcements')
          .select()
          .eq('class_room_id', classRoomId);

      // Option 1: Get count from response metadata (Supabase Dart v2+)
      final count = response.length;

      debugPrint('✅ Found $count announcements for class: $classRoomId');
      return count;
    } catch (e) {
      debugPrint('❌ Error fetching announcements count: $e');
      return 0;
    }
  }

/// Upload announcement image to Supabase storage
static Future<String?> _uploadAnnouncementImage(
  Uint8List fileBytes,
  String fileName,
  String classRoomId,
) async {
  try {
    final supabase = Supabase.instance.client;

    // Derive content type from extension
    final ext = fileName.split('.').last.toLowerCase();
    final contentType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png'           => 'image/png',
      'gif'           => 'image/gif',
      'webp'          => 'image/webp',
      _               => 'image/jpeg', // safe fallback
    };

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitized = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = 'announcements/$classRoomId/${timestamp}_$sanitized';

    debugPrint('📤 Uploading image to: $storagePath');
    debugPrint('📏 File size: ${fileBytes.length} bytes');

    await supabase.storage
        .from('materials')
        .uploadBinary(
          storagePath,
          fileBytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );

    final publicUrl = supabase.storage
        .from('materials')
        .getPublicUrl(storagePath);

    debugPrint('✅ Image uploaded successfully: $publicUrl');
    return publicUrl;
  } catch (e) {
    debugPrint('❌ Error uploading announcement image: $e');
    return null;
  }
}

/// Delete announcement image from storage
static Future<void> _deleteAnnouncementImage(String? imageUrl) async {
  try {
    if (imageUrl == null || imageUrl.isEmpty) return;

    final supabase = Supabase.instance.client;

    // Extract file path from URL
    final uri = Uri.parse(imageUrl);
    final pathSegments = uri.pathSegments;

    // Check if URL is from 'materials' bucket
    final bucketIndex = pathSegments.indexOf('materials');
    if (bucketIndex != -1 && bucketIndex + 1 < pathSegments.length) {
      final filePath = pathSegments.sublist(bucketIndex + 1).join('/');

      // Delete from storage
      await supabase.storage.from('materials').remove([filePath]);

      debugPrint('✅ Image deleted from storage: $filePath');
    }
    // Also check for 'document' bucket for backward compatibility
    else {
      final documentIndex = pathSegments.indexOf('document');
      if (documentIndex != -1 && documentIndex + 1 < pathSegments.length) {
        final filePath = pathSegments.sublist(documentIndex + 1).join('/');

        // Delete from storage
        await supabase.storage.from('document').remove([filePath]);

        debugPrint('✅ Image deleted from storage: $filePath');
      }
    }
  } catch (e) {
    debugPrint('❌ Error deleting announcement image: $e');
  }
}

// Bytes version — no dart:io needed
static ({bool isValid, double actualSizeMB}) validateFileSizeFromBytes(
  Uint8List bytes, {
  required double limitMB,
}) {
  final actualSizeMB = bytes.lengthInBytes / (1024 * 1024);
  return (isValid: actualSizeMB <= limitMB, actualSizeMB: actualSizeMB);
}}

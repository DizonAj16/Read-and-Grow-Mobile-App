import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Regex used to extract `material_id` embedded inside `teacher_comments` JSON.
final _kMaterialIdRegex = RegExp(r'"material_id":\s*"([^"]+)"');

// ---------------------------------------------------------------------------
// ParentService
// ---------------------------------------------------------------------------

class ParentService {
  final _supabase = Supabase.instance.client;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Returns a summary list of all children linked to [parentUserId].
  ///
  /// Each entry contains reading level, task/quiz counts, scores, and avatar.
  Future<List<Map<String, dynamic>>> getChildrenSummary(
    String parentUserId,
  ) async {
    try {
      debugPrint('🔍 Fetching children for parentUserId (auth ID): $parentUserId');

      final parentId = await _resolveParentId(parentUserId);
      if (parentId == null) return [];

      final studentIds = await _fetchLinkedStudentIds(parentId);
      if (studentIds.isEmpty) return [];

      debugPrint('👦 Student IDs found: $studentIds');

      final students = await _fetchStudentRecords(studentIds);
      final childrenList = <Map<String, dynamic>>[];

      for (final student in students) {
        final summary = await _buildChildSummary(student);
        childrenList.add(summary);
      }

      debugPrint('✅ Found ${childrenList.length} children.');
      return childrenList;
    } catch (e) {
      debugPrint('❌ Error fetching children summary: $e');
      return [];
    }
  }

  /// Returns graded reading recordings for [studentId], ordered by most recent.
  Future<List<Map<String, dynamic>>> getReadingGrades(String studentId) async {
    final response = await _supabase
        .from('student_recordings')
        .select('''
          id,
          score,
          material_id,
          graded_by,
          teacher_comments,
          graded_at,
          reading_materials (title, description),
          teachers:graded_by (teacher_name)
        ''')
        .eq('student_id', studentId)
        .order('graded_at', ascending: false);

    return response.map((e) {
      return {
        'id': e['id'],
        'score': e['score'],
        'max_score': 5,
        'material_id': e['material_id'],
        'graded_by': e['graded_by'],
        'graded_by_name': e['teachers']?['teacher_name'] ?? 'N/A',
        'teacher_comments': e['teacher_comments'] ?? '',
        'graded_at': e['graded_at'],
        'title': e['reading_materials']?['title'] ?? 'Reading Material',
        'description': e['reading_materials']?['description'] ?? '',
      };
    }).toList();
  }

  /// Returns detailed progress data for a single [studentId].
  Future<Map<String, dynamic>?> getChildProgress(String studentId) async {
    try {
      debugPrint('📘 Fetching progress for studentId: $studentId');

      // Reading level
      final levelId = await _fetchStudentLevelId(studentId);
      final readingLevel = await _fetchLevelTitle(levelId) ?? 'Not Set';

      // Reading materials
      final (totalMaterials, submittedMaterials) =
          await _countReadingMaterials(studentId, levelId);

      // Assignment-based data
      final classIds = await _fetchEnrolledClassIds(studentId);
      final assignmentData = await _parseAssignments(classIds);

      // Task progress
      final taskProgress = await _fetchTaskProgress(studentId);
      final taskSummary = _summarizeTaskProgress(
        taskProgress: taskProgress,
        assignedTaskIds: assignmentData.assignedTaskIds,
        tasksWithQuizzes: assignmentData.tasksWithQuizzes,
      );

      // Quiz submissions
      final quizResult = await _fetchQuizSubmissions(
        studentId: studentId,
        assignedQuizIds: assignmentData.assignedQuizIds,
        includeDetails: true,
      );

      return {
        'readingLevel': readingLevel,
        'totalTasks': assignmentData.assignedTaskIds.length,
        'completedTasks': submittedMaterials,
        'pendingTasks': totalMaterials - submittedMaterials,
        'totalCorrect': taskSummary.totalCorrect,
        'totalWrong': taskSummary.totalWrong,
        'averageScore': taskSummary.averageScore,
        'totalQuizzes': quizResult.totalQuizzes,
        'completedQuizzes': quizResult.completedQuizzes,
        'pendingQuizzes': quizResult.pendingQuizzes,
        'quizAverage': quizResult.quizAverage,
        'quizSubmissions': quizResult.submissions,
      };
    } catch (e) {
      debugPrint('❌ Error fetching child progress: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers — data fetching
  // -------------------------------------------------------------------------

  /// Resolves the `parents.id` for a given auth user ID.
  /// Returns `null` if no parent record is found.
  Future<String?> _resolveParentId(String authUserId) async {
    final record = await _supabase
        .from('parents')
        .select('id')
        .eq('id', authUserId)
        .maybeSingle();

    if (record == null) {
      debugPrint('⚠️ No parent record found for id: $authUserId');
      return null;
    }

    final parentId = record['id'] as String;
    debugPrint('👨 Parent found: $parentId');
    return parentId;
  }

  /// Returns all student IDs linked to [parentId] via `parent_student_relationships`.
  Future<List<String>> _fetchLinkedStudentIds(String parentId) async {
    final rows = await _supabase
        .from('parent_student_relationships')
        .select('student_id')
        .eq('parent_id', parentId);

    if (rows.isEmpty) {
      debugPrint('⚠️ No linked students for parent_id: $parentId');
      return [];
    }

    return rows.map((r) => r['student_id'] as String).toList();
  }

  /// Fetches basic student records for the given [studentIds].
  Future<List<Map<String, dynamic>>> _fetchStudentRecords(
    List<String> studentIds,
  ) async {
    return await _supabase
        .from('students')
        .select('id, student_name, current_reading_level_id, profile_picture')
        .inFilter('id', studentIds);
  }

  /// Returns the `current_reading_level_id` for [studentId], or `null`.
  Future<String?> _fetchStudentLevelId(String studentId) async {
    final record = await _supabase
        .from('students')
        .select('current_reading_level_id')
        .eq('id', studentId)
        .maybeSingle();

    return record?['current_reading_level_id'] as String?;
  }

  /// Returns the `title` for a reading level by [levelId], or `null`.
  Future<String?> _fetchLevelTitle(String? levelId) async {
    if (levelId == null) return null;

    final record = await _supabase
        .from('reading_levels')
        .select('title')
        .eq('id', levelId)
        .maybeSingle();

    return record?['title'] as String?;
  }

  /// Counts total reading materials and how many [studentId] has submitted,
  /// scoped to [levelId]. Returns (total, submitted).
  Future<(int, int)> _countReadingMaterials(
    String studentId,
    String? levelId,
  ) async {
    if (levelId == null) return (0, 0);

    final materialsRes = await _supabase
        .from('reading_materials')
        .select('id')
        .eq('level_id', levelId);

    final totalMaterials = (materialsRes as List).length;
    if (totalMaterials == 0) return (0, 0);

    final materialIds = materialsRes
        .map((m) => m['id']?.toString())
        .where((id) => id != null)
        .toList();

    final submissionsRes = await _supabase
        .from('student_recordings')
        .select('teacher_comments, file_url')
        .eq('student_id', studentId)
        .isFilter('task_id', null);

    final submittedMaterialIds = <String>{};

    for (final s in submissionsRes) {
      final materialId = _extractMaterialId(
        teacherComments: s['teacher_comments'] as String?,
        fileUrl: s['file_url'] as String?,
        materialIds: materialIds.cast<String>(),
      );

      if (materialId != null && materialIds.contains(materialId)) {
        submittedMaterialIds.add(materialId);
      }
    }

    return (totalMaterials, submittedMaterialIds.length);
  }

  /// Returns the list of `class_room_id`s that [studentId] is enrolled in.
  Future<List<String>> _fetchEnrolledClassIds(String studentId) async {
    final enrollments = await _supabase
        .from('student_enrollments')
        .select('class_room_id')
        .eq('student_id', studentId);

    return enrollments.map((e) => e['class_room_id'] as String).toList();
  }

  /// Queries `assignments` for the given [classIds] and returns parsed data.
  Future<_AssignmentData> _parseAssignments(List<String> classIds) async {
    final assignedTaskIds = <String>[];
    final assignedQuizIds = <String>[];
    final tasksWithQuizzes = <String>{};

    if (classIds.isEmpty) {
      return _AssignmentData(
        assignedTaskIds: assignedTaskIds,
        assignedQuizIds: assignedQuizIds,
        tasksWithQuizzes: tasksWithQuizzes,
      );
    }

    final assignments = await _supabase
        .from('assignments')
        .select('task_id, quiz_id, tasks(id, quizzes(id))')
        .inFilter('class_room_id', classIds);

    for (final assignment in assignments) {
      // Direct quiz on assignment
      final directQuizId = assignment['quiz_id'] as String?;
      if (directQuizId != null && !assignedQuizIds.contains(directQuizId)) {
        assignedQuizIds.add(directQuizId);
      }

      // Task (and its nested quizzes)
      final taskId = assignment['task_id'] as String?;
      if (taskId == null) continue;

      final task = assignment['tasks'] as Map<String, dynamic>?;
      bool taskHasQuiz = false;

      if (task != null) {
        final quizzes = task['quizzes'] as List?;
        if (quizzes != null && quizzes.isNotEmpty) {
          taskHasQuiz = true;
          tasksWithQuizzes.add(taskId);
          for (final quiz in quizzes) {
            final quizId = quiz['id'] as String?;
            if (quizId != null && !assignedQuizIds.contains(quizId)) {
              assignedQuizIds.add(quizId);
            }
          }
        }
      }

      if (!taskHasQuiz && !assignedTaskIds.contains(taskId)) {
        assignedTaskIds.add(taskId);
      }
    }

    return _AssignmentData(
      assignedTaskIds: assignedTaskIds,
      assignedQuizIds: assignedQuizIds,
      tasksWithQuizzes: tasksWithQuizzes,
    );
  }

  /// Fetches raw task progress rows for [studentId].
  Future<List<Map<String, dynamic>>> _fetchTaskProgress(
    String studentId, {
    bool includeAnswerCounts = true,
  }) async {
    final select = includeAnswerCounts
        ? 'task_id, score, max_score, correct_answers, wrong_answers, completed'
        : 'task_id, score, max_score, completed';

    return await _supabase
        .from('student_task_progress')
        .select(select)
        .eq('student_id', studentId);
  }

  /// Fetches quiz submissions and computes completion/average data.
  ///
  /// Set [includeDetails] to `true` to also include the per-submission list
  /// with quiz titles (used by [getChildProgress]).
  Future<_QuizResult> _fetchQuizSubmissions({
    required String studentId,
    required List<String> assignedQuizIds,
    bool includeDetails = false,
  }) async {
    final selectFields = includeDetails
        ? 'score, max_score, submitted_at, assignment_id, assignments(id, task_id, quiz_id, tasks(id, quizzes(id, title)), quiz:quizzes(id, title))'
        : 'score, max_score, assignment_id, assignments(id, task_id, quiz_id, tasks(id, quizzes(id)), quiz:quizzes(id))';

    final quizSubmissions = await _supabase
        .from('student_submissions')
        .select(selectFields)
        .eq('student_id', studentId);

    final completedQuizIds = <String>{};
    final submissionList = <Map<String, dynamic>>[];

    for (final submission in quizSubmissions) {
      final assignment = submission['assignments'] as Map<String, dynamic>?;
      String quizTitle = 'Quiz';

      if (assignment != null) {
        final directQuiz = assignment['quiz'] as Map<String, dynamic>?;
        if (directQuiz != null) {
          final quizId = directQuiz['id'] as String?;
          if (quizId != null) completedQuizIds.add(quizId);

          if (includeDetails && directQuiz['title'] != null) {
            quizTitle = directQuiz['title'];
          }
        } else {
          final task = assignment['tasks'] as Map<String, dynamic>?;
          final quizzes = task?['quizzes'] as List<dynamic>?;
          if (quizzes != null && quizzes.isNotEmpty) {
            final firstQuiz = quizzes.first as Map<String, dynamic>?;
            if (firstQuiz != null) {
              final quizId = firstQuiz['id'] as String?;
              if (quizId != null) completedQuizIds.add(quizId);

              if (includeDetails && firstQuiz['title'] != null) {
                quizTitle = firstQuiz['title'];
              }
            }
          }
        }
      }

      if (includeDetails) {
        submissionList.add({
          'score': submission['score'],
          'max_score': submission['max_score'],
          'submitted_at': submission['submitted_at'],
          'quiz_title': quizTitle,
        });
      }
    }

    // Compute average
    double quizAverage = 0;
    if (quizSubmissions.isNotEmpty) {
      double totalScore = 0;
      double totalMax = 0;
      for (final s in quizSubmissions) {
        final score = (s['score'] ?? 0).toDouble();
        final maxScore = (s['max_score'] ?? 0).toDouble();
        if (maxScore > 0) {
          totalScore += score;
          totalMax += maxScore;
        }
      }
      if (totalMax > 0) quizAverage = (totalScore / totalMax) * 100;
    }

    final totalQuizzes = assignedQuizIds.length;
    final completedQuizzes = completedQuizIds.length;

    return _QuizResult(
      totalQuizzes: totalQuizzes,
      completedQuizzes: completedQuizzes,
      pendingQuizzes: totalQuizzes - completedQuizzes,
      quizAverage: quizAverage,
      submissions: submissionList,
    );
  }

  // -------------------------------------------------------------------------
  // Private helpers — computation / data assembly
  // -------------------------------------------------------------------------

  /// Builds the full summary map for a single child [student] record.
  Future<Map<String, dynamic>> _buildChildSummary(
    Map<String, dynamic> student,
  ) async {
    final studentId = student['id'] as String;
    final studentName = student['student_name'] as String;
    final profilePicture = student['profile_picture'] as String?;
    final levelId = student['current_reading_level_id'] as String?;

    final readingLevel = await _fetchLevelTitle(levelId) ?? 'Not Set';
    final (totalMaterials, submittedMaterials) =
        await _countReadingMaterials(studentId, levelId);

    final classIds = await _fetchEnrolledClassIds(studentId);
    final assignmentData = await _parseAssignments(classIds);

    final taskProgress = await _fetchTaskProgress(
      studentId,
      includeAnswerCounts: false,
    );
    final taskSummary = _summarizeTaskProgress(
      taskProgress: taskProgress,
      assignedTaskIds: assignmentData.assignedTaskIds,
      tasksWithQuizzes: assignmentData.tasksWithQuizzes,
    );

    final quizResult = await _fetchQuizSubmissions(
      studentId: studentId,
      assignedQuizIds: assignmentData.assignedQuizIds,
    );

    return {
      'studentId': studentId,
      'studentName': studentName,
      'readingLevel': readingLevel,
      'totalTasks': assignmentData.assignedTaskIds.length + totalMaterials,
      'completedTasks':
          taskSummary.completedTasksWithoutQuizzes.length + submittedMaterials,
      'pendingTasks': totalMaterials - submittedMaterials,
      'averageScore': taskSummary.averageScore,
      'quizCount': quizResult.completedQuizzes,
      'totalQuizzes': quizResult.totalQuizzes,
      'completedQuizzes': quizResult.completedQuizzes,
      'quizAverage': quizResult.quizAverage,
      'profile_picture': profilePicture,
    };
  }

  /// Aggregates raw [taskProgress] rows into counts and scores.
  _TaskSummary _summarizeTaskProgress({
    required List<Map<String, dynamic>> taskProgress,
    required List<String> assignedTaskIds,
    required Set<String> tasksWithQuizzes,
  }) {
    final completedTaskIds = <String>{};
    final pendingTaskIds = <String>{};

    double totalScore = 0;
    double totalMax = 0;
    int totalCorrect = 0;
    int totalWrong = 0;

    for (final t in taskProgress) {
      final taskId = t['task_id'] as String?;
      if (taskId == null) continue;

      if (t['completed'] == true) {
        completedTaskIds.add(taskId);
      } else {
        pendingTaskIds.add(taskId);
      }

      totalScore += (t['score'] ?? 0).toDouble();
      totalMax += (t['max_score'] ?? 0).toDouble();
      totalCorrect += (t['correct_answers'] ?? 0) as int;
      totalWrong += (t['wrong_answers'] ?? 0) as int;
    }

    final completedWithoutQuizzes =
        completedTaskIds.where((id) => !tasksWithQuizzes.contains(id)).toSet();
    final pendingWithoutQuizzes =
        pendingTaskIds.where((id) => !tasksWithQuizzes.contains(id)).toSet();

    int newPendingTasks = 0;
    for (final taskId in assignedTaskIds) {
      if (!completedWithoutQuizzes.contains(taskId) &&
          !pendingWithoutQuizzes.contains(taskId)) {
        newPendingTasks++;
      }
    }

    return _TaskSummary(
      completedTasksWithoutQuizzes: completedWithoutQuizzes,
      pendingTasksWithoutQuizzes: pendingWithoutQuizzes,
      newPendingTasks: newPendingTasks,
      averageScore: totalMax > 0 ? (totalScore / totalMax) * 100 : 0,
      totalCorrect: totalCorrect,
      totalWrong: totalWrong,
    );
  }

  /// Tries to extract a `material_id` from a recording row.
  ///
  /// First checks [teacherComments] for an embedded JSON fragment,
  /// then falls back to matching [fileUrl] against known [materialIds].
  String? _extractMaterialId({
    required String? teacherComments,
    required String? fileUrl,
    required List<String> materialIds,
  }) {
    // Attempt 1: parse material_id from teacher_comments JSON fragment
    if (teacherComments != null && teacherComments.contains('"material_id"')) {
      try {
        final match = _kMaterialIdRegex.firstMatch(teacherComments);
        if (match != null) return match.group(1);
      } catch (e) {
        debugPrint('Error parsing material_id: $e');
      }
    }

    // Attempt 2: match file URL against known material IDs
    if (fileUrl != null && fileUrl.isNotEmpty) {
      for (final mid in materialIds) {
        if (fileUrl.contains(mid)) return mid;
      }
    }

    return null;
  }
}

// ---------------------------------------------------------------------------
// Private value objects (data transfer within the service only)
// ---------------------------------------------------------------------------

class _AssignmentData {
  const _AssignmentData({
    required this.assignedTaskIds,
    required this.assignedQuizIds,
    required this.tasksWithQuizzes,
  });

  final List<String> assignedTaskIds;
  final List<String> assignedQuizIds;
  final Set<String> tasksWithQuizzes;
}

class _TaskSummary {
  const _TaskSummary({
    required this.completedTasksWithoutQuizzes,
    required this.pendingTasksWithoutQuizzes,
    required this.newPendingTasks,
    required this.averageScore,
    required this.totalCorrect,
    required this.totalWrong,
  });

  final Set<String> completedTasksWithoutQuizzes;
  final Set<String> pendingTasksWithoutQuizzes;
  final int newPendingTasks;
  final double averageScore;
  final int totalCorrect;
  final int totalWrong;
}

class _QuizResult {
  const _QuizResult({
    required this.totalQuizzes,
    required this.completedQuizzes,
    required this.pendingQuizzes,
    required this.quizAverage,
    required this.submissions,
  });

  final int totalQuizzes;
  final int completedQuizzes;
  final int pendingQuizzes;
  final double quizAverage;
  final List<Map<String, dynamic>> submissions;
}
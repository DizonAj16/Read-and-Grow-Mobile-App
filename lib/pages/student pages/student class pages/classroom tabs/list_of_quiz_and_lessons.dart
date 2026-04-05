import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_custom_clippers/flutter_custom_clippers.dart';

import 'lesson_reader_page.dart';
import 'student_essay_page.dart';
import 'student_quiz_pages.dart';

class ClassContentScreen extends StatefulWidget {
  final String classRoomId;

  const ClassContentScreen({super.key, required this.classRoomId});

  @override
  State<ClassContentScreen> createState() => _ClassContentScreenState();
}

class _ClassContentScreenState extends State<ClassContentScreen> {
  Future<List<Map<String, dynamic>>>? _lessonsFuture;
  int _refreshKey = 0;
  late List<bool> _expansionStates;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _lessonsFuture = _fetchLessons();
    _expansionStates = [];
  }

  Future<List<Map<String, dynamic>>> _fetchLessons() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      debugPrint('⚠️ No authenticated user found.');
      return [];
    }

    // Fetch assignments with tasks, quizzes, AND essay assignments
    final response = await supabase
        .from('assignments')
        .select('''
        id,
        task_id,
        class_room_id,
        assignment_type,
        tasks (
          id,
          title,
          description,
          "order",
          created_at,
          quizzes (
            id,
            title
          )
        ),
        essay_assignments (
          id,
          title
        )
      ''')
        .eq('class_room_id', widget.classRoomId);

    if (response.isEmpty) return [];

    final assignments = List<Map<String, dynamic>>.from(response);

    // Sort assignments by order and creation date
    assignments.sort((a, b) {
      final taskA = a['tasks'] ?? {};
      final taskB = b['tasks'] ?? {};
      final orderA = taskA['order'] as int? ?? 0;
      final orderB = taskB['order'] as int? ?? 0;
      if (orderA != orderB) return orderA.compareTo(orderB);

      final createdA = DateTime.tryParse(taskA['created_at']?.toString() ?? '');
      final createdB = DateTime.tryParse(taskB['created_at']?.toString() ?? '');
      if (createdA != null && createdB != null)
        return createdA.compareTo(createdB);

      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });

    // Prepare assignment IDs
    final assignmentIds =
        assignments
            .map((a) => a['id']?.toString())
            .whereType<String>()
            .toList();

    // Fetch student submissions (for quizzes)
    Map<String, Map<String, dynamic>> latestSubmissionMap = {};
    Map<String, int> attemptCountMap = {};

    if (assignmentIds.isNotEmpty) {
      final submissionsRes = await supabase
          .from('student_submissions')
          .select(
            'assignment_id, score, max_score, attempt_number, submitted_at',
          )
          .eq('student_id', user.id)
          .inFilter('assignment_id', assignmentIds)
          .order('submitted_at', ascending: false);

      for (final submission in submissionsRes) {
        final sub = Map<String, dynamic>.from(submission as Map);
        final assignmentId = sub['assignment_id']?.toString();
        if (assignmentId == null) continue;

        attemptCountMap[assignmentId] =
            (attemptCountMap[assignmentId] ?? 0) + 1;
        latestSubmissionMap.putIfAbsent(assignmentId, () => sub);
      }
    }

    // Build lessons list
    final lessons = <Map<String, dynamic>>[];
    bool previousQuizCompletedAndPassed = true;
    const double passingThreshold = 0.5;
    const int maxAttempts = 3;
    int lessonCounter = 0;

    for (final assignment in assignments) {
      final task = Map<String, dynamic>.from(assignment['tasks'] ?? {});
      final assignmentId = assignment['id']?.toString();
      final taskId = task['id']?.toString();
      final assignmentType =
          assignment['assignment_type']?.toString() ?? 'quiz';

      if (assignmentId == null || taskId == null) continue;

      final submission = latestSubmissionMap[assignmentId];
      final attemptCount = attemptCountMap[assignmentId] ?? 0;
      final latestAttemptNumber =
          submission?['attempt_number'] as int? ?? attemptCount;

      // Determine essay assignments
      final isEssay = assignmentType == 'essay';
      final essayAssignments = assignment['essay_assignments'];
      final essayData =
          essayAssignments is List && essayAssignments.isNotEmpty
              ? essayAssignments.first
              : (essayAssignments is Map ? essayAssignments : null);

      // For essays, check if submitted and graded
      bool hasEssaySubmission = false;
      bool isEssayGraded = false;
      double essayScore = 0.0;
      double maxEssayScore = 10.0; // Default max score for essays
      String? teacherFeedback;

      if (isEssay && assignmentId.isNotEmpty) {
        final essaySubmissionCheck =
            await supabase
                .from('student_essay_responses')
                .select('id, teacher_score, teacher_feedback, is_graded')
                .eq('assignment_id', assignmentId)
                .eq('student_id', user.id)
                .limit(1)
                .maybeSingle();

        if (essaySubmissionCheck != null) {
          hasEssaySubmission = true;
          isEssayGraded = essaySubmissionCheck['is_graded'] == true;
          essayScore =
              (essaySubmissionCheck['teacher_score'] as num?)?.toDouble() ??
              0.0;
          teacherFeedback =
              essaySubmissionCheck['teacher_feedback']?.toString();
        }
      }

      // Ensure numeric values for score (for quizzes)
      final int latestScore =
          int.tryParse(submission?['score']?.toString() ?? '0') ?? 0;
      final int latestMaxScore =
          int.tryParse(submission?['max_score']?.toString() ?? '0') ?? 0;

      // Determine pass/fail for quizzes
      final bool passedLatest =
          submission != null &&
          latestMaxScore > 0 &&
          (latestScore / latestMaxScore) >= passingThreshold;

      // For essays, consider submitted as completed
      // If graded, use the grade status; if not graded, it's "submitted"
      final bool hasFinalAttempt =
          isEssay
              ? hasEssaySubmission
              : (passedLatest || latestAttemptNumber >= maxAttempts);
      final bool finalPassed =
          isEssay ? (isEssayGraded && essayScore > 0) : passedLatest;

      final bool isFirstLesson = lessons.isEmpty;
      final bool isLocked =
          isFirstLesson ? false : !previousQuizCompletedAndPassed;
      final bool canRetake = !isLocked && !hasFinalAttempt;

      if (hasFinalAttempt) {
        previousQuizCompletedAndPassed = finalPassed;
      } else {
        previousQuizCompletedAndPassed = false;
      }

      lessons.add({
        "assignment_id": assignmentId,
        "task_id": taskId,
        "class_room_id": assignment['class_room_id']?.toString(),
        "title": task['title'],
        "description": task['description'],
        "assignment_type": assignmentType,
        "quizzes":
            isEssay
                ? []
                : List<Map<String, dynamic>>.from(
                  (task['quizzes'] ?? []) as List,
                ),
        "essay_data": isEssay ? essayData : null,
        "submission": submission,
        "isTaken": hasFinalAttempt,
        "isLocked": isLocked,
        "attemptCount": attemptCount,
        "hasFinalAttempt": hasFinalAttempt,
        "finalPassed": finalPassed,
        "canRetake": canRetake,
        "latestScore": latestScore,
        "latestMaxScore": latestMaxScore,
        "isFirstLesson": isFirstLesson,
        "lessonIndex": lessonCounter,
        "hasEssaySubmission": hasEssaySubmission,
        "isEssayGraded": isEssayGraded,
        "essayScore": essayScore,
        "maxEssayScore": maxEssayScore,
        "teacherFeedback": teacherFeedback,
      });

      lessonCounter++;
    }

    // Initialize expansion states after loading lessons
    if (mounted) {
      _expansionStates = List<bool>.filled(lessons.length, false);

      int currentLessonIndex = _findCurrentLessonIndex(lessons);
      if (currentLessonIndex != -1) {
        _expansionStates[currentLessonIndex] = true;
      }
    }

    return lessons;
  }

  // Helper method to find the current lesson index
  int _findCurrentLessonIndex(List<Map<String, dynamic>> lessons) {
    for (int i = 0; i < lessons.length; i++) {
      final lesson = lessons[i];
      final bool isLocked = lesson['isLocked'] == true;
      final bool hasFinalAttempt = lesson['hasFinalAttempt'] == true;

      // Current lesson is the first one that is not locked and not completed
      if (!isLocked && !hasFinalAttempt) {
        return i;
      }
    }

    // If all lessons are completed or locked, return the last one
    return lessons.isNotEmpty ? lessons.length - 1 : -1;
  }

  Future<void> _refreshLessons() async {
    setState(() {
      _refreshKey++;
      _lessonsFuture = _fetchLessons();
    });
    await _lessonsFuture;
  }

  void _showErrorSnackbar(String message) {
      final colorScheme = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
      backgroundColor: colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
          Icon(Icons.error_outline, color: colorScheme.onError),
            const SizedBox(width: 8),
          Text(message, style: TextStyle(color: colorScheme.onError)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceVariant,
      body: Column(
        children: [
          _ClassContentHeader(colorScheme: colorScheme),
          Expanded(
            child: RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: _refreshLessons,
              color: colorScheme.primary,
              backgroundColor: Colors.white,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _lessonsFuture,
                key: ValueKey(_refreshKey),
                builder: (context, snapshot) {
                  return _ClassContentBody(
                    snapshot: snapshot,
                    colorScheme: colorScheme,
                    refreshLessons: _refreshLessons,
                    expansionStates: _expansionStates,
                    updateExpansionStates: (states) {
                      setState(() => _expansionStates = states);
                    },
                    classRoomId: widget.classRoomId,
                    showCompletedQuizDialog: _showCompletedQuizDialog,
                    openLessonReader: _openLessonReader,
                    openQuizPage: _openQuizPage,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCompletedQuizDialog(
    Map<String, dynamic> submission,
    ColorScheme colorScheme,
  ) {
    if (!mounted) return;

    final score = submission['score'] ?? 0;
    final maxScore = submission['max_score'] ?? 0;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Quiz Results',
              style: TextStyle(color: colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You have already completed this quiz.',
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Your Score',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$score / $maxScore',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.pop(context);
                  }
                },
                child: Text('OK', style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
    );
  }

  Future<void> _openLessonReader({
    required String quizId,
    required String assignmentId,
    required String? taskId,
    required String classRoomId,
    required String lessonTitle,
    required int lessonIndex,
    bool viewOnly = false,
    bool fromQuizReview = false,
    String? assignmentType,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (assignmentId.isEmpty || taskId == null || taskId.isEmpty) {
      if (mounted) {
        _showErrorSnackbar('Lesson information is incomplete');
      }
      return;
    }

    if (user == null || user.id.isEmpty) {
      if (mounted) {
        _showErrorSnackbar('Error: User not authenticated');
      }
      return;
    }

    if (!mounted) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
      );

      // Check if previous lesson is passed (except for first lesson)
      if (lessonIndex > 0 && !viewOnly) {
        final previousLessonPassed = await _checkPreviousLessonStatus(
          lessonIndex,
        );

        if (mounted) Navigator.pop(context);

        if (!previousLessonPassed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Complete the previous lesson first to unlock this lesson.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      } else {
        if (mounted) Navigator.pop(context);
      }

      // Check if this is an essay assignment
      if (assignmentType == 'essay') {
        // Navigate to essay page
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => StudentEssayPage(
                  assignmentId: assignmentId,
                  studentId: user.id,
                  taskId: taskId, // Pass taskId here
                  lessonTitle: lessonTitle,
                ),
          ),
        );

        // NEW: Check if essay was submitted (result will be true)
        if (result == true) {
          // Refresh the lessons immediately
          await _refreshLessons();

          if (mounted) {
            // Also show a message about the status change
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Lesson status updated'),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }
        return;
      }

      // Regular quiz flow (unchanged)
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => LessonReaderPage(
                taskId: taskId!,
                assignmentId: assignmentId,
                classRoomId: classRoomId,
                quizId: quizId,
                studentId: user.id,
                lessonTitle: lessonTitle,
                viewOnly: viewOnly,
                fromQuizReview: fromQuizReview,
              ),
        ),
      );

      if (!mounted) return;

      // Handle navigation results
      if (result == 'back_to_class_content') {
        await _refreshLessons();
        return;
      }

      if (viewOnly || result == null) {
        await _refreshLessons();
        return;
      }

      if (result == StudentQuizOutcome.continueNext) {
        await _findAndNavigateToNextLesson(lessonIndex);
      } else if (result == StudentQuizOutcome.exitSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quiz completed successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result == StudentQuizOutcome.exitFailure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please try the quiz again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      await _refreshLessons();
    } catch (error) {
      debugPrint('Error navigating to lesson: $error');
      if (mounted) {
        if (Navigator.of(context).canPop()) Navigator.pop(context);
        _showErrorSnackbar('Error opening lesson: ${error.toString()}');
      }
    }
  }

  // Helper method to check previous lesson status
  Future<bool> _checkPreviousLessonStatus(int currentIndex) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return false;

    // Fetch all lessons to get the previous one
    final allLessons = await _fetchLessons();

    // If currentIndex is 0, there's no previous lesson - allow access
    if (currentIndex == 0) {
      return true;
    }

    // Get the previous lesson
    final previousLesson = allLessons[currentIndex - 1];
    final previousAssignmentId = previousLesson['assignment_id']?.toString();

    if (previousAssignmentId == null) return false;

    // Check if previous lesson is an essay
    final isPreviousEssay = previousLesson['assignment_type'] == 'essay';

    if (isPreviousEssay) {
      // For essays, check if it was submitted
      final hasEssaySubmission = previousLesson['hasEssaySubmission'] == true;
      final isEssayGraded = previousLesson['isEssayGraded'] == true;
      final essayScore = previousLesson['essayScore'] as double? ?? 0.0;

      // If graded, check if score is passing (more than 0)
      // If not graded but submitted, it's considered "in progress"
      return hasEssaySubmission && (isEssayGraded ? essayScore > 0 : true);
    } else {
      // For quizzes, use the existing logic
      final submissionRes =
          await supabase
              .from('student_submissions')
              .select('score, max_score')
              .eq('assignment_id', previousAssignmentId)
              .eq('student_id', user.id)
              .order('submitted_at', ascending: false)
              .limit(1)
              .maybeSingle();

      if (submissionRes == null) {
        // No submission yet for previous lesson
        return false;
      }

      final score = (submissionRes['score'] as num?)?.toDouble() ?? 0;
      final maxScore = (submissionRes['max_score'] as num?)?.toDouble() ?? 0;

      const double passingThreshold = 0.5;
      return maxScore > 0 && (score / maxScore) >= passingThreshold;
    }
  }

  // Update the _findAndNavigateToNextLesson method
  Future<void> _findAndNavigateToNextLesson(int currentIndex) async {
    final latestLessons = await _fetchLessons();
    int nextIndex = currentIndex + 1;

    while (nextIndex < latestLessons.length) {
      final nextLesson = latestLessons[nextIndex];
      final bool isLocked = nextLesson['isLocked'] == true;

      if (!isLocked) {
        final nextQuizzes =
            (nextLesson['quizzes'] as List?)?.cast<Map<String, dynamic>>() ??
            [];

        if (nextQuizzes.isNotEmpty) {
          final nextQuiz = nextQuizzes.first;
          final nextQuizId = nextQuiz['id']?.toString();
          final nextAssignmentId = nextLesson['assignment_id']?.toString();
          final nextTaskId = nextLesson['task_id']?.toString();
          final nextClassRoomId =
              nextLesson['class_room_id']?.toString() ?? widget.classRoomId;

          if (nextQuizId != null &&
              nextAssignmentId != null &&
              nextTaskId != null) {
            // Navigate to next lesson
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _openLessonReader(
                quizId: nextQuizId,
                assignmentId: nextAssignmentId,
                taskId: nextTaskId,
                classRoomId: nextClassRoomId,
                lessonTitle: nextLesson['title'] ?? 'Lesson',
                lessonIndex: nextIndex,
              );
            });
            return;
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'The next lesson is locked. Complete the current lesson first.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        break;
      }

      nextIndex++;
    }

    if (nextIndex >= latestLessons.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Congratulations! You have completed all available lessons in this class.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _openQuizPage({
    required String quizId,
    required String assignmentId,
    required String? taskId,
    required String classRoomId,
    required String lessonTitle,
    required int lessonIndex,
    String? assignmentType,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Check if it's an essay
    if (assignmentType == 'essay') {
      await _openLessonReader(
        quizId: '', // Not needed for essays
        assignmentId: assignmentId,
        taskId: taskId,
        classRoomId: classRoomId,
        lessonTitle: lessonTitle,
        lessonIndex: lessonIndex,
        assignmentType: assignmentType,
      );
      return;
    }

    // Regular quiz flow
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => LessonReaderPage(
              taskId: taskId!,
              assignmentId: assignmentId,
              classRoomId: classRoomId,
              quizId: quizId,
              studentId: user.id,
              lessonTitle: lessonTitle,
              viewOnly: false,
            ),
      ),
    );

    if (!mounted) return;

    if (result == 'back_to_class_content') {
      await _refreshLessons();
    } else if (result == 'review_lesson') {
      final reviewResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => LessonReaderPage(
                taskId: taskId!,
                assignmentId: assignmentId,
                classRoomId: classRoomId,
                quizId: quizId,
                studentId: user.id,
                lessonTitle: lessonTitle,
                viewOnly: true,
                fromQuizReview: true,
              ),
        ),
      );

      if (reviewResult == 'back_to_class_content') {
        await _refreshLessons();
      } else {
        await _refreshLessons();
      }
    } else if (result == StudentQuizOutcome.continueNext) {
      await _findAndNavigateToNextLesson(lessonIndex);
    } else if (result == StudentQuizOutcome.exitSuccess ||
        result == StudentQuizOutcome.exitFailure) {
      await _refreshLessons();
    }
  }
}

class _ClassContentHeader extends StatelessWidget {
  final ColorScheme colorScheme;

  const _ClassContentHeader({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: WaveClipperOne(reverse: false),
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Lessons & Quizzes",
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassContentBody extends StatelessWidget {
  final AsyncSnapshot<List<Map<String, dynamic>>> snapshot;
  final ColorScheme colorScheme;
  final Future<void> Function() refreshLessons;
  final List<bool> expansionStates;
  final Function(List<bool>) updateExpansionStates;
  final String classRoomId;
  final Function(Map<String, dynamic>, ColorScheme) showCompletedQuizDialog;
  final Function({
    required String quizId,
    required String assignmentId,
    required String? taskId,
    required String classRoomId,
    required String lessonTitle,
    required int lessonIndex,
    bool viewOnly,
    bool fromQuizReview,
  })
  openLessonReader;
  final Function({
    required String quizId,
    required String assignmentId,
    required String? taskId,
    required String classRoomId,
    required String lessonTitle,
    required int lessonIndex,
    String? assignmentType,
  })
  openQuizPage;

  const _ClassContentBody({
    required this.snapshot,
    required this.colorScheme,
    required this.refreshLessons,
    required this.expansionStates,
    required this.updateExpansionStates,
    required this.classRoomId,
    required this.showCompletedQuizDialog,
    required this.openLessonReader,
    required this.openQuizPage,
  });

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const _ClassContentLoadingView();
    }

    if (snapshot.hasError) {
      return _ClassContentErrorView(
        onRetry: refreshLessons,
        colorScheme: colorScheme,
      );
    }

    final lessons = snapshot.data ?? [];
    if (lessons.isEmpty) {
      return const _ClassContentEmptyView();
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 16, bottom: 20, left: 12, right: 12),
      itemCount: lessons.length,
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 400 + (index * 100)),
          tween: Tween(begin: 0.8, end: 1),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: _LessonCard(
                lesson: lessons[index],
                index: index,
                colorScheme: colorScheme,
                expansionStates: expansionStates,
                updateExpansionStates: updateExpansionStates,
                showCompletedQuizDialog: showCompletedQuizDialog,
                openLessonReader: openLessonReader,
                openQuizPage: openQuizPage,
                classRoomId: classRoomId,
              ),
            );
          },
        );
      },
    );
  }
}

class _ClassContentLoadingView extends StatelessWidget {
  const _ClassContentLoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/animation/loading_rainbow.json',
            width: 90,
            height: 90,
          ),
          const SizedBox(height: 20),
          Text(
            "Loading Lessons & Quizzes...",
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
              fontFamily: 'ComicNeue',
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassContentErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final ColorScheme colorScheme;

  const _ClassContentErrorView({
    required this.onRetry,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/animation/error.json', width: 150, height: 150),
          const SizedBox(height: 20),
          Text(
            "Failed to load lessons",
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontFamily: 'ComicNeue',
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Retry",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassContentEmptyView extends StatelessWidget {
  const _ClassContentEmptyView();

  @override
  Widget build(BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/animation/empty.json', width: 250, height: 250),
          const SizedBox(height: 20),
          Text(
            "No lessons assigned yet!",
            style: TextStyle(
              fontSize: 22,
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontFamily: 'ComicNeue',
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Your teacher will assign lessons and quizzes here soon',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatefulWidget {
  final Map<String, dynamic> lesson;
  final int index;
  final ColorScheme colorScheme;
  final List<bool> expansionStates;
  final Function(List<bool>) updateExpansionStates;
  final Function(Map<String, dynamic>, ColorScheme) showCompletedQuizDialog;
  final Function({
    required String quizId,
    required String assignmentId,
    required String? taskId,
    required String classRoomId,
    required String lessonTitle,
    required int lessonIndex,
    bool viewOnly,
    bool fromQuizReview,
  })
  openLessonReader;
  final Function({
    required String quizId,
    required String assignmentId,
    required String? taskId,
    required String classRoomId,
    required String lessonTitle,
    required int lessonIndex,
    String? assignmentType,
  })
  openQuizPage;
  final String classRoomId;

  const _LessonCard({
    required this.lesson,
    required this.index,
    required this.colorScheme,
    required this.expansionStates,
    required this.updateExpansionStates,
    required this.showCompletedQuizDialog,
    required this.openLessonReader,
    required this.openQuizPage,
    required this.classRoomId,
  });

  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded =
        widget.expansionStates.length > widget.index
            ? widget.expansionStates[widget.index]
            : false;
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final quizzes = (lesson['quizzes'] as List).cast<Map<String, dynamic>>();

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        key: ValueKey('lesson_${lesson['assignment_id']}_${widget.index}'),
        initiallyExpanded: _isExpanded,
        onExpansionChanged: (expanded) {
          setState(() => _isExpanded = expanded);
          // Close all other tiles when opening a new one
          if (expanded) {
            final newStates = List<bool>.filled(
              widget.expansionStates.length,
              false,
            );
            if (widget.index < newStates.length) {
              newStates[widget.index] = true;
            }
            widget.updateExpansionStates(newStates);
          } else {
            if (widget.index < widget.expansionStates.length) {
              final newStates = List<bool>.from(widget.expansionStates);
              newStates[widget.index] = false;
              widget.updateExpansionStates(newStates);
            }
          }
        },
        leading: Icon(Icons.menu_book, color: widget.colorScheme.primary),
        title: _buildLessonTitle(lesson, widget.index, widget.colorScheme),
        subtitle: Text(
          lesson['description'] ?? 'No description available',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: widget.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        children:
            (lesson['assignment_type'] == 'essay')
                ? _buildEssayTile(lesson, widget.colorScheme)
                : (quizzes.isEmpty
                    ? [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          "No quizzes for this lesson.",
                          style: TextStyle(
                            color: widget.colorScheme.onSurface.withOpacity(
                              0.6,
                            ),
                          ),
                        ),
                      ),
                    ]
                    : quizzes.map<Widget>((quiz) {
                      final quizId = quiz['id']?.toString();
                      final assignmentId = lesson['assignment_id']?.toString();
                      final taskId = lesson['task_id']?.toString();
                      final classRoomId =
                          lesson['class_room_id']?.toString() ??
                          widget.classRoomId;
                      final submission =
                          lesson['submission'] as Map<String, dynamic>?;
                      final bool hasFinalAttempt =
                          lesson['hasFinalAttempt'] == true;
                      final bool finalPassed = lesson['finalPassed'] == true;
                      final bool canRetake = lesson['canRetake'] == true;
                      final bool isLocked = lesson['isLocked'] == true;
                      final int attemptCount =
                          lesson['attemptCount'] as int? ?? 0;
                      final int latestScore =
                          lesson['latestScore'] as int? ?? 0;
                      final int latestMaxScore =
                          lesson['latestMaxScore'] as int? ?? 0;

                      if (quizId == null ||
                          quizId.isEmpty ||
                          assignmentId == null ||
                          assignmentId.isEmpty) {
                        return ListTile(
                          leading: Icon(
                            Icons.error,
                            color: widget.colorScheme.error,
                          ),
                          title: Text('Invalid Quiz'),
                          subtitle: Text(
                            'Quiz data is missing',
                            style: TextStyle(color: widget.colorScheme.error),
                          ),
                          enabled: false,
                        );
                      }

                      final String statusText;
                      Color statusColor;

                      if (finalPassed) {
                        statusText =
                            'Final attempt passed – next quiz unlocked';
                        statusColor = Colors.green;
                      } else if (hasFinalAttempt && !finalPassed) {
                        statusText = 'Final attempt failed – quiz locked';
                        statusColor = Colors.red;
                      } else if (isLocked) {
                        statusText =
                            'Locked until previous quiz final attempt passes';
                        statusColor = Colors.grey;
                      } else {
                        statusText = 'Attempt ${attemptCount + 1} of 3';
                        statusColor = widget.colorScheme.primary;
                      }

                      final bool canViewMaterialOnly =
                          (taskId != null && taskId.isNotEmpty) &&
                          assignmentId.isNotEmpty &&
                          classRoomId.isNotEmpty &&
                          (finalPassed || hasFinalAttempt || !canRetake);

                      return Column(
                        children: [
                          ListTile(
                            leading: Icon(
                              finalPassed
                                  ? Icons.check_circle
                                  : hasFinalAttempt
                                  ? Icons.block
                                  : isLocked
                                  ? Icons.lock
                                  : Icons.quiz,
                              color:
                                  finalPassed
                                      ? Colors.green
                                      : hasFinalAttempt
                                      ? Colors.red
                                      : isLocked
                                      ? Colors.grey
                                      : widget.colorScheme.primary,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    quiz['title'] ?? 'Quiz',
                                    style: TextStyle(
                                      color: widget.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (hasFinalAttempt && latestMaxScore > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$latestScore/$latestMaxScore',
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontStyle:
                                    (hasFinalAttempt || isLocked)
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                              ),
                            ),
                            trailing:
                                finalPassed
                                    ? Icon(Icons.check, color: Colors.green)
                                    : hasFinalAttempt
                                    ? Icon(Icons.lock, color: Colors.redAccent)
                                    : isLocked
                                    ? Icon(
                                      Icons.lock_outline,
                                      color: Colors.grey,
                                    )
                                    : Icon(
                                      Icons.arrow_forward_ios,
                                      size: 16,
                                      color: widget.colorScheme.primary,
                                    ),
                            onTap: () {
                              if (isLocked) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Complete the previous quiz first to unlock this quiz.',
                                    ),
                                    backgroundColor: widget.colorScheme.primary,
                                  ),
                                );
                                return;
                              }

                              if (hasFinalAttempt || !canRetake) {
                                if (submission != null && mounted) {
                                  widget.showCompletedQuizDialog(
                                    submission,
                                    widget.colorScheme,
                                  );
                                }
                                return;
                              }

                              // Navigate to the lesson reader
                              widget.openQuizPage(
                                quizId: quizId,
                                assignmentId: assignmentId,
                                taskId: taskId,
                                classRoomId: classRoomId,
                                lessonTitle: lesson['title'] ?? 'Lesson',
                                lessonIndex: widget.index,
                              );
                            },
                          ),
                          if (canViewMaterialOnly)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 72,
                                right: 16,
                                bottom: 12,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    widget.openLessonReader(
                                      quizId: quizId,
                                      assignmentId: assignmentId,
                                      taskId: taskId,
                                      classRoomId: classRoomId,
                                      lessonTitle: lesson['title'] ?? 'Lesson',
                                      lessonIndex: widget.index,
                                      viewOnly: true,
                                      fromQuizReview: false,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.menu_book_outlined,
                                    color: widget.colorScheme.primary,
                                  ),
                                  label: Text(
                                    'View material',
                                    style: TextStyle(
                                      color: widget.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    }).toList()),
      ),
    );
  }

  List<Widget> _buildEssayTile(
    Map<String, dynamic> lesson,
    ColorScheme colorScheme,
  ) {
    final assignmentId = lesson['assignment_id']?.toString();
    final taskId = lesson['task_id']?.toString();
    final classRoomId =
        lesson['class_room_id']?.toString() ?? widget.classRoomId;
    final essayData = lesson['essay_data'] as Map<String, dynamic>?;
    final hasSubmission = lesson['hasEssaySubmission'] == true;
    final isLocked = lesson['isLocked'] == true;
    final isGraded = lesson['isEssayGraded'] == true;
    final essayScore = (lesson['essayScore'] as num?)?.toDouble() ?? 0.0;
    final maxEssayScore = (lesson['maxEssayScore'] as num?)?.toDouble() ?? 10.0;
    final teacherFeedback = lesson['teacherFeedback']?.toString();

    final String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isGraded) {
      statusText = 'Graded';
      statusColor = Colors.green;
      statusIcon = Icons.grade;
    } else if (hasSubmission) {
      statusText = 'Submitted - Awaiting grade';
      statusColor = Colors.blue;
      statusIcon = Icons.check_circle;
    } else if (isLocked) {
      statusText = 'Locked - Complete previous lesson';
      statusColor = Colors.grey;
      statusIcon = Icons.lock;
    } else {
      statusText = 'Not yet submitted';
      statusColor = Colors.orange;
      statusIcon = Icons.edit_note;
    }

    return [
      // Main tile
      ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(
          essayData?['title'] ?? 'Essay Assignment',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontStyle:
                    (hasSubmission || isLocked)
                        ? FontStyle.italic
                        : FontStyle.normal,
              ),
            ),
            if (isGraded &&
                teacherFeedback != null &&
                teacherFeedback.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'Feedback: ${teacherFeedback.length > 50 ? '${teacherFeedback.substring(0, 50)}...' : teacherFeedback}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGraded && essayScore > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchEssayQuestionsAndGrades(assignmentId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        width: 40,
                        height: 20,
                        child: Center(
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError ||
                        snapshot.data == null ||
                        snapshot.data!.isEmpty) {
                      // Fallback to single score if we can't fetch details
                      return Text(
                        '${essayScore.toStringAsFixed(1)}/$maxEssayScore',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    }

                    final gradedResponses = snapshot.data!;
                    final totalQuestions = gradedResponses.length;

                    if (totalQuestions == 1) {
                      // Single question - show the score
                      final response = gradedResponses.first;
                      final score =
                          (response['teacher_score'] as num?)?.toDouble() ??
                          0.0;
                      return Text(
                        '${score.toStringAsFixed(1)}/$maxEssayScore',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    } else {
                      // Multiple questions - show average
                      final totalScore = gradedResponses.fold<double>(
                        0.0,
                        (sum, response) =>
                            sum +
                            ((response['teacher_score'] as num?)?.toDouble() ??
                                0.0),
                      );
                      final averageScore = totalScore / totalQuestions;
                      return Text(
                        '${averageScore.toStringAsFixed(1)} avg',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    }
                  },
                ),
              ),
            const SizedBox(width: 8),
            if (isGraded)
              const Icon(Icons.check, color: Colors.green)
            else if (isLocked)
              const Icon(Icons.lock_outline, color: Colors.grey)
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.primary,
              ),
          ],
        ),
        onTap: () {
          if (isLocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Complete the previous lesson first.'),
                backgroundColor: colorScheme.primary,
              ),
            );
            return;
          }

          if (hasSubmission && isGraded) {
            // Show detailed grade dialog
            _showEssayGradeDialog(lesson, colorScheme);
            return;
          }

          if (hasSubmission && !isGraded) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'You have already submitted this essay. Your teacher will grade it soon.',
                ),
                backgroundColor: Colors.blue,
              ),
            );
            return;
          }

          widget.openQuizPage(
            quizId: '', // Not needed for essays
            assignmentId: assignmentId!,
            taskId: taskId,
            classRoomId: classRoomId,
            lessonTitle: lesson['title'] ?? 'Essay',
            lessonIndex: widget.index,
            assignmentType: 'essay',
          );
        },
      ),

      // NEW: Expanded view - show question-by-question breakdown only when graded
      if (isGraded && hasSubmission) ...[
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchEssayQuestionsAndGrades(assignmentId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError ||
                snapshot.data == null ||
                snapshot.data!.isEmpty) {
              return Container(); // Return empty if no detailed data
            }

            final gradedResponses = snapshot.data!;
            final totalQuestions = gradedResponses.length;

            // Calculate summary statistics
            final totalScore = gradedResponses.fold<double>(
              0.0,
              (sum, response) =>
                  sum +
                  ((response['teacher_score'] as num?)?.toDouble() ?? 0.0),
            );
            final maxScorePerQuestion = 10.0;
            final maxTotalScore = totalQuestions * maxScorePerQuestion;
            final averageScore = totalScore / totalQuestions;
            final totalPercentage = (totalScore / maxTotalScore) * 100;

            // Always show summary for multiple questions, detailed breakdown for single question
            return Column(
              children: [
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary statistics
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Score',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                    Text(
                                      '${totalScore.toStringAsFixed(1)}/$maxTotalScore',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getGradeColor(totalPercentage),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${totalPercentage.toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Questions',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurface
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                      Text(
                                        '$totalQuestions',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: Colors.grey[300],
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Average Score',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurface
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                      Text(
                                        averageScore.toStringAsFixed(1),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: Colors.grey[300],
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Grade',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurface
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                      Text(
                                        _getGradeLetter(totalPercentage),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _getGradeColor(
                                            totalPercentage,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Question list (always show first 2 questions for preview)
                      Text(
                        'Question Scores',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Show first 2 questions with scores
                      ...gradedResponses.take(2).toList().asMap().entries.map((
                        entry,
                      ) {
                        final index = entry.key;
                        final response = entry.value;
                        final question =
                            response['essay_questions']
                                as Map<String, dynamic>? ??
                            {};
                        final questionText =
                            question['question_text']?.toString() ??
                            'Question ${index + 1}';
                        final score =
                            (response['teacher_score'] as num?)?.toDouble() ??
                            0.0;
                        final questionPercentage =
                            (score / maxScorePerQuestion) * 100;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  questionText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getGradeColor(
                                    questionPercentage,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _getGradeColor(questionPercentage),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '${score.toStringAsFixed(1)}/$maxScorePerQuestion',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _getGradeColor(questionPercentage),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),

                      // Show "more questions" indicator if there are more than 2
                      if (gradedResponses.length > 2) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.more_horiz,
                              color: Colors.grey[500],
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '+${gradedResponses.length - 2} more questions',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],

                      // View full details button
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed:
                              () => _showEssayGradeDialog(lesson, colorScheme),
                          icon: Icon(
                            Icons.open_in_new,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          label: Text(
                            'View All $totalQuestions Questions',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.primary,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ];
  }

  // Helper method to fetch essay questions and grades
  Future<List<Map<String, dynamic>>> _fetchEssayQuestionsAndGrades(
    String assignmentId,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    try {
      final gradedResponses = await Supabase.instance.client
          .from('student_essay_responses')
          .select('''
          id,
          question_id,
          response_text,
          word_count,
          teacher_score,
          teacher_feedback,
          is_graded,
          essay_questions!inner(
            id,
            question_text,
            question_image_url,
            word_limit,
            sort_order
          )
        ''')
          .eq('assignment_id', assignmentId)
          .eq('student_id', user.id)
          .eq('is_graded', true)
          .order('essay_questions(sort_order)', ascending: true);

      return (gradedResponses as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error fetching essay grades: $e');
      return [];
    }
  }

  void _showEssayGradeDialog(
    Map<String, dynamic> lesson,
    ColorScheme colorScheme,
  ) async {
    final assignmentId = lesson['assignment_id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;

    if (assignmentId == null || user == null) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Center(
            child: CircularProgressIndicator(color: colorScheme.primary),
          ),
    );

    try {
      // Fetch all graded essay responses for this assignment
      final gradedResponses = await Supabase.instance.client
          .from('student_essay_responses')
          .select('''
          id,
          question_id,
          response_text,
          word_count,
          teacher_score,
          teacher_feedback,
          is_graded,
          essay_questions!inner(
            id,
            question_text,
            question_image_url,
            word_limit,
            sort_order
          )
        ''')
          .eq('assignment_id', assignmentId)
          .eq('student_id', user.id)
          .eq('is_graded', true)
          .order('essay_questions(sort_order)', ascending: true);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (gradedResponses == null || gradedResponses.isEmpty) {
        // Fallback to simple dialog if no graded responses found
        _showSingleEssayGradeDialog(lesson, colorScheme);
        return;
      }

      final essayTitle = lesson['essay_data']?['title'] ?? 'Essay Assignment';
      final totalQuestions = gradedResponses.length;
      final totalScore = gradedResponses.fold<double>(
        0.0,
        (sum, response) =>
            sum + ((response['teacher_score'] as num?)?.toDouble() ?? 0.0),
      );
      final maxScorePerQuestion = 10.0; // Assuming each question is out of 10
      final maxTotalScore = totalQuestions * maxScorePerQuestion;
      final averageScore = totalScore / totalQuestions;
      final totalPercentage = (totalScore / maxTotalScore) * 100;

      // If only one question, show simplified dialog
      if (totalQuestions == 1) {
        final response = gradedResponses.first;
        final score = (response['teacher_score'] as num?)?.toDouble() ?? 0.0;
        final feedback =
            response['teacher_feedback']?.toString() ?? 'No feedback provided';
        final question =
            response['essay_questions'] as Map<String, dynamic>? ?? {};
        final questionText =
            question['question_text']?.toString() ?? 'Question 1';

        _showSingleQuestionDialog(
          context,
          colorScheme,
          essayTitle,
          questionText,
          score,
          maxScorePerQuestion,
          feedback,
        );
        return;
      }

      // For multiple questions, show comprehensive dialog
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Essay Graded',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    essayTitle,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Overall Score Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _getGradeColor(totalPercentage).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getGradeColor(totalPercentage),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Overall Score',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.onSurface.withOpacity(
                                        0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${totalScore.toStringAsFixed(1)} / $maxTotalScore',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: _getGradeColor(totalPercentage),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _getGradeColor(totalPercentage),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${totalPercentage.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'Questions',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                    Text(
                                      '$totalQuestions',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: Colors.grey[300],
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'Average Score',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                    Text(
                                      averageScore.toStringAsFixed(1),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: Colors.grey[300],
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'Grade',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                    Text(
                                      _getGradeLetter(totalPercentage),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _getGradeColor(totalPercentage),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Individual Question Scores
                    Text(
                      'Question-by-Question Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // List of questions
                    ...gradedResponses.asMap().entries.map((entry) {
                      final index = entry.key;
                      final response = entry.value;
                      final question =
                          response['essay_questions']
                              as Map<String, dynamic>? ??
                          {};
                      final questionText =
                          question['question_text']?.toString() ??
                          'Question ${index + 1}';
                      final wordLimit = question['word_limit'] as int?;
                      final wordCount = response['word_count'] as int? ?? 0;
                      final score =
                          (response['teacher_score'] as num?)?.toDouble() ??
                          0.0;
                      final maxScore = 10.0;
                      final feedback =
                          response['teacher_feedback']?.toString() ??
                          'No feedback provided';
                      final questionPercentage = (score / maxScore) * 100;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Question header
                            Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    questionText,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getGradeColor(
                                      questionPercentage,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _getGradeColor(questionPercentage),
                                    ),
                                  ),
                                  child: Text(
                                    '${score.toStringAsFixed(1)}/$maxScore',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _getGradeColor(questionPercentage),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Word count and limit
                            if (wordLimit != null)
                              Row(
                                children: [
                                  Icon(
                                    Icons.text_fields,
                                    size: 14,
                                    color: Colors.blue[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Words: $wordCount/$wordLimit',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),

                            const SizedBox(height: 8),

                            // Score bar
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: questionPercentage / 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _getGradeColor(questionPercentage),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Teacher Feedback
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.feedback,
                                      size: 14,
                                      color: Colors.orange[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Feedback:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange[700],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.orange[100]!,
                                    ),
                                  ),
                                  child: Text(
                                    feedback,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 16),

                    // Legend for grades
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Grading Scale:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildGradeLegendItem(
                                'A',
                                90,
                                Colors.green[700]!,
                              ),
                              _buildGradeLegendItem('B', 80, Colors.blue[700]!),
                              _buildGradeLegendItem(
                                'C',
                                70,
                                Colors.amber[700]!,
                              ),
                              _buildGradeLegendItem(
                                'D',
                                60,
                                Colors.orange[700]!,
                              ),
                              _buildGradeLegendItem('F', 0, Colors.red[700]!),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(
                    'Close',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
              ],
            ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Fallback to simple dialog
      _showSingleEssayGradeDialog(lesson, colorScheme);
      print('Error fetching graded responses: $e');
    }
  }

  // Dialog for single question
  void _showSingleQuestionDialog(
    BuildContext context,
    ColorScheme colorScheme,
    String essayTitle,
    String questionText,
    double score,
    double maxScore,
    String feedback,
  ) {
    final percentage = (score / maxScore) * 100;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Essay Graded',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  essayTitle,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Question
                  Text(
                    'Question:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      questionText,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Score display
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getGradeColor(percentage).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getGradeColor(percentage),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Your Score',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${score.toStringAsFixed(1)} / $maxScore',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getGradeColor(percentage),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getGradeColor(percentage),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${percentage.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getGradeLetter(percentage),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _getGradeColor(percentage),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Feedback
                  const SizedBox(height: 16),
                  Text(
                    'Teacher Feedback:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      feedback,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.pop(context);
                  }
                },
                child: Text('OK', style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
    );
  }

  // Helper method for single essay (fallback)
  void _showSingleEssayGradeDialog(
    Map<String, dynamic> lesson,
    ColorScheme colorScheme,
  ) {
    final essayScore = (lesson['essayScore'] as num?)?.toDouble() ?? 0.0;
    final maxEssayScore = (lesson['maxEssayScore'] as num?)?.toDouble() ?? 10.0;
    final teacherFeedback =
        lesson['teacherFeedback']?.toString() ?? 'No feedback provided';
    final essayTitle = lesson['essay_data']?['title'] ?? 'Essay Assignment';
    final percentage = (essayScore / maxEssayScore) * 100;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Essay Graded',
              style: TextStyle(color: colorScheme.onSurface),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    essayTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getGradeColor(percentage).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getGradeColor(percentage),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Your Grade',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${essayScore.toStringAsFixed(1)} / $maxEssayScore',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getGradeColor(percentage),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getGradeColor(percentage),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${percentage.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getGradeLetter(percentage),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _getGradeColor(percentage),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Teacher Feedback:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      teacherFeedback,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.pop(context);
                  }
                },
                child: Text('OK', style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
    );
  }

  // Helper methods for grading
  Color _getGradeColor(double percentage) {
    if (percentage >= 90) return Colors.green[700]!;
    if (percentage >= 80) return Colors.blue[700]!;
    if (percentage >= 70) return Colors.amber[700]!;
    if (percentage >= 60) return Colors.orange[700]!;
    return Colors.red[700]!;
  }

  String _getGradeLetter(double percentage) {
    if (percentage >= 90) return 'A';
    if (percentage >= 80) return 'B';
    if (percentage >= 70) return 'C';
    if (percentage >= 60) return 'D';
    return 'F';
  }

  Widget _buildGradeLegendItem(String grade, int minPercentage, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 4),
          Text(
            grade,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            '≥$minPercentage%',
            style: TextStyle(fontSize: 8, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonTitle(
    Map<String, dynamic> lesson,
    int index,
    ColorScheme colorScheme,
  ) {
    final bool isLocked = lesson['isLocked'] == true;
    final bool hasFinalAttempt = lesson['hasFinalAttempt'] == true;
    final bool isCurrentLesson = !isLocked && !hasFinalAttempt;

    return Row(
      children: [
        // Current lesson indicator
        if (isCurrentLesson)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow, size: 12, color: Colors.orange.shade800),
                const SizedBox(width: 4),
                Text(
                  'Current',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Text(
            lesson['title'] ?? 'Untitled',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

extension on _ClassContentScreenState {
  static _ClassContentScreenState? of(BuildContext context) {
    return context.findAncestorStateOfType<_ClassContentScreenState>();
  }
}

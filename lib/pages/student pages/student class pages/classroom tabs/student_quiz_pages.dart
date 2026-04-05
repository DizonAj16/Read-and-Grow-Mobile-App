import 'dart:async';
import 'dart:io';
import 'package:deped_reading_app_laravel/widgets/audio_recorder_widget.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:deped_reading_app_laravel/helper/QuizHelper.dart';
import '../../../../../models/quiz_questions.dart';

enum StudentQuizOutcome { continueNext, exitSuccess, exitFailure }

class StudentQuizPage extends StatefulWidget {
  final String quizId;
  final String assignmentId;
  final String studentId;
  final String? lessonTitle;
  final String? taskId;
  final String? classRoomId;

  const StudentQuizPage({
    super.key,
    required this.quizId,
    required this.assignmentId,
    required this.studentId,
    this.lessonTitle,
    this.taskId,
    this.classRoomId,
  });

  @override
  State<StudentQuizPage> createState() => _StudentQuizPageState();
}

class _StudentQuizPageState extends State<StudentQuizPage> {
  bool loading = true;
  List<QuizQuestion> questions = [];
  String quizTitle = "Quiz";
  QuizHelper? quizHelper;
  bool isSubmitting = false;
  final Map<String, TextEditingController> _textControllers = {};

  // New state variables for single question navigation
  int currentQuestionIndex = 0;
  final PageController _pageController = PageController();
  bool _canProceedToNext = false;

  // Timer animation state
  late Timer _timerAnimationTimer;

  // Add this flag to prevent auto-submission after exit
  bool _preventAutoSubmit = false;

  // Add this variable to store lesson data

  // Helper method to stop all timers
  void _stopAllTimers() {
    // Stop the visual timer animation
    _timerAnimationTimer.cancel();

    // Stop the QuizHelper timer
    quizHelper?.stopTimer();

    // Prevent any future auto-submissions
    _preventAutoSubmit = true;

    debugPrint('⏹️ All timers stopped - Quiz exited without submission');
  }

  @override
  void initState() {
    super.initState();
    _loadQuiz();
    _timerAnimationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (quizHelper?.timeRemaining != null &&
          quizHelper!.timeRemaining <= 10) {
        if (mounted) {
          setState(() {});
        }
      } else {
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    // Set flag to prevent any pending auto-submissions
    _preventAutoSubmit = true;

    // Dispose all text controllers
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    _pageController.dispose();
    _timerAnimationTimer.cancel();

    // Stop the quiz helper timer
    quizHelper?.stopTimer();

    super.dispose();
  }

  Future<void> _loadQuiz() async {
    final supabase = Supabase.instance.client;

    try {
      debugPrint("\n===============================");
      debugPrint("➡️ STARTING QUIZ LOAD");
      debugPrint("===============================\n");

      debugPrint("🟦 Fetching assignment ID: ${widget.assignmentId}");

      // Load lesson data if available
      if (widget.taskId != null && widget.taskId!.isNotEmpty) {
        // Use non-null assertion since we already checked for null and empty
        final taskRes =
            await supabase
                .from('tasks')
                .select('title, description, class_room_id')
                .eq('id', widget.taskId!)
                .maybeSingle();

        if (taskRes != null) {
          setState(() {});
        }
      }

      // Check if quiz has already been submitted (up to 3 attempts allowed)
      // widget.assignmentId is already the assignment ID from assignments table
      final existingSubmissionRes = await supabase
          .from('student_submissions')
          .select('id, score, max_score, attempt_number')
          .eq('assignment_id', widget.assignmentId)
          .eq('student_id', widget.studentId)
          .order('submitted_at', ascending: false);

      const double passingThreshold = 0.5;
      final attemptCount = existingSubmissionRes.length;
      final maxAttempts = 3;

      final passingSubmission = existingSubmissionRes.firstWhere((submission) {
        final score = (submission['score'] as num?)?.toDouble() ?? 0;
        final maxScore = (submission['max_score'] as num?)?.toDouble() ?? 0;
        return maxScore > 0 && (score / maxScore) >= passingThreshold;
      }, orElse: () => {});

      if (passingSubmission.isNotEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder:
                (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(
                        Icons.celebration,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text('Quiz Already Passed'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Great work! You already passed this quiz, so no further attempts are needed.',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Your Score',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${passingSubmission['score']} / ${passingSubmission['max_score']}',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
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
                        if (!mounted) return;
                        Navigator.of(context).pop(); // close dialog
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(
                            context,
                          ).pop(StudentQuizOutcome.exitSuccess);
                        }
                      },
                      child: const Text('Back to Lessons'),
                    ),
                  ],
                ),
          );
        }
        return;
      }

      if (attemptCount >= maxAttempts) {
        final existingSubmission = existingSubmissionRes.first;
        // Quiz already taken maximum times, show message and go back
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder:
                (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(
                        Icons.info,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text('Quiz Already Completed'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'You have already completed this quiz $maxAttempts times. Maximum attempts reached.',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Your Score',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${existingSubmission['score']} / ${existingSubmission['max_score']}',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
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
                        if (!mounted) return;
                        Navigator.pop(context); // Close dialog
                        if (Navigator.of(context).canPop()) {
                          Navigator.pop(
                            context,
                            StudentQuizOutcome.exitFailure,
                          );
                        }
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
          );
        }
        return;
      }

      final quizRes =
          await supabase
              .from('quizzes')
              .select('title')
              .eq('id', widget.quizId)
              .maybeSingle();

      if (quizRes == null) return;

      quizTitle = quizRes['title'] ?? "Quiz";
      final qRes = await supabase
          .from('quiz_questions')
          .select(
            '*, question_options(*), matching_pairs!matching_pairs_question_id_fkey(*)',
          )
          .eq('quiz_id', widget.quizId)
          .order('sort_order', ascending: true);

      questions =
          qRes.map<QuizQuestion>((q) {
            List<MatchingPair> pairs = [];
            if (q['matching_pairs'] != null) {
              pairs =
                  (q['matching_pairs'] as List)
                      .map((p) => MatchingPair.fromMap(p))
                      .toList();
            }

            // Parse option images if they exist
            Map<String, String> optionImages = {};
            if (q['option_images'] != null && q['option_images'] is Map) {
              final imagesMap = q['option_images'] as Map;
              imagesMap.forEach((key, value) {
                if (value is String) {
                  optionImages[key.toString()] = value;
                }
              });
            }

            // For drag-and-drop, ensure options are loaded and sorted by sort_order
            QuizQuestion question = QuizQuestion.fromMap(q).copyWith(
              matchingPairs: pairs,
              optionImages: optionImages.isNotEmpty ? optionImages : null,
            );

            if (question.type == QuestionType.dragAndDrop) {
              // Check if question_options exist
              if (q['question_options'] != null &&
                  q['question_options'] is List) {
                final optionsList = q['question_options'] as List;
                if (optionsList.isNotEmpty) {
                  // Sort by sort_order if available, otherwise keep original order
                  final sortedOptions = <Map<String, dynamic>>[];
                  for (var opt in optionsList) {
                    if (opt is Map<String, dynamic>) {
                      sortedOptions.add(opt);
                    } else if (opt is Map) {
                      sortedOptions.add(Map<String, dynamic>.from(opt));
                    }
                  }
                  sortedOptions.sort((a, b) {
                    final orderA = a['sort_order'] as int? ?? 0;
                    final orderB = b['sort_order'] as int? ?? 0;
                    return orderA.compareTo(orderB);
                  });
                  final optionTexts =
                      sortedOptions
                          .map((opt) => opt['option_text']?.toString() ?? '')
                          .where((text) => text.isNotEmpty)
                          .toList();

                  if (optionTexts.isNotEmpty) {
                    question = question.copyWith(options: optionTexts);
                  } else {
                    // Fallback: create empty options list to prevent null errors
                    question = question.copyWith(options: []);
                  }
                } else {
                  // Empty options list
                  question = question.copyWith(options: []);
                }
              } else {
                // No question_options, create empty list to prevent null errors
                question = question.copyWith(options: []);
              }
              // Store correct order as JSON string in userAnswer for later comparison
              question.userAnswer = ''; // Will be set when student reorders
            }

            return question;
          }).toList();

      // Get task_id from assignment to pass to QuizHelper
      final assignmentRes =
          await supabase
              .from('assignments')
              .select('task_id')
              .eq('id', widget.assignmentId)
              .maybeSingle();

      String? taskId;
      if (assignmentRes != null && assignmentRes['task_id'] != null) {
        final taskIdValue = assignmentRes['task_id'];
        if (taskIdValue is String && taskIdValue.isNotEmpty) {
          taskId = taskIdValue;
        }
      }

      // Determine current attempt number
      final attemptRes = await supabase
          .from('student_submissions')
          .select('attempt_number')
          .eq('assignment_id', widget.assignmentId)
          .eq('student_id', widget.studentId)
          .order('submitted_at', ascending: false)
          .limit(1);

      final currentAttempt =
          attemptRes.isNotEmpty
              ? (attemptRes.first['attempt_number'] as int? ?? 0) + 1
              : 1;

      quizHelper = QuizHelper(
        studentId: widget.studentId,
        taskId: taskId ?? widget.assignmentId, // Fallback to assignmentId
        questions: questions,
        supabase: supabase,
      );
      quizHelper!.currentAttempt = currentAttempt;

      quizHelper!.startTimerFromDatabase(() => _submitQuiz(auto: true), () {
        if (mounted) setState(() {});
      });
    } catch (e, stack) {
      debugPrint("❌ Error loading quiz: $e");
      debugPrint(stack.toString());
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  /// Normalize answer for comparison: trim, lowercase, and normalize whitespace
  String _normalizeAnswer(String answer) {
    if (answer.isEmpty) return '';

    // Trim leading/trailing whitespace
    String normalized = answer.trim();

    // Convert to lowercase
    normalized = normalized.toLowerCase();

    // Normalize whitespace: replace multiple spaces/tabs/newlines with single space
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');

    // Remove any zero-width characters or other invisible unicode
    normalized = normalized.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');

    return normalized;
  }

  Future<void> _submitQuiz({bool auto = false}) async {
    // Prevent submission if we've exited the quiz
    if (_preventAutoSubmit && auto) {
      debugPrint('🚫 Auto-submission prevented - quiz was exited');
      return;
    }
    if (isSubmitting) return; // prevent duplicate submission

    // Show detailed submitting dialog
    bool loadingDialogOpen = false;
    bool scoresComputed = false;
    bool progressUpdated = false;
    bool submissionCreated = false;
    bool audioUploaded = false;

    if (mounted && !auto) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              backgroundColor: Colors.white,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Simple circular progress indicator
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),

                  // Single status text
                  Text(
                    'Submitting Quiz...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),

                  // Optional: simple progress text
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while your answers are being submitted',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
      ).then((_) {
        loadingDialogOpen = false;
      });
      loadingDialogOpen = true;
    }

    isSubmitting = true;
    if (quizHelper == null) return;

    // Show "Times Up" dialog if this is an auto-submission due to timer
    if (auto && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.timer_off, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'Time\'s Up!',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Your time has expired. The quiz will be automatically submitted.',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Don\'t worry! You can review your answers after submission.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text(
                    'View Results',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
      );
    }

    try {
      final supabase = quizHelper!.supabase;
      const double passingThreshold = 0.7;

      // Check existing submissions to determine next attempt number
      final existingSubmissionRes = await supabase
          .from('student_submissions')
          .select('id, attempt_number')
          .eq('assignment_id', widget.assignmentId)
          .eq('student_id', widget.studentId);

      final attemptCount = existingSubmissionRes.length;
      final maxAttempts = 3;

      // Calculate next attempt number (current submissions + 1)
      final nextAttemptNumber = attemptCount + 1;

      // Check if this would exceed maximum attempts
      if (nextAttemptNumber > maxAttempts) {
        if (mounted) {
          // Close the submitting dialog if it's open
          if (!auto) Navigator.of(context).pop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You have already completed this quiz $maxAttempts times. Maximum attempts reached.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
        }
        return;
      }

      // Get student
      final studentRes =
          await supabase
              .from('students')
              .select('id')
              .eq('id', widget.studentId)
              .maybeSingle();

      if (studentRes == null) {
        debugPrint("No student found for id ${widget.studentId}");
        // Close the submitting dialog if it's open
        if (mounted && !auto) Navigator.of(context).pop();
        return;
      }
      final studentId = studentRes['id'];

      // Prepare scores
      int correct = 0;
      int wrong = 0;
      final List<Map<String, dynamic>> activityDetails = [];

      // Prepare a variable for audio upload
      String? audioFileUrl;

      // STEP 1: COMPUTE SCORES
      debugPrint('📊 [SUBMIT] Step 1: Computing scores...');
      for (var q in quizHelper!.questions) {
        bool isCorrect = false;

        switch (q.type) {
          case QuestionType.multipleChoice:
          case QuestionType.multipleChoiceWithImages:
          case QuestionType.fillInTheBlank:
          case QuestionType.fillInTheBlankWithImage:
            // Try to get correct answer from question_options first
            final optionsRes = await supabase
                .from('question_options')
                .select('question_id, option_text, is_correct')
                .eq('question_id', q.id as Object)
                .eq('is_correct', true);

            String? correctAnswerText;

            if (optionsRes.isNotEmpty) {
              correctAnswerText =
                  optionsRes.first['option_text']?.toString().trim();
            } else {
              // Fallback: try fill_in_the_blank_answers table
              try {
                final fillBlankRes =
                    await supabase
                        .from('fill_in_the_blank_answers')
                        .select('correct_answer')
                        .eq('question_id', q.id as Object)
                        .maybeSingle();

                if (fillBlankRes != null) {
                  correctAnswerText =
                      fillBlankRes['correct_answer']?.toString().trim();
                }
              } catch (e) {
                debugPrint('Error fetching fill-in-the-blank answer: $e');
              }
            }

            if (correctAnswerText != null && correctAnswerText.isNotEmpty) {
              // Normalize both answers for comparison
              final normalizedUserAnswer = _normalizeAnswer(q.userAnswer);
              final normalizedCorrectAnswer = _normalizeAnswer(
                correctAnswerText,
              );

              isCorrect = normalizedUserAnswer == normalizedCorrectAnswer;
            } else {
              debugPrint(
                '⚠️ [MULTIPLE_CHOICE_IMAGE] No correct answer found for question ${q.id}',
              );
              isCorrect = false;
            }
            break;

          case QuestionType.matching:
            isCorrect = q.matchingPairs!.every(
              (p) => p.userSelected == p.leftItem,
            );
            break;

          case QuestionType.dragAndDrop:
            // Get correct order from database (sorted by sort_order)
            final optionsRes = await supabase
                .from('question_options')
                .select('option_text, sort_order')
                .eq('question_id', q.id as Object)
                .order('sort_order', ascending: true);

            final correctOrder =
                (optionsRes as List)
                    .map((opt) => opt['option_text']?.toString().trim() ?? '')
                    .where((text) => text.isNotEmpty)
                    .toList();

            // Get student's answer
            List<String>? studentOrder;
            if (q.options != null && q.options!.isNotEmpty) {
              studentOrder =
                  q.options!
                      .map((opt) => opt.toString().trim())
                      .where((text) => text.isNotEmpty)
                      .toList();
            } else if (q.userAnswer.isNotEmpty) {
              studentOrder =
                  q.userAnswer
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
            }

            // Compare student's order with correct order
            if (studentOrder != null &&
                studentOrder.length == correctOrder.length) {
              isCorrect = studentOrder.asMap().entries.every((entry) {
                return entry.value == correctOrder[entry.key];
              });
            } else {
              isCorrect = false;
            }
            break;

          case QuestionType.audio:
            // Upload happens here
            if (q.userAnswer.isNotEmpty && File(q.userAnswer).existsSync()) {
              // Update dialog state for audio upload
              if (mounted && !auto) {
                // This would require a more complex state management approach
                // For now, we'll just proceed
              }

              final localFile = File(q.userAnswer);
              final fileName =
                  '${widget.studentId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
              final storagePath = 'student_voice/$fileName';

              final fileBytes = await localFile.readAsBytes();
              await supabase.storage
                  .from('student_voice')
                  .uploadBinary(
                    storagePath,
                    fileBytes,
                    fileOptions: const FileOptions(contentType: 'audio/m4a'),
                  );

              audioFileUrl = supabase.storage
                  .from('student_voice')
                  .getPublicUrl(storagePath);
              isCorrect = true;
              audioUploaded = true;

              await supabase.from('student_recordings').insert({
                'student_id': widget.studentId,
                'quiz_question_id': q.id,
                'file_url': audioFileUrl,
                'created_at': DateTime.now().toIso8601String(),
              });
            }
            break;

          default:
            isCorrect = false;
        }

        if (isCorrect)
          correct++;
        else
          wrong++;

        activityDetails.add(q.toMap());
      }

      quizHelper!.score = correct;

      debugPrint('📊 [SUBMIT] Step 1 Complete: Score calculation:');
      debugPrint(
        '📊 [SUBMIT] Correct: $correct, Wrong: $wrong, Total: ${quizHelper!.questions.length}',
      );

      // Update dialog to show scores computed
      scoresComputed = true;
      if (mounted && !auto) {
        // Force dialog rebuild
        // Note: In a real implementation, you might need a callback or state management
        // For now, the dialog will update on the next build cycle
      }

      // Update progress - STEP 2
      debugPrint('📊 [SUBMIT] Step 2: Updating progress...');
      final progressUpdate = {
        'student_id': studentId,
        'task_id': quizHelper!.taskId,
        'attempts_left': (3 - nextAttemptNumber),
        'score': correct,
        'max_score': quizHelper!.questions.length,
        'activity_details': activityDetails,
        'correct_answers': correct,
        'wrong_answers': wrong,
        'completed': correct == quizHelper!.questions.length,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final progressResult =
          await supabase
              .from('student_task_progress')
              .upsert(progressUpdate, onConflict: 'student_id,task_id')
              .select();

      debugPrint(
        '📊 [SUBMIT] Step 2 Complete: Progress updated: ${progressResult.length} row(s)',
      );
      progressUpdated = true;

      // Insert submission with attempt number - STEP 3
      debugPrint('📊 [SUBMIT] Step 3: Creating submission...');
      final submissionResult =
          await supabase.from('student_submissions').insert({
            'assignment_id': widget.assignmentId,
            'student_id': widget.studentId,
            'attempt_number': nextAttemptNumber,
            'score': correct,
            'max_score': quizHelper!.questions.length,
            'quiz_answers': activityDetails,
            'audio_file_path': audioFileUrl,
            'submitted_at': DateTime.now().toIso8601String(),
          }).select();

      debugPrint(
        '📊 [SUBMIT] Step 3 Complete: Submission created: ${submissionResult.length} row(s)',
      );
      submissionCreated = true;

      // Update quizHelper with the current attempt number
      quizHelper!.currentAttempt = nextAttemptNumber;

      // IMPORTANT: Only close the loading dialog AFTER scores are computed
      // and all database operations are complete
      if (mounted && !auto && loadingDialogOpen) {
        // Wait a moment to show the completed state
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.of(context).pop(); // Close loading dialog
      }

      if (!mounted) return;

      final bool reachedFinalAttempt = nextAttemptNumber >= maxAttempts;
      final bool passedCurrentAttempt =
          quizHelper!.questions.isNotEmpty &&
          (correct / quizHelper!.questions.length) >= passingThreshold;

      if (reachedFinalAttempt) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              passedCurrentAttempt
                  ? 'Great job! You passed and unlocked the next lesson.'
                  : 'No attempts left. Review the material and try again later.',
            ),
            backgroundColor:
                passedCurrentAttempt
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      final dialogResult = await _showQuizReviewDialog(
        correct,
        quizHelper!.questions.length,
      );

      if (dialogResult == 'review_lesson') {
        // User clicked "Review Lesson"
        debugPrint(
          '🎯 User clicked Review Lesson - navigating to LessonReaderPage',
        );

        // Close the quiz page itself (go back to ClassContentScreen)
        if (!mounted) return;

        // Return a special value to indicate "review_lesson" was clicked
        Navigator.pop(context, 'review_lesson');
        return;
      } else if (dialogResult == true) {
        // This was "Back to Tasks" or similar exit
        if (!mounted) return;
        Navigator.pop(context, StudentQuizOutcome.exitFailure);
        return;
      }

      // For "OK" button (false result), continue as before
      if (!mounted) return;

      // If student passed (50% or higher), show post-quiz options
      if (passedCurrentAttempt) {
        final continueNext = await _showPostQuizOptions();
        if (!mounted) return;
        Navigator.pop(
          context,
          continueNext
              ? StudentQuizOutcome.continueNext
              : StudentQuizOutcome.exitSuccess,
        );
        return;
      }

      // If student failed but clicked "OK" in review dialog
      Navigator.pop(context, StudentQuizOutcome.exitFailure);
    } catch (e, stack) {
      // Close the submitting dialog if it's open
      if (mounted && !auto && loadingDialogOpen) {
        Navigator.of(context).pop();
      }

      debugPrint('❌ Error submitting quiz: $e');
      debugPrint(stack.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to submit quiz. Please try again.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      isSubmitting = false;
    }
  }

  // Helper method to build progress step widget
  Widget _buildProgressStep(String label, bool completed, bool allCompleted) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                completed
                    ? (allCompleted
                        ? Colors.green
                        : Theme.of(context).colorScheme.primary)
                    : Colors.grey.shade300,
          ),
          child:
              completed
                  ? Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color:
                completed
                    ? (allCompleted
                        ? Colors.green
                        : Theme.of(context).colorScheme.primary)
                    : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // Helper method to get sub-status text
  String _getSubStatusText(
    bool scoresComputed,
    bool progressUpdated,
    bool submissionCreated,
    bool audioUploaded,
  ) {
    if (submissionCreated) {
      return 'Quiz submitted successfully! Redirecting to results...';
    } else if (progressUpdated) {
      return 'Creating submission record...';
    } else if (scoresComputed) {
      if (audioUploaded) {
        return 'Audio uploaded. Updating progress...';
      }
      return 'Calculating final score...';
    } else {
      return 'Evaluating answers...';
    }
  }

  Future<dynamic> _showQuizReviewDialog(int score, int totalQuestions) async {
    if (quizHelper == null) return false;

    final supabase = quizHelper!.supabase;

    debugPrint(
      '📊 [REVIEW] Showing quiz review - Score: $score / $totalQuestions',
    );

    // Build list of question reviews with correct answers
    final List<Map<String, dynamic>> questionReviews = [];
    int recalculatedCorrect = 0;

    for (int i = 0; i < quizHelper!.questions.length; i++) {
      final q = quizHelper!.questions[i];
      String correctAnswerText = '';
      String studentAnswerText =
          q.userAnswer.isEmpty ? '(No answer)' : q.userAnswer;
      bool isCorrect = false;

      // Get correct answer based on question type
      switch (q.type) {
        case QuestionType.multipleChoice:
        case QuestionType.multipleChoiceWithImages:
        case QuestionType.fillInTheBlank:
        case QuestionType.fillInTheBlankWithImage:
          // Fetch correct option from database
          final optionsRes = await supabase
              .from('question_options')
              .select('option_text, is_correct')
              .eq('question_id', q.id as Object)
              .eq('is_correct', true);

          if (optionsRes.isNotEmpty) {
            correctAnswerText =
                optionsRes.first['option_text']?.toString().trim() ?? 'N/A';
          } else {
            // Fallback: try fill_in_the_blank_answers table
            try {
              final fillBlankRes =
                  await supabase
                      .from('fill_in_the_blank_answers')
                      .select('correct_answer')
                      .eq('question_id', q.id as Object)
                      .maybeSingle();

              if (fillBlankRes != null) {
                correctAnswerText =
                    fillBlankRes['correct_answer']?.toString().trim() ?? 'N/A';
              } else {
                correctAnswerText = 'N/A';
              }
            } catch (e) {
              debugPrint(
                'Error fetching fill-in-the-blank answer for review: $e',
              );
              correctAnswerText = 'N/A';
            }
          }

          // Normalize both answers for comparison (trim, lowercase, normalize whitespace)
          final normalizedUserAnswer = _normalizeAnswer(q.userAnswer);
          final normalizedCorrectAnswer = _normalizeAnswer(correctAnswerText);
          isCorrect = normalizedUserAnswer == normalizedCorrectAnswer;
          break;

        case QuestionType.matching:
          if (q.matchingPairs != null) {
            final correctPairs = q.matchingPairs!
                .map((p) => '${p.leftItem} → ${p.leftItem}')
                .join(', ');
            final userPairs = q.matchingPairs!
                .map(
                  (p) =>
                      '${p.leftItem} → ${p.userSelected.isEmpty ? "(No match)" : p.userSelected}',
                )
                .join(', ');
            correctAnswerText = correctPairs;
            studentAnswerText = userPairs;
            isCorrect = q.matchingPairs!.every(
              (p) => p.userSelected == p.leftItem,
            );
          }
          break;

        case QuestionType.trueFalse:
          // Fetch correct option from database
          final optionsRes = await supabase
              .from('question_options')
              .select('option_text, is_correct')
              .eq('question_id', q.id as Object);

          final correctOption = optionsRes.firstWhere(
            (o) => o['is_correct'] == true,
            orElse: () => {'option_text': q.correctAnswer ?? 'N/A'},
          );
          correctAnswerText =
              correctOption['option_text'] ?? q.correctAnswer ?? 'N/A';
          isCorrect =
              q.userAnswer.trim().toLowerCase() ==
              correctAnswerText.trim().toLowerCase();
          break;

        case QuestionType.dragAndDrop:
          // Get correct order from database
          final optionsRes = await supabase
              .from('question_options')
              .select('option_text, sort_order')
              .eq('question_id', q.id as Object)
              .order('sort_order', ascending: true);

          final correctOrder =
              (optionsRes as List)
                  .map((opt) => opt['option_text']?.toString().trim() ?? '')
                  .where((text) => text.isNotEmpty)
                  .toList();

          correctAnswerText = correctOrder.join(' → ');

          // Get student's answer - prefer options list, fallback to userAnswer
          List<String>? studentOrder;
          if (q.options != null && q.options!.isNotEmpty) {
            studentOrder =
                q.options!
                    .map((opt) => opt.toString().trim())
                    .where((text) => text.isNotEmpty)
                    .toList();
          } else if (q.userAnswer.isNotEmpty) {
            studentOrder =
                q.userAnswer
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
          }

          studentAnswerText =
              studentOrder != null && studentOrder.isNotEmpty
                  ? studentOrder.join(' → ')
                  : '(No answer)';

          // Compare student's current order with correct order
          if (studentOrder != null &&
              studentOrder.length == correctOrder.length) {
            isCorrect = studentOrder.asMap().entries.every((entry) {
              return entry.value == correctOrder[entry.key];
            });
          } else {
            isCorrect = false;
          }
          break;

        case QuestionType.audio:
          correctAnswerText = 'Audio recording submitted';
          studentAnswerText =
              q.userAnswer.isNotEmpty ? 'Audio recorded' : '(No recording)';
          isCorrect = q.userAnswer.isNotEmpty;
          break;
      }

      if (isCorrect) recalculatedCorrect++;

      questionReviews.add({
        'questionNumber': i + 1,
        'questionText': q.questionText,
        'studentAnswer': studentAnswerText,
        'correctAnswer': correctAnswerText,
        'isCorrect': isCorrect,
      });

      debugPrint(
        '📊 [REVIEW] Q${i + 1}: ${isCorrect ? "✓" : "✗"} - Student: "$studentAnswerText" vs Correct: "$correctAnswerText"',
      );
    }

    // Use recalculated score (more accurate as it recalculates on the fly)
    final finalScore = recalculatedCorrect;
    debugPrint(
      '📊 [REVIEW] Final score: $finalScore / $totalQuestions (Original: $score)',
    );

    // Update the quizHelper score to match recalculated value
    if (finalScore != score) {
      debugPrint(
        '⚠️ [REVIEW] Score mismatch detected! Original: $score, Recalculated: $finalScore',
      );
      debugPrint(
        '✅ [REVIEW] Updating database with correct score: $finalScore',
      );

      // Update quizHelper
      quizHelper!.score = finalScore;

      // Update database records with correct score
      try {
        // Get the most recent submission ID
        final submissionRes =
            await supabase
                .from('student_submissions')
                .select('id')
                .eq('assignment_id', widget.assignmentId)
                .eq('student_id', widget.studentId)
                .order('submitted_at', ascending: false)
                .limit(1)
                .maybeSingle();

        if (submissionRes != null && submissionRes['id'] != null) {
          // Update student_submissions with correct score
          await supabase
              .from('student_submissions')
              .update({'score': finalScore, 'max_score': totalQuestions})
              .eq('id', submissionRes['id']);

          debugPrint(
            '✅ [REVIEW] Updated student_submissions with correct score',
          );
        }

        // Update student_task_progress with correct score
        try {
          await supabase
              .from('student_task_progress')
              .update({
                'score': finalScore,
                'max_score': totalQuestions,
                'correct_answers': finalScore,
                'wrong_answers': totalQuestions - finalScore,
              })
              .eq('student_id', widget.studentId)
              .eq('task_id', quizHelper!.taskId);

          debugPrint(
            '✅ [REVIEW] Updated student_task_progress with correct score',
          );
        } catch (e) {
          debugPrint('⚠️ [REVIEW] Could not update student_task_progress: $e');
        }
      } catch (e) {
        debugPrint('❌ [REVIEW] Error updating database with correct score: $e');
      }
    }

    // Calculate if the attempt passed or failed
    const double passingThreshold = 0.5;
    final double scorePercentage =
        totalQuestions > 0 ? finalScore / totalQuestions : 0.0;
    final bool passedAttempt = scorePercentage >= passingThreshold;

    // Determine if this is first or second attempt that failed
    final bool isFailedFirstOrSecond =
        !passedAttempt && quizHelper!.currentAttempt < 3;

    debugPrint(
      '📊 [REVIEW] Score percentage: ${(scorePercentage * 100).toStringAsFixed(1)}% - Passed: $passedAttempt - FailedFirstOrSecond: $isFailedFirstOrSecond',
    );

    if (!mounted) return false;

    final exitRequested = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => Dialog(
            insetPadding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 700,
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient background
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primaryContainer,
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimary.withOpacity(0.2),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimary.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            passedAttempt ? Icons.celebration : Icons.quiz,
                            size: 32,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                passedAttempt
                                    ? "Quiz Passed! 🎉"
                                    : "Quiz Review",
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Score: $finalScore / $totalQuestions (${((finalScore / totalQuestions) * 100).toStringAsFixed(0)}%)",
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary.withOpacity(0.9),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (passedAttempt) ...[
                                const SizedBox(height: 4),
                                Text(
                                  "Congratulations! You've successfully completed this quiz.",
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary.withOpacity(0.8),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Progress indicator for score
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Performance',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    passedAttempt
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.1)
                                        : Theme.of(
                                          context,
                                        ).colorScheme.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                passedAttempt ? 'PASSED' : 'NEEDS IMPROVEMENT',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      passedAttempt
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.primary
                                          : Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: finalScore / totalQuestions,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            passedAttempt
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Correct: $finalScore',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Incorrect: ${totalQuestions - finalScore}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Attempt warning (if failed first or second)
                  if (isFailedFirstOrSecond)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.errorContainer.withOpacity(0.1),
                            Theme.of(
                              context,
                            ).colorScheme.errorContainer.withOpacity(0.05),
                          ],
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withOpacity(0.2),
                          ),
                          bottom: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withOpacity(0.2),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Attempt ${quizHelper!.currentAttempt} of 3',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'You have ${3 - quizHelper!.currentAttempt} attempt(s) remaining. Review your answers carefully before trying again.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Questions Review Section
                  Expanded(
                    child: Container(
                      color: Theme.of(context).colorScheme.background,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.list_alt,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Question Review',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${questionReviews.length} questions',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              shrinkWrap: true,
                              itemCount: questionReviews.length,
                              separatorBuilder:
                                  (context, index) =>
                                      const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final review = questionReviews[index];
                                return _buildQuestionReviewCard(review);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Update the footer actions section in _showQuizReviewDialog() method:
                  // Update the footer actions section in _showQuizReviewDialog() method:
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.1),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Review Lesson Button (Left side) - Navigates to lesson reader in viewOnly mode
                        // In the footer actions section of _showQuizReviewDialog()
                        // In _showQuizReviewDialog() method, update the "Review Lesson" button:
                        if (widget.taskId != null &&
                            widget.taskId!.isNotEmpty &&
                            widget.classRoomId != null &&
                            widget.classRoomId!.isNotEmpty)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                // Return a special value that indicates user wants to review lesson
                                Navigator.pop(context, 'review_lesson');
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.menu_book_outlined,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Review Lesson',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (widget.taskId != null &&
                            widget.taskId!.isNotEmpty &&
                            widget.classRoomId != null &&
                            widget.classRoomId!.isNotEmpty)
                          const SizedBox(width: 12),
                        // Continue/OK Button (Right side) - Returns false to continue
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                false,
                              ); // false = continue/ok
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              elevation: 3,
                              shadowColor: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.3),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.done,
                                  size: 18,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "OK",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );

    return exitRequested ?? false;
  }

  Widget _buildQuestionReviewCard(Map<String, dynamic> review) {
    final isCorrect = review['isCorrect'];
    final correctColor = Colors.green.shade700;
    final incorrectColor = Colors.red.shade700;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isCorrect
                    ? correctColor.withOpacity(0.2)
                    : incorrectColor.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isCorrect
                                  ? correctColor.withOpacity(0.1)
                                  : incorrectColor.withOpacity(0.1),
                        ),
                        child: Center(
                          child: Text(
                            "${review['questionNumber']}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isCorrect ? correctColor : incorrectColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isCorrect
                                  ? correctColor.withOpacity(0.1)
                                  : incorrectColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isCorrect ? Icons.check_circle : Icons.cancel,
                              size: 14,
                              color: isCorrect ? correctColor : incorrectColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isCorrect ? 'Correct' : 'Incorrect',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    isCorrect ? correctColor : incorrectColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Q${review['questionNumber']}",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                review['questionText'],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Student's Answer - Red background if wrong, green if correct
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      isCorrect
                          ? correctColor.withOpacity(0.05)
                          : incorrectColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        isCorrect
                            ? correctColor.withOpacity(0.2)
                            : incorrectColor.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: isCorrect ? correctColor : incorrectColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Your Answer",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isCorrect ? correctColor : incorrectColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isCorrect
                                ? correctColor.withOpacity(0.1)
                                : incorrectColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              isCorrect
                                  ? correctColor.withOpacity(0.3)
                                  : incorrectColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        review['studentAnswer'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isCorrect ? correctColor : incorrectColor,
                          fontStyle:
                              review['studentAnswer'] == '(No answer)'
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Correct Answer - Always green
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Correct Answer",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        review['correctAnswer'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (!isCorrect) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Take note of the correct answer for your next attempt",
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  Widget _buildTimerWidget() {
    if (quizHelper?.timeRemaining == null || quizHelper!.timeRemaining <= 0) {
      return const SizedBox();
    }
    final colorScheme = Theme.of(context).colorScheme;

    final timeRemaining = quizHelper!.timeRemaining;
    final isLast10Seconds = timeRemaining <= 10;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.symmetric(
        horizontal: isLast10Seconds ? 16 : 12,
        vertical: isLast10Seconds ? 10 : 6,
      ),
      decoration: BoxDecoration(
        color:
            isLast10Seconds
                ? colorScheme.errorContainer.withOpacity(0.3)
                : colorScheme.errorContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isLast10Seconds ? 20 : 16),
        border: Border.all(
          color:
              isLast10Seconds
                  ? colorScheme.error
                  : colorScheme.error.withOpacity(0.5),
          width: isLast10Seconds ? 2 : 1,
        ),
        boxShadow:
            isLast10Seconds
                ? [
                  BoxShadow(
                    color: colorScheme.error.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                ]
                : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: isLast10Seconds ? 20 : 16,
            color: isLast10Seconds ? colorScheme.error : colorScheme.error,
          ),
          const SizedBox(width: 6),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isLast10Seconds ? colorScheme.error : colorScheme.error,
              fontSize: isLast10Seconds ? 18 : 14,
            ),
            child: Text(_formatTime(timeRemaining)),
          ),
          if (isLast10Seconds) ...[
            const SizedBox(width: 6),
            Icon(Icons.warning, size: 16, color: Colors.red),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionWidget(QuizQuestion question) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (question.type) {
      case QuestionType.audio:
        return AudioRecorderWidget(
          studentId: widget.studentId,
          quizQuestionId: question.id!,
          onRecordComplete: (filePath) {
            if (mounted) {
              setState(() {
                question.userAnswer =
                    filePath; // store local path for upload later
                _updateProceedButtonState();
              });
            }
          },
        );

      case QuestionType.multipleChoice:
      case QuestionType.multipleChoiceWithImages:
        // For multiple choice with images, we need to build options with images if available
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // NEW: Display question image if available for multiple choice with images
            if (question.type == QuestionType.multipleChoiceWithImages &&
                question.questionImageUrl != null &&
                question.questionImageUrl!.isNotEmpty)
              Column(
                children: [
                  ImageWithFullScreen(
                    imageUrl: question.questionImageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose the correct answer:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            // Options
            ...question.options!.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;

              // Check if this question has option images
              final optionImage = question.optionImages?[index.toString()];
              final hasImage = optionImage != null && optionImage.isNotEmpty;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                elevation: 1,
                color: colorScheme.surface,

                child: RadioListTile<String>(
                  title:
                      hasImage
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Option image
                              ImageWithFullScreen(
                                imageUrl: optionImage,
                                height: 100,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                              // Option text
                              Text(
                                option.isNotEmpty
                                    ? option
                                    : 'Image option ${index + 1}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          )
                          : Text(option, style: const TextStyle(fontSize: 16)),
                  value: option,
                  groupValue: question.userAnswer,
                  onChanged: (value) {
                    if (mounted) {
                      setState(() {
                        question.userAnswer = value!;
                        _updateProceedButtonState();
                      });
                    }
                  },
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: hasImage ? 12 : 8,
                  ),
                ),
              );
            }).toList(),
          ],
        );

      case QuestionType.trueFalse:
        // For true/false, always show True and False options
        return Column(
          children:
              ['True', 'False'].map((option) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: 1,
                  child: RadioListTile<String>(
                    title: Text(option, style: const TextStyle(fontSize: 16)),
                    value: option,
                    groupValue: question.userAnswer,
                    onChanged: (value) {
                      if (mounted) {
                        setState(() {
                          question.userAnswer = value!;
                          _updateProceedButtonState();
                        });
                      }
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                );
              }).toList(),
        );

      case QuestionType.fillInTheBlank:
        // Get or create controller for this question
        final questionId = question.id ?? question.questionText;
        if (!_textControllers.containsKey(questionId)) {
          _textControllers[questionId] = TextEditingController(
            text: question.userAnswer,
          );
        }
        final controller = _textControllers[questionId]!;

        // Update controller text if question.userAnswer changed externally
        if (controller.text != question.userAnswer) {
          controller.text = question.userAnswer;
        }

        return TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Type your answer",
            hintText: "Enter your answer here",
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.all(16),
          ),
          textCapitalization: TextCapitalization.none,
          onChanged: (value) {
            // Store the answer as-is (normalization happens during comparison)
            question.userAnswer = value;
            _updateProceedButtonState();
          },
        );

      case QuestionType.fillInTheBlankWithImage:
        // Get or create controller for this question
        final questionId = question.id ?? question.questionText;
        if (!_textControllers.containsKey(questionId)) {
          _textControllers[questionId] = TextEditingController(
            text: question.userAnswer,
          );
        }
        final controller = _textControllers[questionId]!;

        // Update controller text if question.userAnswer changed externally
        if (controller.text != question.userAnswer) {
          controller.text = question.userAnswer;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question image if available
            if (question.questionImageUrl != null &&
                question.questionImageUrl!.isNotEmpty)
              ImageWithFullScreen(
                imageUrl: question.questionImageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: "Type your answer based on the image",
                hintText: "Enter your answer here",
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.all(16),
              ),
              textCapitalization: TextCapitalization.none,
              onChanged: (value) {
                // Store the answer as-is (normalization happens during comparison)
                question.userAnswer = value;
                _updateProceedButtonState();
              },
            ),
          ],
        );

      case QuestionType.matching:
        // Ensure matching pairs exist
        if (question.matchingPairs == null || question.matchingPairs!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "No matching pairs available for this question. Please contact your teacher.",
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Create a shuffled copy of the matching pairs for display only once
        // Store the shuffled pairs in the question to maintain consistency
        if (question.userAnswer.isEmpty) {
          // First time viewing this question - shuffle and store the order
          final shuffledPairs = List<MatchingPair>.from(
            question.matchingPairs!,
          );
          shuffledPairs.shuffle();
          // Store the shuffled order as userAnswer (comma separated left items)
          question.userAnswer = shuffledPairs.map((p) => p.leftItem).join(',');
        }

        // Get the stored shuffled order
        final shuffledLeftItems = question.userAnswer.split(',');
        final shuffledPairs = <MatchingPair>[];

        // Reconstruct the shuffled pairs based on stored order
        for (final leftItem in shuffledLeftItems) {
          final originalPair = question.matchingPairs!.firstWhere(
            (p) => p.leftItem == leftItem,
            orElse: () => question.matchingPairs!.first,
          );
          shuffledPairs.add(originalPair);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Match the items by dragging the text to the correct image:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  shuffledPairs.map((pair) {
                    return Draggable<String>(
                      data: pair.leftItem,
                      feedback: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            pair.leftItem,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      childWhenDragging: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pair.leftItem,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        child: Text(
                          pair.leftItem,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
            // Target drop zones - keep in original order
            Column(
              children:
                  question.matchingPairs!.asMap().entries.map((entry) {
                    final pair = entry.value;
                    return DragTarget<String>(
                      onAccept: (received) {
                        if (mounted) {
                          setState(() {
                            // Remove the tag from any other picture that currently has it
                            for (var otherPair in question.matchingPairs!) {
                              if (otherPair != pair &&
                                  otherPair.userSelected == received) {
                                otherPair.userSelected = '';
                              }
                            }

                            // Assign the tag to the current picture
                            pair.userSelected = received;
                            _updateProceedButtonState();
                          });
                        }
                      },
                      onLeave: (data) {
                        // Optional: Add visual feedback when dragging over
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                pair.userSelected.isEmpty
                                    ? Colors.green.shade50
                                    : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  pair.userSelected.isEmpty
                                      ? Colors.green.shade300
                                      : Colors.green,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (pair.rightItemUrl != null &&
                                  pair.rightItemUrl!.isNotEmpty)
                                ImageWithFullScreen(
                                  imageUrl: pair.rightItemUrl!,
                                  height: 80,
                                  width: 80,
                                  fit: BoxFit.contain,
                                ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  pair.userSelected.isEmpty
                                      ? 'Drop text here'
                                      : pair.userSelected,
                                  style: TextStyle(
                                    color:
                                        pair.userSelected.isEmpty
                                            ? Colors.grey[600]
                                            : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (pair.userSelected.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: Colors.red.shade600,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    if (mounted) {
                                      setState(() {
                                        pair.userSelected = '';
                                        _updateProceedButtonState();
                                      });
                                    }
                                  },
                                  tooltip: 'Remove tag',
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  }).toList(),
            ),
            // Add instructions
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Drag each text tag to the matching picture. Each tag can only be used once. Tap the X to remove a tag.',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case QuestionType.dragAndDrop:
        // For drag and drop, ensure options list exists
        if (question.options == null || question.options!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "No options available for this drag-and-drop question. Please contact your teacher.",
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Drag items to reorder them:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                onReorder: (oldIndex, newIndex) {
                  if (mounted) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = question.options!.removeAt(oldIndex);
                      question.options!.insert(newIndex, item);
                    });
                  }
                  // Store the reordered list as user answer (comma-separated)
                  question.userAnswer = question.options!.join(',');
                  // Also ensure options list is preserved
                  debugPrint(
                    '📝 [DRAG_DROP] Reordered: ${question.options!.join(" → ")}',
                  );
                  debugPrint(
                    '📝 [DRAG_DROP] UserAnswer: ${question.userAnswer}',
                  );
                  _updateProceedButtonState();
                },
                children: [
                  for (int i = 0; i < question.options!.length; i++)
                    Card(
                      key: ValueKey('${question.options![i]}-$i'),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      elevation: 2,
                      color: Colors.white,
                      child: ListTile(
                        title: Text(
                          question.options![i],
                          style: const TextStyle(fontSize: 16),
                        ),
                        trailing: const Icon(
                          Icons.drag_handle,
                          color: Colors.grey,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
    }
  }

  void _updateProceedButtonState() {
    final currentQuestion = questions[currentQuestionIndex];
    bool canProceed = false;

    switch (currentQuestion.type) {
      case QuestionType.multipleChoice:
      case QuestionType.multipleChoiceWithImages:
      case QuestionType.trueFalse:
        canProceed = currentQuestion.userAnswer.isNotEmpty;
        break;
      case QuestionType.fillInTheBlank:
      case QuestionType.fillInTheBlankWithImage:
        canProceed = currentQuestion.userAnswer.trim().isNotEmpty;
        break;
      case QuestionType.matching:
        canProceed =
            currentQuestion.matchingPairs != null &&
            currentQuestion.matchingPairs!.isNotEmpty &&
            currentQuestion.matchingPairs!.every(
              (pair) => pair.userSelected.isNotEmpty,
            );
        break;
      case QuestionType.dragAndDrop:
        canProceed =
            currentQuestion.options != null &&
            currentQuestion.options!.isNotEmpty;
        break;
      case QuestionType.audio:
        canProceed = currentQuestion.userAnswer.isNotEmpty;
        break;
    }

    if (mounted) {
      setState(() {
        _canProceedToNext = canProceed;
      });
    }
  }

  void _goToNextQuestion() {
    if (currentQuestionIndex < questions.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        currentQuestionIndex++;
        _updateProceedButtonState();
      });
    }
  }

  void _goToPreviousQuestion() {
    if (currentQuestionIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        currentQuestionIndex--;
        _updateProceedButtonState();
      });
    }
  }

  Widget _buildProgressIndicator() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: (currentQuestionIndex + 1) / questions.length,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),

            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            'Question ${currentQuestionIndex + 1} of ${questions.length}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSubmitConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      Icons.quiz,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('Submit Quiz'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Are you sure you want to submit your quiz?',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have answered ${_getAnsweredQuestionsCount()} out of ${questions.length} questions.',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    if (_getAnsweredQuestionsCount() < questions.length) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'You have unanswered questions. You can still go back and answer them.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isSubmitting
                            ? null
                            : () => Navigator.pop(context, false),
                    child: const Text('Review Answers'),
                  ),
                  ElevatedButton(
                    onPressed:
                        isSubmitting
                            ? null
                            : () {
                              setDialogState(() {});
                              Navigator.pop(context, true);
                            },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child:
                        isSubmitting
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : Text(
                              'Submit Quiz',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                  ),
                ],
              );
            },
          ),
    );

    if (confirmed == true) {
      if (quizHelper != null) {
        for (var q in quizHelper!.questions) {
          if (q.type == QuestionType.dragAndDrop &&
              q.options != null &&
              q.options!.isNotEmpty) {
            q.userAnswer = q.options!.join(',');
            debugPrint('✅ [SUBMIT] Saved drag-drop answer: ${q.userAnswer}');
          }
        }
      }
      _submitQuiz();
    }
  }

  int _getAnsweredQuestionsCount() {
    int answered = 0;
    for (var question in questions) {
      switch (question.type) {
        case QuestionType.multipleChoice:
        case QuestionType.multipleChoiceWithImages:
        case QuestionType.trueFalse:
          if (question.userAnswer.isNotEmpty) answered++;
          break;
        case QuestionType.fillInTheBlank:
        case QuestionType.fillInTheBlankWithImage:
          if (question.userAnswer.trim().isNotEmpty) answered++;
          break;
        case QuestionType.matching:
          if (question.matchingPairs != null &&
              question.matchingPairs!.isNotEmpty &&
              question.matchingPairs!.every(
                (pair) => pair.userSelected.isNotEmpty,
              )) {
            answered++;
          }
          break;
        case QuestionType.dragAndDrop:
          if (question.options != null && question.options!.isNotEmpty)
            answered++;
          break;
        case QuestionType.audio:
          if (question.userAnswer.isNotEmpty) answered++;
          break;
      }
    }
    return answered;
  }

  Widget _buildNavigationButtons() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Previous Button
          Expanded(
            child: OutlinedButton(
              onPressed:
                  currentQuestionIndex > 0 ? _goToPreviousQuestion : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: colorScheme.primary),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_back, size: 18, color: colorScheme.primary),

                  const SizedBox(width: 8),
                  Text(
                    'Previous',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Next/Submit Button
          Expanded(
            child: ElevatedButton(
              onPressed:
                  _canProceedToNext
                      ? (currentQuestionIndex < questions.length - 1
                          ? _goToNextQuestion
                          : _showSubmitConfirmationDialog)
                      : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: colorScheme.primary,
                disabledBackgroundColor: colorScheme.surfaceVariant,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    currentQuestionIndex < questions.length - 1
                        ? 'Next'
                        : 'Submit Quiz',
                    style: TextStyle(color: colorScheme.onPrimary),
                  ),
                  if (currentQuestionIndex < questions.length - 1) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: colorScheme.onPrimary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Loading Quiz...',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(quizTitle)),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No questions available for this quiz.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Use WillPopScope to prevent back button
    return WillPopScope(
      onWillPop: () async {
        debugPrint('⚠️ WillPopScope triggered in StudentQuizPage');

        // Show confirmation dialog when back button is pressed
        final shouldExit = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Exit Quiz?',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Are you sure you want to exit the quiz?',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have answered ${_getAnsweredQuestionsCount()} out of ${questions.length} questions.',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.errorContainer.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your progress will NOT be saved and this attempt will NOT be recorded.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Continue Quiz'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: Text(
                      'Exit Quiz',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ),
                ],
              ),
        );

        if (shouldExit == true && mounted) {
          // Stop the timer before exiting
          _stopAllTimers();
          debugPrint('⏹️ Timer stopped - Quiz exited without submission');
        }

        return shouldExit ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(quizTitle),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          elevation: 2,
          // Remove the back button entirely from app bar
          automaticallyImplyLeading: false,
          // Add custom action buttons
          actions: [
            // // Review Lesson Button - Small button with book icon
            // IconButton(
            //   icon: Icon(
            //     Icons.menu_book_outlined,
            //     color: Theme.of(context).colorScheme.onPrimary,
            //     size: 22,
            //   ),
            //   onPressed: () {
            //     _navigateToLessonReader();
            //   },
            //   tooltip: 'Review Lesson',
            // ),
            // Exit Quiz Button
            IconButton(
              icon: Icon(
                Icons.exit_to_app,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () async {
                final colorScheme = Theme.of(context).colorScheme;

                // Show the same confirmation dialog when exit button is pressed
                final shouldExit = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder:
                      (context) => AlertDialog(
                        title: Row(
                          children: [
                            Icon(Icons.warning, color: colorScheme.error),

                            const SizedBox(width: 8),
                            Text(
                              'Exit Quiz?',
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Are you sure you want to exit the quiz?',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You have answered ${_getAnsweredQuestionsCount()} out of ${questions.length} questions.',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer.withOpacity(
                                  0.2,
                                ),

                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.error),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info,
                                    color: colorScheme.error,
                                    size: 20,
                                  ),

                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Your progress will NOT be saved and this attempt will NOT be recorded.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Continue Quiz'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.error,
                            ),
                            child: Text(
                              'Exit Quiz',
                              style: TextStyle(color: colorScheme.onError),
                            ),
                          ),
                        ],
                      ),
                );

                if (shouldExit == true && mounted) {
                  // Stop the timer before exiting
                  _stopAllTimers();
                  debugPrint(
                    '⏹️ Timer stopped - Quiz exited without submission',
                  );

                  // Return exit failure outcome when manually exiting
                  Navigator.pop(context, StudentQuizOutcome.exitFailure);
                }
              },
              tooltip: 'Exit Quiz',
            ),
          ],
        ),
        body: Column(
          children: [
            // Timer positioned in the body below appbar
            if (quizHelper?.timeRemaining != null &&
                quizHelper!.timeRemaining > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.grey.shade50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [_buildTimerWidget()],
                ),
              ),
            _buildProgressIndicator(),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics:
                    const NeverScrollableScrollPhysics(), // Prevent swipe navigation
                itemCount: questions.length,
                itemBuilder: (context, index) {
                  final question = questions[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      elevation: 4,
                      margin: const EdgeInsets.all(0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Question Header
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Q${index + 1}',
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _getQuestionTypeLabel(question.type),
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Question Text
                            Text(
                              question.questionText,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Question Widget
                            _buildQuestionWidget(question),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  String _getQuestionTypeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuestionType.multipleChoiceWithImages:
        return 'Multiple Choice with Images';
      case QuestionType.trueFalse:
        return 'True or False';
      case QuestionType.fillInTheBlank:
        return 'Fill in the Blank';
      case QuestionType.fillInTheBlankWithImage:
        return 'Fill in the Blank with Image';
      case QuestionType.matching:
        return 'Matching';
      case QuestionType.dragAndDrop:
        return 'Drag and Drop';
      case QuestionType.audio:
        return 'Audio Recording';
    }
  }

  Future<bool> _showPostQuizOptions() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: Text(
              'Quiz Passed',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            content: const Text(
              'Would you like to move on to the next lesson now or come back later?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: Text(
                  'Continue',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
    );

    return result ?? false;
  }
}

class ImageWithFullScreen extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;

  const ImageWithFullScreen({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
  });

  @override
  State<ImageWithFullScreen> createState() => _ImageWithFullScreenState();
}

class _ImageWithFullScreenState extends State<ImageWithFullScreen> {
  bool _isFullScreen = false;

  void _toggleFullScreen() {
    if (_isFullScreen) {
      Navigator.of(context).pop();
      setState(() {
        _isFullScreen = false;
      });
    } else {
      // Show full screen dialog
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                setState(() {
                  _isFullScreen = false;
                });
              },
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                color: Colors.black87,
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Image.network(
                          widget.imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[100],
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      right: 20,
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isFullScreen = false;
                          });
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 40,
                      right: 20,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Pinch to zoom • Tap to close',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).then((_) {
        setState(() {
          _isFullScreen = false;
        });
      });
      setState(() {
        _isFullScreen = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleFullScreen,
      child: Stack(
        children: [
          Container(
            height: widget.height,
            width: widget.width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.imageUrl,
                fit: widget.fit,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[100],
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fullscreen, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Full Screen',
                    style: TextStyle(color: Colors.white, fontSize: 10),
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

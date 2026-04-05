import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/database_helpers.dart';
import 'student class pages/classroom tabs/student_quiz_pages.dart';

class StudentQuizzesPage extends StatefulWidget {
  final String studentId;
  const StudentQuizzesPage({super.key, required this.studentId});

  @override
  State<StudentQuizzesPage> createState() => _StudentQuizzesPageState();
}

class _StudentQuizzesPageState extends State<StudentQuizzesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> quizzes = [];
  Map<String, Map<String, dynamic>> quizSubmissions = {}; // quiz_id -> submission data
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    setState(() => loading = true);
    
    try {
      final result = await ClassroomService.fetchStudentQuizzes(widget.studentId);
      
      // Load submissions for all quizzes
      final submissionMap = <String, Map<String, dynamic>>{};
      
      for (var quiz in result) {
        final assignmentId = quiz['assignment_id'] as String?;
        if (assignmentId != null && assignmentId.isNotEmpty) {
          try {
            // Check if student has already taken this quiz
            final submissions = await DatabaseHelpers.safeGetList(
              supabase: supabase,
              table: 'student_submissions',
              filters: {
                'student_id': widget.studentId,
                'assignment_id': assignmentId,
              },
              orderBy: 'submitted_at',
              ascending: false,
              limit: 1,
            );
            
            if (submissions.isNotEmpty) {
              final submission = submissions.first;
              final quizId = quiz['quiz_id'] as String?;
              if (quizId != null) {
                submissionMap[quizId] = submission;
              }
            }
          } catch (e) {
            debugPrint('Error loading submission for quiz ${quiz['quiz_id']}: $e');
          }
        }
      }
      
      setState(() {
        quizzes = result;
        quizSubmissions = submissionMap;
        loading = false;
      });
    } catch (e) {
      debugPrint('Error loading quizzes: $e');
      setState(() => loading = false);
    }
  }

  Widget _buildQuizCard(Map<String, dynamic> quiz) {
    final quizId = quiz['quiz_id'] as String?;
    final quizTitle = quiz['quiz_title'] as String? ?? 'Untitled Quiz';
    final className = quiz['class_name'] as String? ?? '';
    final assignmentId = quiz['assignment_id'] as String?;
    final submission = quizId != null ? quizSubmissions[quizId] : null;
    final hasTakenQuiz = submission != null;
    
    int score = 0;
    int maxScore = 0;
    if (submission != null) {
      score = DatabaseHelpers.safeIntFromResult(submission, 'score');
      maxScore = DatabaseHelpers.safeIntFromResult(submission, 'max_score');
    }
    final submittedAt = submission != null
        ? DatabaseHelpers.safeStringFromResult(submission, 'submitted_at')
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasTakenQuiz 
              ? (score >= maxScore * 0.8 ? Colors.green : score >= maxScore * 0.6 ? Colors.orange : Colors.red)
              : Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            hasTakenQuiz ? Icons.check_circle : Icons.quiz,
            color: hasTakenQuiz ? Colors.white : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          quizTitle,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: hasTakenQuiz ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Class: $className'),
            if (hasTakenQuiz) ...[
              const SizedBox(height: 4),
              Text(
                'Score: $score / $maxScore',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: score >= maxScore * 0.8 
                      ? Colors.green 
                      : score >= maxScore * 0.6 
                          ? Colors.orange 
                          : Colors.red,
                ),
              ),
              if (submittedAt != null && submittedAt.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Taken: ${_formatDate(submittedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ],
        ),
        trailing: hasTakenQuiz
            ? Icon(Icons.visibility, color: Colors.grey[400])
            : const Icon(Icons.arrow_forward_ios),
        onTap: hasTakenQuiz
            ? () {
                // Show score dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Quiz Score'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quiz: $quizTitle'),
                        const SizedBox(height: 8),
                        Text('Class: $className'),
                        const SizedBox(height: 8),
                        Text(
                          'Score: $score / $maxScore',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (submittedAt != null && submittedAt.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Taken: ${_formatDate(submittedAt)}'),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }
            : () {
                // Navigate to take quiz
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentQuizPage(
                      quizId: quizId ?? '',
                      assignmentId: assignmentId ?? '',
                      studentId: widget.studentId,
                    ),
                  ),
                ).then((_) {
                  // Reload quizzes after returning from quiz
                  _loadQuizzes();
                });
              },
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (quizzes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("My Quizzes")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz_outlined, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 20),
              Text(
                'No quizzes available',
                style: TextStyle(color: Colors.grey[600], fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("My Quizzes")),
      body: RefreshIndicator(
        onRefresh: _loadQuizzes,
        child: ListView.builder(
          itemCount: quizzes.length,
          itemBuilder: (context, index) => _buildQuizCard(quizzes[index]),
        ),
      ),
    );
  }
}

import 'package:deped_reading_app_laravel/api/supabase_api_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class EssayGradingScreen extends StatefulWidget {
  final String classRoomId;
  final String assignmentId;

  const EssayGradingScreen({
    super.key,
    required this.classRoomId,
    required this.assignmentId,
  });

  @override
  State<EssayGradingScreen> createState() => _EssayGradingScreenState();
}

class _EssayGradingScreenState extends State<EssayGradingScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _essaySubmissions = [];
  Map<String, Map<String, dynamic>> _studentsData = {};
  String _filterStatus = 'all'; // 'all', 'graded', 'pending'
  final Map<String, bool> _expandedCards = {}; // Track expanded/collapsed state

  @override
  void initState() {
    super.initState();
    _loadEssaySubmissions();
  }

  Future<void> _loadEssaySubmissions() async {
    setState(() => _isLoading = true);
    try {
      // First get the essay assignment ID from the assignment
      final assignmentRes = await _supabase
          .from('assignments')
          .select('essay_assignments(id)')
          .eq('id', widget.assignmentId)
          .single()
          .catchError((e) {
            print('Error fetching assignment: $e');
            return null;
          });

      if (assignmentRes == null) {
        setState(() {
          _essaySubmissions = [];
          _isLoading = false;
        });
        return;
      }

      // Handle the response structure
      dynamic essayAssignmentsData = assignmentRes['essay_assignments'];
      String? essayAssignmentId;

      if (essayAssignmentsData is List) {
        if (essayAssignmentsData.isNotEmpty) {
          essayAssignmentId = essayAssignmentsData.first?['id']?.toString();
        }
      } else if (essayAssignmentsData is Map<String, dynamic>) {
        essayAssignmentId = essayAssignmentsData['id']?.toString();
      }

      if (essayAssignmentId == null || essayAssignmentId.isEmpty) {
        setState(() {
          _essaySubmissions = [];
          _isLoading = false;
        });
        return;
      }

      // Get essay questions for this assignment
      final questionsRes = await _supabase
          .from('essay_questions')
          .select('*')
          .eq('essay_assignment_id', essayAssignmentId)
          .order('sort_order')
          .catchError((e) {
            print('Error fetching questions: $e');
            return <Map<String, dynamic>>[];
          });

      // Get essay submissions
      final submissionsRes = await _supabase
          .from('student_essay_responses')
          .select('*')
          .eq('assignment_id', widget.assignmentId)
          .catchError((e) {
            print('Error fetching submissions: $e');
            return <Map<String, dynamic>>[];
          });

      // Create a map of questions by their ID for easy lookup
      final questionsMap = <String, Map<String, dynamic>>{};
      if (questionsRes != null && questionsRes.isNotEmpty) {
        for (var question in questionsRes) {
          final id = question['id']?.toString();
          if (id != null) {
            questionsMap[id] = question;
          }
        }
      }

      // Combine submissions with their corresponding questions
      final combinedSubmissions = <Map<String, dynamic>>[];

      if (submissionsRes != null && submissionsRes.isNotEmpty) {
        for (var submission in submissionsRes) {
          final questionId = submission['question_id']?.toString();
          final Map<String, dynamic>? question;

          if (questionId != null && questionsMap.containsKey(questionId)) {
            question = questionsMap[questionId];
          } else {
            question = null;
          }

          combinedSubmissions.add({...submission, 'essay_question': question});
        }
      }

      setState(() {
        _essaySubmissions = combinedSubmissions;
        // Initialize all cards as collapsed by default
        for (var submission in _essaySubmissions) {
          final id = submission['id'].toString();
          _expandedCards[id] = false;
        }
      });

      // Extract unique student IDs from submissions
      if (combinedSubmissions.isNotEmpty) {
        final studentIds =
            combinedSubmissions
                .map((s) => s['student_id']?.toString())
                .where((id) => id != null && id.isNotEmpty)
                .toSet()
                .toList()
                .cast<String>();

        if (studentIds.isNotEmpty) {
          await _loadStudentsData(studentIds);
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading essay submissions: $e');
      setState(() {
        _essaySubmissions = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStudentsData(List<String> studentIds) async {
    try {
      final response = await _supabase
          .from('students')
          .select('*')
          .inFilter('id', studentIds);

      if (response != null) {
        final students = List<Map<String, dynamic>>.from(response);
        for (var student in students) {
          _studentsData[student['id'].toString()] = student;
        }
      }
    } catch (e) {
      print('Error loading students data: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredSubmissions {
    if (_filterStatus == 'all') return _essaySubmissions;

    final isGraded = _filterStatus == 'graded';
    return _essaySubmissions
        .where((s) => (s['is_graded'] as bool? ?? false) == isGraded)
        .toList();
  }

  Future<void> _gradeEssay(Map<String, dynamic> submission) async {
    final TextEditingController _feedbackController = TextEditingController(
      text: submission['teacher_feedback']?.toString() ?? '',
    );

    // Convert existing score to stars (1-5 scale)
    final currentScore =
        (submission['teacher_score'] as num?)?.toDouble() ?? 0.0;
    final currentStars = _convertScoreToStars(currentScore);

    double _starRating = currentStars.toDouble();
    final question =
        submission['essay_question'] as Map<String, dynamic>? ?? {};
    final maxScore =
        question['word_limit'] != null
            ? (question['word_limit'] as int) / 10.0
            : 10.0;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.grade,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Title
                      Text(
                        'Grade Essay',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Rate the student\'s essay',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),

                      const SizedBox(height: 24),

                      // Star Rating
                      Column(
                        children: [
                          Text(
                            'Score: ${_starRating.toStringAsFixed(1)} / 5.0',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _getStarColor(_starRating),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Star Rating Widget
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (index) {
                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    _starRating = (index + 1).toDouble();
                                  });
                                },
                                child: Icon(
                                  index < _starRating.floor()
                                      ? Icons.star
                                      : (index < _starRating
                                          ? Icons.star_half
                                          : Icons.star_border),
                                  size: 40,
                                  color: _getStarColor(_starRating),
                                ),
                              );
                            }),
                          ),

                          const SizedBox(height: 8),

                          // Numeric score display
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _getStarColor(
                                _starRating,
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Numerical Score: ${_convertStarsToScore(_starRating).toStringAsFixed(1)} / ${maxScore.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _getStarColor(_starRating),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Feedback Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.feedback,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Feedback',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: TextField(
                              controller: _feedbackController,
                              maxLines: 5,
                              minLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Provide constructive feedback...',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_feedbackController.text
                                    .trim()
                                    .isNotEmpty) {
                                  Navigator.pop(context, true);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please provide feedback'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                backgroundColor: _getStarColor(_starRating),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                                shadowColor: _getStarColor(
                                  _starRating,
                                ).withOpacity(0.3),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Submit',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true) {
      try {
        // Convert star rating back to numerical score
        final numericalScore = _convertStarsToScore(_starRating);

        final success = await ApiService.gradeEssay(
          submissionId: submission['id'].toString(),
          score: numericalScore,
          feedback: _feedbackController.text.trim(),
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Essay graded successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          await _loadEssaySubmissions();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Error grading essay: $e'),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    }
  }

  // Convert numerical score (0-10) to stars (1-5)
  double _convertScoreToStars(double score) {
    if (score <= 0) return 1.0;
    if (score >= 10) return 5.0;
    return (score / 2).clamp(1.0, 5.0);
  }

  // Convert stars (1-5) to numerical score (1-10)
  double _convertStarsToScore(double stars) {
    return (stars * 2).clamp(2.0, 10.0); // Minimum 2, maximum 10
  }

  // Get color based on star rating
  Color _getStarColor(double stars) {
    if (stars >= 4.0) return Colors.green[700]!;
    if (stars >= 3.0) return Colors.blue[700]!;
    if (stars >= 2.0) return Colors.amber[700]!;
    return Colors.red[700]!;
  }

  // Get star rating display
  Widget _buildStarRating(double stars) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < stars.floor()
              ? Icons.star
              : (index < stars ? Icons.star_half : Icons.star_border),
          size: 16,
          color: _getStarColor(stars),
        );
      }),
    );
  }

  // Toggle card expansion
  void _toggleCardExpansion(String cardId) {
    setState(() {
      _expandedCards[cardId] = !(_expandedCards[cardId] ?? false);
    });
  }

  // UPDATED: View attachment within the app
  Future<void> _viewAttachment(String url, String fileName) async {
    final fileExtension = _getFileExtension(fileName);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              appBar: AppBar(
                title: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                elevation: 4,
                shadowColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.3),
              ),
              body: _getMediaViewer(url, fileExtension),
            ),
      ),
    );
  }

  // Get file extension from file name
  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  // Get appropriate viewer based on file type
  Widget _getMediaViewer(String url, String fileExtension) {
    // Check if it's an image
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(fileExtension)) {
      return PhotoView(
        imageProvider: NetworkImage(url),
        minScale: PhotoViewComputedScale.contained * 0.8,
        maxScale: PhotoViewComputedScale.covered * 2,
        backgroundDecoration: BoxDecoration(color: Colors.grey[100]),
      );
    }

    // Check if it's a PDF
    if (fileExtension == 'pdf') {
      return SfPdfViewer.network(url);
    }

    // Check if it's a video
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(fileExtension)) {
      return _VideoViewerWidget(videoUrl: url);
    }

    // For other file types (doc, docx, etc.)
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getFileIconFromExtension(fileExtension),
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Preview not available for .$fileExtension files',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _downloadFile(url, fileExtension),
            icon: const Icon(Icons.download),
            label: const Text('Download File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              shadowColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  // Download file function
  Future<void> _downloadFile(String url, String fileExtension) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.download, color: Colors.white),
            const SizedBox(width: 8),
            Text('Downloading .$fileExtension file...'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Get file icon based on extension
  IconData _getFileIconFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.videocam;
      default:
        return Icons.insert_drive_file;
    }
  }

  Map<String, dynamic> _getStudentData(String? studentId) {
    if (studentId == null || !_studentsData.containsKey(studentId)) {
      return {};
    }
    return _studentsData[studentId]!;
  }

  Widget _buildEssayCard(Map<String, dynamic> submission) {
    final cardId = submission['id'].toString();
    final isExpanded = _expandedCards[cardId] ?? false;
    final studentId = submission['student_id']?.toString();
    final student = _getStudentData(studentId);

    // CHANGED: Use 'essay_question' instead of 'essay_questions'
    final question =
        submission['essay_question'] as Map<String, dynamic>? ?? {};

    final responseText = submission['response_text']?.toString() ?? '';
    final wordCount = submission['word_count'] as int? ?? 0;
    final wordLimit = question['word_limit'] as int?;
    final isGraded = submission['is_graded'] as bool? ?? false;
    final teacherScore = (submission['teacher_score'] as num?)?.toDouble();
    final teacherFeedback = submission['teacher_feedback']?.toString();
    final questionImageUrl = question['question_image_url']?.toString();
    final attachedFiles = submission['attached_files'] as List? ?? [];

    // Convert score to stars if graded
    final starRating =
        isGraded && teacherScore != null
            ? _convertScoreToStars(teacherScore)
            : 0.0;

    // Student data from students table
    final studentName =
        student['student_name']?.toString() ?? 'Unknown Student';
    final studentEmail = student['username']?.toString() ?? '';
    final profilePicture = student['profile_picture']?.toString();
    final studentLrn = student['student_lrn']?.toString() ?? '';
    final studentGrade = student['student_grade']?.toString() ?? '';
    final studentSection = student['student_section']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: isExpanded ? 8 : 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Column(
          children: [
            // Collapsed Header (same as before)
            InkWell(
              onTap: () => _toggleCardExpansion(cardId),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.05),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // Profile picture
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                        image:
                            profilePicture != null && profilePicture.isNotEmpty
                                ? DecorationImage(
                                  image: NetworkImage(profilePicture),
                                  fit: BoxFit.cover,
                                  onError: (exception, stackTrace) {
                                    // Error handled by fallback
                                  },
                                )
                                : null,
                      ),
                      child:
                          profilePicture == null || profilePicture.isEmpty
                              ? Center(
                                child: Text(
                                  studentName.isNotEmpty
                                      ? studentName
                                          .substring(0, 1)
                                          .toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              )
                              : null,
                    ),

                    const SizedBox(width: 16),

                    // Student info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studentName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.assignment,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${wordCount} words${wordLimit != null ? '/$wordLimit' : ''}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Status and expand icon
                    Column(
                      children: [
                        Chip(
                          label: Text(
                            isGraded ? 'Graded' : 'Pending',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor:
                              isGraded ? Colors.green[100] : Colors.amber[100],
                          avatar: Icon(
                            isGraded ? Icons.check_circle : Icons.pending,
                            size: 14,
                            color:
                                isGraded
                                    ? Colors.green[700]
                                    : Colors.amber[700],
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),

                        const SizedBox(height: 8),

                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Expanded Content
            if (isExpanded) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.question_answer,
                                size: 20,
                                color: Colors.blue[700],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Question:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          if (questionImageUrl != null &&
                              questionImageUrl.isNotEmpty)
                            Column(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => Scaffold(
                                              appBar: AppBar(
                                                title: const Text(
                                                  'Question Image',
                                                ),
                                                backgroundColor:
                                                    Colors.blue[700],
                                              ),
                                              body: PhotoView(
                                                imageProvider: NetworkImage(
                                                  questionImageUrl,
                                                ),
                                                minScale:
                                                    PhotoViewComputedScale
                                                        .contained *
                                                    0.8,
                                                maxScale:
                                                    PhotoViewComputedScale
                                                        .covered *
                                                    2,
                                              ),
                                            ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      questionImageUrl,
                                      height: 150,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return Container(
                                          height: 150,
                                          color: Colors.grey[300],
                                          child: const Center(
                                            child: Icon(
                                              Icons.broken_image,
                                              size: 50,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),

                          // CHANGED: Access question text properly
                          if (question.isNotEmpty &&
                              question['question_text'] != null)
                            Text(
                              question['question_text']!.toString(),
                              style: const TextStyle(fontSize: 14),
                            )
                          else
                            Text(
                              'Question not available',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Student Response (rest of the code remains the same)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.edit_note,
                                size: 20,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Student Response:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          if (responseText.isNotEmpty)
                            Text(
                              responseText,
                              style: const TextStyle(fontSize: 14),
                            )
                          else
                            Text(
                              'No text response provided',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Attached files
                    if (attachedFiles.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.purple[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purple[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.attachment,
                                  size: 20,
                                  color: Colors.purple[700],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Attachments (${attachedFiles.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple[700],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  attachedFiles.map((fileUrl) {
                                    final fileName =
                                        fileUrl.toString().split('/').last;
                                    return InkWell(
                                      onTap:
                                          () => _viewAttachment(
                                            fileUrl.toString(),
                                            fileName,
                                          ),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.purple[300]!,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _getFileIcon(fileName),
                                              color: Colors.purple[700],
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: 150,
                                              ),
                                              child: Text(
                                                fileName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Grade display or grading button
                    if (isGraded)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green[200]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.grade,
                                  color: Colors.green[700],
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Grade',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                    fontSize: 18,
                                  ),
                                ),
                                const Spacer(),
                                _buildStarRating(starRating),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${teacherScore?.toStringAsFixed(1)}/10',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            OutlinedButton.icon(
                              onPressed: () => _gradeEssay(submission),
                              icon: Icon(
                                Icons.edit,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              label: Text(
                                'Edit Grade',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 45),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),

                            if (teacherFeedback != null &&
                                teacherFeedback.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Feedback:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Text(
                                  teacherFeedback,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () => _gradeEssay(submission),
                        icon: const Icon(Icons.grading, color: Colors.white),
                        label: const Text(
                          'Grade This Essay',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                          shadowColor: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return _getFileIconFromExtension(extension);
  }

  @override
  Widget build(BuildContext context) {
    final filteredSubmissions = _filteredSubmissions;
    final pendingCount =
        _essaySubmissions
            .where((s) => !(s['is_graded'] as bool? ?? false))
            .length;
    final gradedCount = _essaySubmissions.length - pendingCount;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: Text(
          'Essay Grading',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 4,
        shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        actions: [
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadEssaySubmissions,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _FilterChip(
                        label: 'All Essays (${_essaySubmissions.length})',
                        isSelected: _filterStatus == 'all',
                        onTap: () => setState(() => _filterStatus = 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterChip(
                        label: 'Pending ($pendingCount)',
                        isSelected: _filterStatus == 'pending',
                        onTap: () => setState(() => _filterStatus = 'pending'),
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterChip(
                        label: 'Graded ($gradedCount)',
                        isSelected: _filterStatus == 'graded',
                        onTap: () => setState(() => _filterStatus = 'graded'),
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap on a student card to expand and view details',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ),
      body:
          _isLoading
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading submissions...',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              )
              : filteredSubmissions.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.inbox,
                        size: 60,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _filterStatus == 'all'
                          ? 'No essay submissions yet'
                          : 'No ${_filterStatus} essays',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Students haven\'t submitted essays for this assignment yet.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _loadEssaySubmissions,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Colors.white,
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  itemCount: filteredSubmissions.length,
                  itemBuilder: (context, index) {
                    return _buildEssayCard(filteredSubmissions[index]);
                  },
                ),
              ),
    );
  }
}

// Video viewer widget
class _VideoViewerWidget extends StatefulWidget {
  final String videoUrl;

  const _VideoViewerWidget({required this.videoUrl});

  @override
  State<_VideoViewerWidget> createState() => _VideoViewerWidgetState();
}

class _VideoViewerWidgetState extends State<_VideoViewerWidget> {
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: false,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      showControls: true,
      placeholder: Container(
        color: Colors.grey[300],
        child: const Center(child: Icon(Icons.videocam, size: 50)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Chewie(controller: _chewieController);
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController.dispose();
    super.dispose();
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : chipColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipColor, width: isSelected ? 2 : 1),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: chipColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                  : [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : chipColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

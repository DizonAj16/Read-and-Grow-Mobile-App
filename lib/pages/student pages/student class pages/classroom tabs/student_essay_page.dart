import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';

class StudentEssayPage extends StatefulWidget {
  final String assignmentId;
  final String studentId;
  final String? lessonTitle;
  final String taskId;
  final String? courseId;
  final String? moduleId;
  final VoidCallback? onSubmissionComplete;

  const StudentEssayPage({
    super.key,
    required this.assignmentId,
    required this.studentId,
    required this.taskId,
    this.lessonTitle,
    this.courseId,
    this.moduleId,
    this.onSubmissionComplete,
  });

  @override
  State<StudentEssayPage> createState() => _StudentEssayPageState();
}

class _StudentEssayPageState extends State<StudentEssayPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isLoadingMaterials = true;
  List<Map<String, dynamic>> _essayQuestions = [];
  List<Map<String, dynamic>> _lessonMaterials = [];
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, List<PlatformFile>> _attachedFiles = {};
  final Map<String, List<String>> _uploadedFileUrls = {};
  bool _isSubmitting = false;
  String? _essayAssignmentId;
  bool _hasSubmittedPreviously = false;
  Map<String, dynamic>? _previousSubmission;
  String _errorMessage = '';
  bool _hasError = false;
  final _formKey = GlobalKey<FormState>();
  final Map<String, bool> _questionValidation = {};
  StreamSubscription? _internetConnectionSubscription;
  bool _isOffline = false;
  bool _isConnected = true;

  bool _hasStartedEssay = false;
  bool _progressRecorded = false;

  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
    _loadEssayQuestions();
    _loadLessonMaterials();
    _checkPreviousSubmission();
    _checkIfAlreadyStarted(); // Add this line
  }

  // Add this method to check if already started
  Future<void> _checkIfAlreadyStarted() async {
    if (_isOffline) return;

    try {
      final existingProgress = await _supabase
          .from('student_task_progress')
          .select()
          .eq('student_id', widget.studentId)
          .eq('task_id', widget.taskId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (existingProgress != null) {
        setState(() {
          _progressRecorded = true;
        });
      }
    } catch (e) {
      debugPrint('Error checking essay progress: $e');
    }
  }

  @override
  void dispose() {
    _internetConnectionSubscription?.cancel();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // Check internet connection
  Future<void> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      setState(() {
        _isConnected = result.isNotEmpty;
        _isOffline = !_isConnected;
        if (_isOffline) {
          _errorMessage = 'No internet connection. Please check your network.';
          _hasError = true;
        }
      });
    } on TimeoutException {
      setState(() {
        _isConnected = false;
        _isOffline = true;
        _errorMessage =
            'Connection timeout. Please check your internet connection.';
        _hasError = true;
      });
    } on SocketException {
      setState(() {
        _isConnected = false;
        _isOffline = true;
        _errorMessage = 'No internet connection. Please check your network.';
        _hasError = true;
      });
    } catch (e) {
      debugPrint('Error checking internet connection: $e');
      setState(() {
        _isConnected = false;
        _isOffline = true;
        _errorMessage = 'Network error. Please check your connection.';
        _hasError = true;
      });
    }
  }

  // Check if student has already submitted
  Future<void> _checkPreviousSubmission() async {
    if (_isOffline) return;

    try {
      final response = await _supabase
          .from('student_essay_responses')
          .select('*')
          .eq('student_id', widget.studentId)
          .eq('assignment_id', widget.assignmentId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (response != null) {
        setState(() {
          _hasSubmittedPreviously = true;
          _previousSubmission = response;
        });
      }
    } on TimeoutException {
      debugPrint('Timeout checking previous submission');
    } catch (e) {
      debugPrint('Error checking previous submission: $e');
    }
  }

  Future<void> _loadEssayQuestions() async {
    if (_isOffline) {
      setState(() {
        _hasError = true;
        _errorMessage =
            'No internet connection. Please check your network and try again.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      if (widget.assignmentId.isEmpty) {
        throw FormatException('Invalid assignment ID');
      }

      final assignmentRes = await _supabase
          .from('assignments')
          .select('essay_assignments(*)')
          .eq('id', widget.assignmentId)
          .single()
          .timeout(const Duration(seconds: 30));

      if (assignmentRes == null || assignmentRes.isEmpty) {
        throw Exception('Assignment not found');
      }

      final essayAssignments = assignmentRes['essay_assignments'];
      if (essayAssignments == null ||
          (essayAssignments is List && essayAssignments.isEmpty)) {
        setState(() {
          _essayQuestions = [];
          _isLoading = false;
        });
        return;
      }

      final essayAssignment =
          essayAssignments is List
              ? essayAssignments.first as Map<String, dynamic>
              : essayAssignments as Map<String, dynamic>;

      if (essayAssignment['id'] == null) {
        throw FormatException('Invalid essay assignment data');
      }

      _essayAssignmentId = essayAssignment['id']?.toString();

      final questionsRes = await _supabase
          .from('essay_questions')
          .select('*')
          .eq('essay_assignment_id', _essayAssignmentId!)
          .order('sort_order', ascending: true) // Ensure this is ASCENDING
          .timeout(const Duration(seconds: 30));

      if (questionsRes == null) {
        throw Exception('Failed to load essay questions');
      }

      setState(() {
        _essayQuestions = List<Map<String, dynamic>>.from(questionsRes);

        for (var question in _essayQuestions) {
          final questionId = question['id'].toString();
          _controllers[questionId] = TextEditingController();
          _attachedFiles[questionId] = [];
          _uploadedFileUrls[questionId] = [];
          _questionValidation[questionId] = false;
        }

        _isLoading = false;
      });
      // Track progress after questions are loaded
      if (!_hasSubmittedPreviously &&
          !_progressRecorded &&
          _essayQuestions.isNotEmpty) {
        _trackEssayProgress();
      }
    } on TimeoutException {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage =
            'Connection timeout. Please check your internet connection and try again.';
      });
    } on FormatException catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Data format error: ${e.message}';
      });
    } catch (e) {
      debugPrint('Error loading essay questions: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = _getUserFriendlyErrorMessage(e);
      });
    }
  }

  Future<void> _loadLessonMaterials() async {
    if (_isOffline) {
      setState(() {
        _isLoadingMaterials = false;
        _lessonMaterials = [];
      });
      return;
    }

    setState(() {
      _isLoadingMaterials = true;
    });

    try {
      if (widget.taskId.isEmpty) {
        throw FormatException('Invalid task ID');
      }

      final materialsRes = await _supabase
          .from('task_materials')
          .select('*')
          .eq('task_id', widget.taskId)
          .timeout(const Duration(seconds: 30));

      setState(() {
        _lessonMaterials = List<Map<String, dynamic>>.from(materialsRes ?? []);
        _isLoadingMaterials = false;
      });
    } on TimeoutException {
      setState(() {
        _isLoadingMaterials = false;
        _lessonMaterials = [];
      });
    } catch (e) {
      debugPrint('Error loading lesson materials: $e');
      setState(() {
        _isLoadingMaterials = false;
        _lessonMaterials = [];
      });
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    if (error is String) {
      if (error.contains('timeout')) {
        return 'Connection timeout. Please check your internet connection and try again.';
      }
      if (error.contains('network')) {
        return 'Network error. Please check your internet connection.';
      }
      if (error.contains('permission') || error.contains('auth')) {
        return 'You do not have permission to access this assignment.';
      }
      if (error.contains('not found')) {
        return 'Assignment not found. It may have been removed.';
      }
      return error;
    }

    if (error is TimeoutException) {
      return 'Request timeout. Please try again.';
    }

    if (error is SocketException) {
      return 'No internet connection. Please check your network settings.';
    }

    if (error is PlatformException) {
      return 'An error occurred: ${error.message ?? "Unknown platform error"}';
    }

    if (error is FormatException) {
      return 'Data format error. Please contact support.';
    }

    if (error is PostgrestException) {
      return 'Database error: ${error.message}';
    }

    if (error is StorageException) {
      return 'Storage error: ${error.message}';
    }

    if (error is AuthException) {
      return 'Authentication error: ${error.message}';
    }

    if (error is Exception) {
      final errorStr = error.toString();
      return errorStr.replaceAll('Exception: ', '').replaceAll('Error: ', '');
    }

    return 'An unexpected error occurred. Please try again.';
  }

  int _countWords(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  Future<void> _pickFiles(String questionId) async {
    if (_isOffline) {
      _showErrorSnackbar('No internet connection. Cannot pick files.');
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform
          .pickFiles(
            type: FileType.custom,
            allowedExtensions: [
              'pdf',
              'doc',
              'docx',
              'jpg',
              'jpeg',
              'png',
              'txt',
            ],
            allowMultiple: true,
          )
          .timeout(const Duration(seconds: 30));

      if (result != null) {
        final oversizedFiles =
            result.files.where((file) => file.size > 10 * 1024 * 1024).toList();
        if (oversizedFiles.isNotEmpty) {
          _showErrorDialog(
            'File Size Error',
            'Some files exceed the 10MB limit:\n${oversizedFiles.map((f) => f.name).join('\n')}',
          );
          return;
        }

        final totalSize = result.files.fold<int>(
          0,
          (sum, file) => sum + file.size,
        );
        if (totalSize > 50 * 1024 * 1024) {
          _showErrorDialog(
            'Total Size Error',
            'Total file size exceeds 50MB limit. Please select fewer files.',
          );
          return;
        }

        setState(() {
          _attachedFiles[questionId]!.addAll(result.files);
        });

        _showSuccessSnackbar(
          '${result.files.length} file(s) attached successfully',
        );
      }
    } on TimeoutException {
      _showErrorSnackbar('File picker timeout. Please try again.');
    } on PlatformException catch (e) {
      _showErrorSnackbar('File picker error: ${e.message}');
    } catch (e) {
      _showErrorSnackbar(
        'Error picking files: ${_getUserFriendlyErrorMessage(e)}',
      );
    }
  }

  void _removeFile(String questionId, int index) {
    setState(() {
      _attachedFiles[questionId]!.removeAt(index);
    });
  }

  Future<String?> _uploadFile(PlatformFile file) async {
    if (_isOffline) {
      throw SocketException('No internet connection');
    }

    try {
      if (file.path == null) {
        throw Exception('File path is null');
      }

      final fileExtension = file.extension?.toLowerCase() ?? '';
      final allowedExtensions = [
        'pdf',
        'doc',
        'docx',
        'jpg',
        'jpeg',
        'png',
        'txt',
      ];
      if (!allowedExtensions.contains(fileExtension)) {
        throw FormatException('File type .$fileExtension is not allowed');
      }

      if (file.size > 10 * 1024 * 1024) {
        throw Exception('File size exceeds 10MB limit');
      }

      final fileName =
          'essay_${widget.studentId}_${DateTime.now().millisecondsSinceEpoch}_${_sanitizeFileName(file.name)}';

      final fileBytes = await File(file.path!).readAsBytes();
      if (fileBytes.isEmpty) {
        throw Exception('File is empty or corrupted');
      }

      final response = await _supabase.storage
          .from('essay_submissions')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _getMimeType(fileExtension),
            ),
          )
          .timeout(const Duration(seconds: 60));

      if (response.isEmpty) {
        throw Exception('Failed to upload file: Empty response');
      }

      final fileUrl = _supabase.storage
          .from('essay_submissions')
          .getPublicUrl(fileName);

      return fileUrl;
    } on TimeoutException {
      throw TimeoutException('File upload timeout');
    } on StorageException catch (e) {
      throw Exception('Storage error: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  String _getMimeType(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-_]'), '_');
  }

  bool _validateAllQuestions() {
    bool allValid = true;

    for (var question in _essayQuestions) {
      final questionId = question['id'].toString();
      final controller = _controllers[questionId];
      final hasText = controller != null && controller.text.trim().isNotEmpty;
      final hasFiles = _attachedFiles[questionId]?.isNotEmpty ?? false;
      final wordLimit = question['word_limit'] as int?;
      final wordCount = _countWords(controller?.text ?? '');

      bool isValid = hasText || hasFiles;
      if (wordLimit != null && wordCount > wordLimit) {
        isValid = false;
      }

      _questionValidation[questionId] = isValid;
      if (!isValid) allValid = false;
    }

    return allValid;
  }

  Future<void> _submitEssays() async {
    if (_isSubmitting) return;

    if (_hasSubmittedPreviously) {
      _showErrorDialog(
        'Already Submitted',
        'You have already submitted this essay assignment. You cannot submit again.',
      );
      return;
    }

    if (_isOffline) {
      _showErrorDialog(
        'No Internet Connection',
        'You need an internet connection to submit your essay. Please check your connection and try again.',
      );
      return;
    }

    if (!_validateAllQuestions()) {
      _showErrorSnackbar('Please complete all questions and check word limits');
      return;
    }

    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    setState(() => _isSubmitting = true);

    bool shouldNavigateBack = false;
    String? successMessage;

    try {
      // Upload all files first
      final uploadErrors = <String>[];

      for (var question in _essayQuestions) {
        final questionId = question['id'].toString();
        final files = _attachedFiles[questionId] ?? [];

        for (var file in files) {
          try {
            final fileUrl = await _uploadFile(file);
            if (fileUrl != null) {
              _uploadedFileUrls[questionId]!.add(fileUrl);
            } else {
              uploadErrors.add('Failed to upload: ${file.name}');
            }
          } catch (e) {
            uploadErrors.add(
              'Error uploading ${file.name}: ${_getUserFriendlyErrorMessage(e)}',
            );
          }
        }
      }

      if (uploadErrors.isNotEmpty) {
        throw Exception('File upload errors:\n${uploadErrors.join('\n')}');
      }

      // Save essay responses
      final saveErrors = <String>[];
      final successfulResponses = <Map<String, dynamic>>[];

      for (var question in _essayQuestions) {
        final questionId = question['id'].toString();
        final controller = _controllers[questionId]!;
        final wordCount = _countWords(controller.text);
        final wordLimit = question['word_limit'] as int?;

        if (wordLimit != null && wordCount > wordLimit) {
          saveErrors.add(
            'Question ${_essayQuestions.indexOf(question) + 1}: Word count ($wordCount) exceeds limit ($wordLimit)',
          );
          continue;
        }

        try {
          final response = await _supabase
              .from('student_essay_responses')
              .insert({
                'student_id': widget.studentId,
                'assignment_id': widget.assignmentId,
                'question_id': questionId,
                'response_text': controller.text.trim(),
                'word_count': wordCount,
                'submitted_at': DateTime.now().toIso8601String(),
                'is_graded': false,
                'attached_files': _uploadedFileUrls[questionId],
              })
              .select()
              .single()
              .timeout(const Duration(seconds: 30));

          if (response == null) {
            saveErrors.add(
              'Failed to save response for question ${_essayQuestions.indexOf(question) + 1}',
            );
          } else {
            successfulResponses.add(response);
          }
        } catch (e) {
          saveErrors.add(
            'Error saving question ${_essayQuestions.indexOf(question) + 1}: ${_getUserFriendlyErrorMessage(e)}',
          );
        }
      }

      if (saveErrors.isNotEmpty) {
        // Rollback successful responses
        if (successfulResponses.isNotEmpty) {
          for (var response in successfulResponses) {
            try {
              await _supabase
                  .from('student_essay_responses')
                  .delete()
                  .eq('id', response['id']);
            } catch (e) {
              debugPrint('Error rolling back response: $e');
            }
          }
        }
        throw Exception(
          'Failed to save some responses:\n${saveErrors.join('\n')}',
        );
      }

      // Record submission in student_submissions
      try {
        await _supabase.from('student_submissions').insert({
          'assignment_id': widget.assignmentId,
          'student_id': widget.studentId,
          'submitted_at': DateTime.now().toIso8601String(),
          'score': 0,
          'max_score': 100,
          'attempt_number': 1,
        });

        // ========== UPDATE STUDENT TASK PROGRESS ==========
        // Mark progress as completed
        await _supabase
            .from('student_task_progress')
            .update({
              'completed': true,
              'score': 100, // Essay is submitted, consider it complete
              'max_score': 100,
              'updated_at': DateTime.now().toIso8601String(),
              'activity_details': {
                ..._buildActivityDetails(),
                'submitted_at': DateTime.now().toIso8601String(),
                'total_words': _controllers.values.fold<int>(
                  0,
                  (sum, c) => sum + _countWords(c.text),
                ),
                'total_files': _attachedFiles.values.fold<int>(
                  0,
                  (sum, files) => sum + files.length,
                ),
              },
            })
            .eq('student_id', widget.studentId)
            .eq('task_id', widget.taskId);
      } catch (e) {
        // Clean up essay responses if submission recording fails
        for (var question in _essayQuestions) {
          try {
            await _supabase
                .from('student_essay_responses')
                .delete()
                .eq('student_id', widget.studentId)
                .eq('assignment_id', widget.assignmentId)
                .eq('question_id', question['id'].toString());
          } catch (deleteError) {
            debugPrint(
              'Error cleaning up after submission failure: $deleteError',
            );
          }
        }
        throw Exception('Failed to record submission. Please try again.');
      }

      // Success
      shouldNavigateBack = true;
      successMessage = 'Essay submitted successfully!';
    } catch (e) {
      debugPrint('Error submitting essay: $e');
      if (mounted) {
        _showErrorDialog(
          'Submission Failed',
          'Failed to submit essay:\n${_getUserFriendlyErrorMessage(e)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);

        // Handle success
        if (shouldNavigateBack) {
          _showSuccessSnackbar(successMessage!);

          if (mounted) {
            _navigateBackToClassContent();
          }
        }
      }
    }
  }

  void _navigateBackToClassContent() {
    // Option 1: Simple pop with callback
    Navigator.of(context).pop(true); // Pass true to indicate success

    // Option 2: Use a result callback
    if (widget.onSubmissionComplete != null) {
      widget.onSubmissionComplete!();
    }
  }

  Future<bool> _showConfirmationDialog() async {
    final totalWordCount = _controllers.values.fold<int>(
      0,
      (sum, controller) => sum + _countWords(controller.text),
    );
    final totalFiles = _attachedFiles.values.fold<int>(
      0,
      (sum, files) => sum + files.length,
    );

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Submit Essay'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Are you sure you want to submit your essay?'),
                  const SizedBox(height: 12),
                  Text('• Total words: $totalWordCount'),
                  Text('• Total files: $totalFiles'),
                  Text('• Questions: ${_essayQuestions.length}'),
                  const SizedBox(height: 8),
                  const Text(
                    '⚠️ You will be redirected to the class content page after submission.',
                    style: TextStyle(color: Colors.blue),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '⚠️ You cannot edit it after submission.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text(
                  'Submit & Exit',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Widget _buildLessonMaterialsSection() {
    if (_isLoadingMaterials) {
      return const _LoadingIndicator(message: 'Loading materials...');
    }

    if (_lessonMaterials.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(Icons.library_books, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'No lesson materials available',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.library_books,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Lesson Materials',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        ..._lessonMaterials.map((material) {
          return _buildMaterialCard(material);
        }).toList(),
      ],
    );
  }

  Widget _buildMaterialCard(Map<String, dynamic> material) {
    final colorScheme = Theme.of(context).colorScheme;

    final title = material['material_title']?.toString() ?? 'Untitled Material';
    final description = material['description']?.toString();
    final filePath = material['material_file_path']?.toString();
    final materialType = material['material_type']?.toString() ?? 'pdf';

    String fileUrl = '';
    if (filePath != null && filePath.isNotEmpty) {
      try {
        fileUrl = _supabase.storage.from('materials').getPublicUrl(filePath);
      } catch (e) {
        debugPrint('Error getting file URL: $e');
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _getMaterialColor(materialType).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getMaterialIcon(materialType),
                    color: _getMaterialColor(materialType),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (description != null && description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (fileUrl.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      Icons.open_in_new,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed:
                        () => _viewMaterial(fileUrl, materialType, title),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getMaterialColor(materialType),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    materialType.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  fileUrl.isEmpty ? 'No file available' : 'Tap to view',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewMaterial(
    String url,
    String materialType,
    String title,
  ) async {
    if (url.isEmpty) {
      _showErrorSnackbar('No file available to open');
      return;
    }

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => Scaffold(
                appBar: AppBar(
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                body: _getMaterialViewer(url, materialType),
              ),
        ),
      );
    } catch (e) {
      _showErrorSnackbar(
        'Failed to open material: ${_getUserFriendlyErrorMessage(e)}',
      );
    }
  }

  Widget _getMaterialViewer(String url, String materialType) {
    try {
      switch (materialType.toLowerCase()) {
        case 'pdf':
          return SfPdfViewer.network(
            url,
            canShowScrollHead: true,
            canShowScrollStatus: true,
          );
        case 'image':
        case 'jpg':
        case 'jpeg':
        case 'png':
          return PhotoView(
            imageProvider: NetworkImage(url),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 2,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder:
                (context, event) => Center(
                  child: CircularProgressIndicator(
                    value:
                        event == null
                            ? null
                            : event.cumulativeBytesLoaded /
                                event.expectedTotalBytes!,
                  ),
                ),
          );
        case 'video':
          return _VideoPlayerWidget(videoUrl: url);
        default:
          return _UnsupportedFileViewer(
            fileType: materialType,
            onDownload: () => _downloadFile(url, materialType),
          );
      }
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load file',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              _getUserFriendlyErrorMessage(e),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }

  Future<void> _downloadFile(String url, String materialType) async {
    _showSuccessSnackbar('Download started for $materialType file...');
  }

  IconData _getMaterialIcon(String materialType) {
    switch (materialType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      case 'image':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getMaterialColor(String materialType) {
    switch (materialType.toLowerCase()) {
      case 'pdf':
        return Colors.red[700]!;
      case 'video':
        return Colors.purple[700]!;
      case 'audio':
        return Colors.orange[700]!;
      case 'image':
        return Colors.green[700]!;
      default:
        return Colors.blue[700]!;
    }
  }

  Widget _buildEssayQuestion(Map<String, dynamic> question, int index) {
    final questionId = question['id'].toString();
    final controller = _controllers[questionId]!;
    final wordCount = _countWords(controller.text);
    final wordLimit = question['word_limit'] as int?;
    final questionImageUrl = question['question_image_url']?.toString();
    final attachedFiles = _attachedFiles[questionId] ?? [];
    final hasText = controller.text.trim().isNotEmpty;
    final hasFiles = attachedFiles.isNotEmpty;
    final isValid = _questionValidation[questionId] ?? true;
    final isInvalid = !isValid && (hasText || hasFiles);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            isInvalid
                ? const BorderSide(color: Colors.red, width: 2)
                : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Essay Question ${index + 1}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isInvalid) const Icon(Icons.error, color: Colors.red),
              ],
            ),
            const SizedBox(height: 12),

            if (questionImageUrl != null && questionImageUrl.isNotEmpty)
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
                                  title: const Text('Question Image'),
                                ),
                                body: PhotoView(
                                  imageProvider: NetworkImage(questionImageUrl),
                                  minScale:
                                      PhotoViewComputedScale.contained * 0.8,
                                  maxScale: PhotoViewComputedScale.covered * 2,
                                ),
                              ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        questionImageUrl,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 180,
                            color: Colors.grey[200],
                            child: Center(
                              child: CircularProgressIndicator(
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress
                                                .cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 180,
                            color: Colors.grey[300],
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 8),
                                  Text('Failed to load image'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            Text(
              question['question_text']?.toString() ?? '',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),

            if (wordLimit != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.text_fields, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Word Limit: $wordLimit words',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            Form(
              key: Key(questionId),
              child: TextFormField(
                controller: controller,
                maxLines: 15,
                minLines: 8,
                maxLength: wordLimit != null ? wordLimit * 10 : null,
                decoration: InputDecoration(
                  hintText: 'Write your essay here...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  suffixText: '$wordCount words',
                  suffixStyle: TextStyle(
                    color:
                        wordLimit != null && wordCount > wordLimit
                            ? Colors.red
                            : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onChanged: (_) {
                  setState(() {
                    _questionValidation[questionId] = true;
                  });
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    if (attachedFiles.isEmpty) {
                      return 'Please write an answer or attach files';
                    }
                  }
                  if (wordLimit != null && _countWords(value!) > wordLimit) {
                    return 'Word count exceeds limit';
                  }
                  return null;
                },
              ),
            ),

            if (wordLimit != null)
              Column(
                children: [
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: wordCount / wordLimit,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      wordCount > wordLimit ? Colors.red : Colors.green,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        wordCount > wordLimit
                            ? '${wordCount - wordLimit} words over limit'
                            : '${wordLimit - wordCount} words remaining',
                        style: TextStyle(
                          color:
                              wordCount > wordLimit ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${((wordCount / wordLimit) * 100).toInt()}%',
                        style: TextStyle(
                          color:
                              wordCount > wordLimit ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

            const SizedBox(height: 20),

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
                        Icons.attach_file,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Attachments (Optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Add Files',
                        child: IconButton(
                          onPressed: () => _pickFiles(questionId),
                          icon: Icon(
                            Icons.upload_file,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            side: BorderSide(color: Colors.blue[300]!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supported: PDF, DOC, DOCX, JPG, PNG, TXT (Max 10MB each, 50MB total)',
                    style: TextStyle(fontSize: 11, color: Colors.blue[600]),
                  ),

                  if (attachedFiles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...attachedFiles.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final file = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[300]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getFileIcon(file.extension ?? ''),
                                color: Colors.blue[700],
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  Text(
                                    _formatFileSize(file.size),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Tooltip(
                              message: 'Remove',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                onPressed: () => _removeFile(questionId, idx),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red[50],
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(30, 30),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildErrorView() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 20),
            Text(
              'Error Loading Assignment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _checkInternetConnection();
                _loadEssayQuestions();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmittedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 20),
            const Text(
              'Already Submitted',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'You have already submitted this essay assignment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            if (_previousSubmission != null)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Submission Details',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Submitted on:'),
                            Text(
                              _formatDate(_previousSubmission!['submitted_at']),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Words:'),
                            Text(
                              '${_previousSubmission!['word_count']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (_previousSubmission!['is_graded'] == true)
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Grade:'),
                                  Text(
                                    '${_previousSubmission!['teacher_score'] ?? 'Not graded'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Class Content'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    try {
      if (date is String) {
        final dateTime = DateTime.parse(date).toLocal();
        return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      }
      return 'Unknown date';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange[50],
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are offline. Some features may be limited.',
              style: TextStyle(color: Colors.orange[800]),
            ),
          ),
          TextButton(
            onPressed: _checkInternetConnection,
            child: Text(
              'Retry',
              style: TextStyle(
                color: Colors.orange[800],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this method to track essay progress
  Future<void> _trackEssayProgress() async {
    if (_progressRecorded || _isOffline) return;

    try {
      // Check if progress record exists
      final existingProgress = await _supabase
          .from('student_task_progress')
          .select()
          .eq('student_id', widget.studentId)
          .eq('task_id', widget.taskId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (existingProgress != null) {
        // Update existing record
        await _supabase
            .from('student_task_progress')
            .update({
              'updated_at': DateTime.now().toIso8601String(),
              'activity_details': _buildActivityDetails(),
            })
            .eq('id', existingProgress['id']);
      } else {
        // Create new progress record
        await _supabase.from('student_task_progress').insert({
          'student_id': widget.studentId,
          'task_id': widget.taskId,
          'attempts_left': 3,
          'score': 0,
          'max_score': 100,
          'activity_details': _buildActivityDetails(),
          'correct_answers': 0,
          'wrong_answers': 0,
          'completed': false,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      setState(() {
        _progressRecorded = true;
      });
    } catch (e) {
      debugPrint('Error tracking essay progress: $e');
    }
  }

  // Add this helper method to build activity details
  Map<String, dynamic> _buildActivityDetails() {
    return {
      'essay_assignment_id': _essayAssignmentId,
      'questions_count': _essayQuestions.length,
      'started_at': DateTime.now().toIso8601String(),
      'has_attachments': _attachedFiles.values.any((files) => files.isNotEmpty),
      'has_responses': _controllers.values.any((c) => c.text.trim().isNotEmpty),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lessonTitle ?? 'Essay Assignment'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          if (!_isLoading && !_hasError && !_hasSubmittedPreviously)
            Tooltip(
              message: 'Submission Guidelines',
              child: IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('Essay Guidelines'),
                          content: const SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('• Write your response in the text box'),
                                SizedBox(height: 8),
                                Text(
                                  '• You can attach files (PDF, DOC, DOCX, images, text)',
                                ),
                                SizedBox(height: 8),
                                Text('• Maximum file size: 10MB per file'),
                                SizedBox(height: 8),
                                Text('• Maximum total size: 50MB'),
                                SizedBox(height: 8),
                                Text('• Follow the word limit if specified'),
                                SizedBox(height: 8),
                                Text(
                                  '• Your teacher will grade your submission',
                                ),
                                SizedBox(height: 8),
                                Text('• You cannot edit after submission'),
                                SizedBox(height: 8),
                                Text(
                                  '• Ensure you have stable internet connection',
                                ),
                                SizedBox(height: 8),
                                Text('• Save your work periodically'),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                  );
                },
              ),
            ),
        ],
      ),
      body:
          _isLoading
              ? const _LoadingIndicator(message: 'Loading essay assignment...')
              : _hasError
              ? _buildErrorView()
              : _hasSubmittedPreviously
              ? _buildSubmittedView()
              : _essayQuestions.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.assignment, size: 80, color: Colors.grey),
                    const SizedBox(height: 20),
                    const Text(
                      'No essay questions available',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              )
              : Column(
                children: [
                  if (_isOffline) _buildOfflineBanner(),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Lesson Materials
                          if (!_isLoadingMaterials &&
                              _lessonMaterials.isNotEmpty)
                            _buildLessonMaterialsSection(),

                          const SizedBox(height: 16),

                          // Essay Questions
                          ..._essayQuestions.asMap().entries.map((entry) {
                            final index = entry.key;
                            final question = entry.value;
                            return _buildEssayQuestion(question, index);
                          }).toList(),

                          // Submit Button
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                top: BorderSide(color: Colors.grey[300]!),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, -5),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed:
                                  _isSubmitting || _isOffline
                                      ? null
                                      : _submitEssays,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 55),
                                backgroundColor:
                                    _isOffline
                                        ? Colors.grey
                                        : Theme.of(context).colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                                shadowColor: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.3),
                              ),
                              child:
                                  _isSubmitting
                                      ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                      : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.send,
                                            color:
                                                _isOffline
                                                    ? Colors.grey[300]
                                                    : Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _isOffline
                                                ? 'Offline - Cannot Submit'
                                                : 'Submit All Essays',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  _isOffline
                                                      ? Colors.grey[300]
                                                      : Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      bottomNavigationBar:
          _hasSubmittedPreviously
              ? null
              : SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isOffline)
                        Text(
                          '⚠️ Offline Mode - Submission disabled',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      Text(
                        'Total Questions: ${_essayQuestions.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  final String message;

  const _LoadingIndicator({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: 3,
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerWidget({required this.videoUrl});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _videoPlayerController.initialize().timeout(
        const Duration(seconds: 30),
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
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 50, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load video',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );

      setState(() {
        _isLoading = false;
      });
    } on TimeoutException {
      setState(() {
        _isLoading = false;
        _error = 'Video loading timeout';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty || _chewieController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Failed to load video',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              _error,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeVideo,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Chewie(controller: _chewieController!);
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}

class _UnsupportedFileViewer extends StatelessWidget {
  final String fileType;
  final VoidCallback onDownload;

  const _UnsupportedFileViewer({
    required this.fileType,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
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
              Icons.insert_drive_file,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Preview not available for .$fileType files',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onDownload,
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
}

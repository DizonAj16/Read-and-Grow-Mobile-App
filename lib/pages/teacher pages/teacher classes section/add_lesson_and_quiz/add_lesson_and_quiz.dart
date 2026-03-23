import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../api/supabase_api_service.dart';
import '../../../../models/quiz_questions.dart';
import '../../quiz_preview_screen.dart';
import '../../../../utils/file_validator.dart';

class AddLessonWithQuizScreen extends StatefulWidget {
  final String? readingLevelId;
  final Map<String, dynamic> classDetails;

  const AddLessonWithQuizScreen({
    super.key,
    this.readingLevelId,
    required this.classDetails,
  });

  @override
  State<AddLessonWithQuizScreen> createState() =>
      _AddLessonWithQuizScreenState();
}

class _AddLessonWithQuizScreenState extends State<AddLessonWithQuizScreen> {
  // Lesson controllers
  final _lessonTitleController = TextEditingController();
  final _lessonDescController = TextEditingController();
  final _lessonTimeController = TextEditingController();
  // bool _unlocksNextLevel = false;

  // Quiz controllers
  final _quizTitleController = TextEditingController();
  List<QuizQuestion> _questions = [];

  bool _isLoading = false;
  String? _uploadedFileUrl;
  String? _uploadedFilePath;
  String? _uploadedFileType;
  String? _uploadedFileExtension;

  // Validation
  final Map<String, String> _validationErrors = {};
  final Map<int, Map<String, String>> _questionValidationErrors = {};

  // Track focus nodes for proper newline handling
  final Map<int, FocusNode> _questionFocusNodes = {};
  final Map<int, Map<int, FocusNode>> _optionFocusNodes = {};

  // Track option images for multiple choice with pictures
  final Map<int, Map<int, String?>> _optionImages = {};

  FocusNode _getQuestionFocusNode(int index) {
    if (!_questionFocusNodes.containsKey(index)) {
      _questionFocusNodes[index] = FocusNode();
    }
    return _questionFocusNodes[index]!;
  }

  FocusNode _getOptionFocusNode(int questionIndex, int optionIndex) {
    if (!_optionFocusNodes.containsKey(questionIndex)) {
      _optionFocusNodes[questionIndex] = {};
    }
    if (!_optionFocusNodes[questionIndex]!.containsKey(optionIndex)) {
      _optionFocusNodes[questionIndex]![optionIndex] = FocusNode();
    }
    return _optionFocusNodes[questionIndex]![optionIndex]!;
  }

  String? _getOptionImage(int questionIndex, int optionIndex) {
    if (!_optionImages.containsKey(questionIndex)) {
      _optionImages[questionIndex] = {};
    }
    return _optionImages[questionIndex]![optionIndex];
  }

  void _setOptionImage(int questionIndex, int optionIndex, String? imageUrl) {
    if (!_optionImages.containsKey(questionIndex)) {
      _optionImages[questionIndex] = {};
    }
    _optionImages[questionIndex]![optionIndex] = imageUrl;
    setState(() {});
  }

  void _removeOptionImage(int questionIndex, int optionIndex) {
    if (_optionImages.containsKey(questionIndex)) {
      _optionImages[questionIndex]!.remove(optionIndex);
      setState(() {});
    }
  }

  void _addQuestion() {
    final defaultOptions = List.generate(4, (i) => 'Option ${i + 1}');
    final newQuestion = QuizQuestion(
      questionText: '',
      type: QuestionType.multipleChoice,
      options: defaultOptions,
      matchingPairs: [],
    );

    if (newQuestion.type == QuestionType.dragAndDrop) {
      newQuestion.options = defaultOptions;
    }

    if (newQuestion.type == QuestionType.trueFalse) {
      newQuestion.options = ['True', 'False'];
    }

    _questions.add(newQuestion);
    setState(() {});
  }

  void _deleteQuestion(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Question'),
            content: const Text(
              'Are you sure you want to delete this question?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Clean up focus nodes
                  _questionFocusNodes.remove(index);
                  _optionFocusNodes.remove(index);
                  _optionImages.remove(index);
                  // Remove the question
                  _questions.removeAt(index);
                  // Remove validation errors
                  _questionValidationErrors.remove(index);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Question deleted'),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  void _addOption(QuizQuestion question, int questionIndex) {
    final newIndex = (question.options?.length ?? 0) + 1;
    question.options?.add('Option $newIndex');

    // Initialize option image for this new option
    if (question.type == QuestionType.multipleChoiceWithImages) {
      if (!_optionImages.containsKey(questionIndex)) {
        _optionImages[questionIndex] = {};
      }
      _optionImages[questionIndex]![question.options!.length - 1] = null;
    }

    setState(() {});
  }

  void _deleteOption(
    QuizQuestion question,
    int questionIndex,
    int optionIndex,
  ) {
    if (question.options != null && question.options!.length > 2) {
      // Don't allow deletion if it would leave less than 2 options
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Delete Option'),
              content: const Text(
                'Are you sure you want to delete this option?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    question.options?.removeAt(optionIndex);

                    // Remove option image
                    if (_optionImages.containsKey(questionIndex)) {
                      _optionImages[questionIndex]!.remove(optionIndex);
                      // Shift other images up
                      for (
                        int i = optionIndex + 1;
                        i < _optionImages[questionIndex]!.length + 1;
                        i++
                      ) {
                        final image = _optionImages[questionIndex]![i];
                        if (image != null) {
                          _optionImages[questionIndex]![i - 1] = image;
                        }
                      }
                      _optionImages[questionIndex]!.remove(
                        _optionImages[questionIndex]!.length,
                      );
                    }

                    // If the deleted option was the correct answer, clear it
                    if (question.correctAnswer ==
                        question.options?[optionIndex]) {
                      question.correctAnswer = null;
                    }
                    setState(() {});
                  },
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Questions must have at least 2 options'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _addMatchingPair(QuizQuestion question) {
    question.matchingPairs ??= [];
    question.matchingPairs!.add(MatchingPair(leftItem: '', rightItemUrl: ''));
    setState(() {});
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'mp4', 'mp3', 'wav', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      
      // Front-end validation: Immediately check file size
      final validation = await validateFileSize(file);
      if (!validation.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validation.getUserMessage()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return; // Prevent upload button from triggering
      }

      final fileExtension = file.path.split('.').last.toLowerCase();

      final uploadedUrl = await ApiService.uploadFile(file);
      if (uploadedUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to upload file. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _uploadedFileUrl = uploadedUrl;
        _uploadedFilePath = _extractStoragePath(uploadedUrl);
        _uploadedFileExtension = fileExtension;
        if (['jpg', 'jpeg', 'png'].contains(fileExtension)) {
          _uploadedFileType = 'image';
        } else if (fileExtension == 'pdf') {
          _uploadedFileType = 'pdf';
        } else if (['mp4'].contains(fileExtension)) {
          _uploadedFileType = 'video';
        } else {
          _uploadedFileType = 'audio';
        }
      });
    }
  }

  Future<String?> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      File file = File(pickedFile.path);
      
      // Front-end validation: Immediately check file size
      final validation = await validateFileSize(file);
      if (!validation.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validation.getUserMessage()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null; // Prevent upload button from triggering
      }

      String? uploadedUrl = await ApiService.uploadFile(file);
      if (uploadedUrl == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return uploadedUrl;
    }
    return null;
  }

  Widget _buildFilePreview() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    if (_uploadedFileUrl == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_upload, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('No file uploaded', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    Widget previewWidget;
    Color iconColor = primaryColor;

    switch (_uploadedFileType) {
      case 'image':
        previewWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            _uploadedFileUrl!,
            height: 150,
            fit: BoxFit.contain,
          ),
        );
        iconColor = Colors.green;
      case 'pdf':
        previewWidget = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PDF Document',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                    Text(
                      _uploadedFileUrl!.split('/').last,
                      style: TextStyle(color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'video':
        previewWidget = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.videocam, color: Colors.purple, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video File',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple[700],
                      ),
                    ),
                    Text(
                      _uploadedFileUrl!.split('/').last,
                      style: TextStyle(color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'audio':
        previewWidget = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.audiotrack, color: Colors.orange, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audio File',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                    Text(
                      _uploadedFileUrl!.split('/').last,
                      style: TextStyle(color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        previewWidget = Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Uploaded File:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        previewWidget,
      ],
    );
  }

  // Validation Methods
  bool _validateForm() {
    _validationErrors.clear();
    _questionValidationErrors.clear();

    // Validate lesson title
    if (_lessonTitleController.text.trim().isEmpty) {
      _validationErrors['lessonTitle'] = 'Lesson title is required';
    }

    // Validate quiz title
    if (_quizTitleController.text.trim().isEmpty) {
      _validationErrors['quizTitle'] = 'Quiz title is required';
    }

    // Validate time limit
    if (_lessonTimeController.text.trim().isEmpty) {
      _validationErrors['timeLimit'] = 'Time limit is required';
    } else {
      final timeLimit = int.tryParse(_lessonTimeController.text.trim());
      if (timeLimit == null || timeLimit <= 0) {
        _validationErrors['timeLimit'] = 'Please enter a valid time limit';
      }
    }

    // Validate lesson material (REQUIRED)
    if (_uploadedFileUrl == null) {
      _validationErrors['lessonMaterial'] = 'Lesson material is required';
    }

    // Validate questions
    if (_questions.isEmpty) {
      _validationErrors['questions'] = 'At least one question is required';
    } else {
      for (int i = 0; i < _questions.length; i++) {
        final question = _questions[i];
        final questionErrors = <String, String>{};

        // Validate question text (unless it's an image-only multiple choice)
        if (question.questionText.trim().isEmpty &&
            question.type != QuestionType.multipleChoiceWithImages) {
          questionErrors['questionText'] = 'Question text is required';
        }

        // Validate correct answer for ALL question types
        switch (question.type) {
          case QuestionType.multipleChoice:
          case QuestionType.multipleChoiceWithImages:
            // Validate options - require at least 2 options
            if (question.options == null || question.options!.length < 2) {
              questionErrors['options'] = 'At least 2 options are required';
            } else {
              // For regular multiple choice, validate each option text
              if (question.type == QuestionType.multipleChoice) {
                for (int j = 0; j < question.options!.length; j++) {
                  if (question.options![j].trim().isEmpty) {
                    questionErrors['option_$j'] = 'Option ${j + 1} is required';
                  }
                }
              }
              // For multiple choice with images, either text or image must be provided
              else if (question.type == QuestionType.multipleChoiceWithImages) {
                for (int j = 0; j < question.options!.length; j++) {
                  final hasText = question.options![j].trim().isNotEmpty;
                  final hasImage = _getOptionImage(i, j) != null;
                  if (!hasText && !hasImage) {
                    questionErrors['option_$j'] =
                        'Option ${j + 1} needs either text or image';
                  }
                }
              }
            }
            // Validate correct answer selection
            if (question.correctAnswer == null ||
                question.correctAnswer!.isEmpty) {
              questionErrors['correctAnswer'] =
                  'Please select a correct answer';
            }
            break;

          case QuestionType.fillInTheBlank:
          case QuestionType.fillInTheBlankWithImage:
            if (question.correctAnswer == null ||
                question.correctAnswer!.trim().isEmpty) {
              questionErrors['correctAnswer'] = 'Correct answer is required';
            }
            break;

          case QuestionType.trueFalse:
            if (question.correctAnswer == null ||
                question.correctAnswer!.isEmpty) {
              questionErrors['correctAnswer'] = 'Please select True or False';
            }
            break;

          case QuestionType.matching:
            if (question.matchingPairs == null ||
                question.matchingPairs!.isEmpty) {
              questionErrors['matchingPairs'] =
                  'At least one matching pair is required';
            } else {
              // For matching questions, validate that all pairs are complete
              bool allPairsComplete = true;
              for (int j = 0; j < question.matchingPairs!.length; j++) {
                final pair = question.matchingPairs![j];
                if (pair.leftItem.trim().isEmpty) {
                  questionErrors['leftItem_$j'] = 'Left item text is required';
                  allPairsComplete = false;
                }
                if (pair.rightItemUrl == null || pair.rightItemUrl!.isEmpty) {
                  questionErrors['rightItem_$j'] =
                      'Right item image is required';
                  allPairsComplete = false;
                }
              }
              // If pairs exist but are incomplete, mark correct answer as required
              if (!allPairsComplete) {
                questionErrors['correctAnswer'] = 'Complete all matching pairs';
              }
            }
            break;

          case QuestionType.dragAndDrop:
            // Validate drag and drop options - require at least 2 items
            if (question.options == null || question.options!.length < 2) {
              questionErrors['dragDropOptions'] =
                  'At least 2 items are required for drag and drop';
            } else {
              // Validate each item text
              for (int j = 0; j < question.options!.length; j++) {
                if (question.options![j].trim().isEmpty) {
                  questionErrors['dragItem_$j'] = 'Item ${j + 1} is required';
                }
              }
            }
            // For drag and drop, the correct answer is the correct order
            // We need to ensure there's a defined correct sequence
            if (question.correctAnswer == null ||
                question.correctAnswer!.isEmpty) {
              questionErrors['correctAnswer'] =
                  'Please define the correct sequence';
            }
            break;

          default:
            // Generic validation for any other question types
            if (question.correctAnswer == null ||
                question.correctAnswer!.isEmpty) {
              questionErrors['correctAnswer'] = 'Correct answer is required';
            }
            break;
        }

        if (questionErrors.isNotEmpty) {
          _questionValidationErrors[i] = questionErrors;
        }
      }
    }

    setState(() {});
    return _validationErrors.isEmpty && _questionValidationErrors.isEmpty;
  }

  String? _getFieldError(String fieldName) {
    return _validationErrors[fieldName];
  }

  String? _getQuestionError(int questionIndex, String fieldName) {
    return _questionValidationErrors[questionIndex]?[fieldName];
  }

  void _clearFieldError(String fieldName) {
    if (_validationErrors.containsKey(fieldName)) {
      _validationErrors.remove(fieldName);
      setState(() {});
    }
  }

  void _clearQuestionError(int questionIndex, String fieldName) {
    if (_questionValidationErrors.containsKey(questionIndex)) {
      _questionValidationErrors[questionIndex]?.remove(fieldName);
      if (_questionValidationErrors[questionIndex]!.isEmpty) {
        _questionValidationErrors.remove(questionIndex);
      }
      setState(() {});
    }
  }

  Future<void> _submitLessonAndQuiz() async {
    if (!_validateForm()) {
      // Scroll to first error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = this.context;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please fix all errors before submitting'),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
      return;
    }

    if (_lessonTitleController.text.isEmpty ||
        _quizTitleController.text.isEmpty)
      return;

    setState(() => _isLoading = true);

    try {
      final hasAudioQuiz = _questions.any((q) => q.type == QuestionType.audio);
      final readingLevelId =
          widget.readingLevelId ?? widget.classDetails['reading_level_id'];

      if (hasAudioQuiz && readingLevelId == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio quiz requires a reading level')),
        );
        return;
      }

      // 1️⃣ Add Lesson
      debugPrint('Adding lesson...');
      final lesson = await ApiService.addLesson(
        readingLevelId: hasAudioQuiz ? readingLevelId : null,
        classRoomId: widget.classDetails['id'] as String,
        title: _lessonTitleController.text,
        description: _lessonDescController.text,
        timeLimitMinutes: int.tryParse(_lessonTimeController.text),
          // unlocksNextLevel: _unlocksNextLevel,
      );

      if (lesson == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to add lesson')));
        return;
      }

      debugPrint('Lesson added: ${lesson['id']}');

      // 2️⃣ Determine teacherId
      String? teacherId = widget.classDetails['teacher_id'];
      if (teacherId == null) {
        final teacherData =
            await Supabase.instance.client
                .from('teachers')
                .select('id')
                .eq('id', Supabase.instance.client.auth.currentUser!.id)
                .maybeSingle();
        teacherId = teacherData?['id'];
        if (teacherId == null) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to find teacher ID')),
          );
          return;
        }
      }
      debugPrint('Teacher ID: $teacherId');

      // 3️⃣ Insert assignment row (without quiz_id for now)
      final assignmentRes =
          await Supabase.instance.client
              .from('assignments')
              .insert({
                'class_room_id': widget.classDetails['id'],
                'task_id': lesson['id'],
                'teacher_id': teacherId,
              })
              .select()
              .maybeSingle();

      if (assignmentRes == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add assignment')),
        );
        return;
      }

      final assignmentId = assignmentRes['id'];
      debugPrint('Assignment created with id: $assignmentId');

      // 4️⃣ Save lesson material
      await _saveTaskMaterial(taskId: lesson['id'].toString());
      await _createClassMaterialRecord(
        classRoomId: widget.classDetails['id'] as String,
      );

      // 5️⃣ Add Quiz (with option images)
      debugPrint('Adding quiz...');
      final quiz = await ApiService.addQuiz(
        taskId: lesson['id'],
        title: _quizTitleController.text,
        questions: _questions,
        classRoomId: widget.classDetails['id'] as String,
        optionImages: _optionImages, // Pass option images
      );

      debugPrint('Quiz object returned: $quiz');
      final quizId = quiz?['quiz_id']; // <-- use 'quiz_id' instead of 'id'
      debugPrint('Quiz ID extracted: $quizId');

      if (quiz == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to add quiz')));
        return;
      }

      debugPrint('Quiz created with id: $quizId');

      // 6️⃣ Update assignment to include quiz_id
      await Supabase.instance.client
          .from('assignments')
          .update({'quiz_id': quizId})
          .eq('id', assignmentId);

      debugPrint('Assignment updated with quiz_id: $quizId');

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lesson & Quiz added successfully!')),
      );

      // Pass option images to preview screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => QuizPreviewScreen(
                title: _quizTitleController.text,
                questions: _questions,
                isPreview: true,
                classDetails: widget.classDetails,
              ),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error submitting lesson & quiz: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String? _extractStoragePath(String? publicUrl) {
    if (publicUrl == null || publicUrl.isEmpty) return null;
    const bucketMarker = '/materials/';
    final index = publicUrl.indexOf(bucketMarker);
    if (index == -1) return null;
    return publicUrl.substring(index + bucketMarker.length);
  }

  Future<void> _saveTaskMaterial({required String taskId}) async {
    final storagePath = _uploadedFilePath;
    if (storagePath == null || storagePath.isEmpty) return;

    final title =
        _lessonTitleController.text.trim().isEmpty
            ? 'Lesson Material'
            : _lessonTitleController.text.trim();
    final description = _lessonDescController.text.trim();

    final payload = {
      'task_id': taskId,
      'material_title': title,
      if (description.isNotEmpty) 'description': description,
      'material_file_path': storagePath,
      'material_type': _uploadedFileType ?? 'pdf',
    };

    try {
      await Supabase.instance.client.from('task_materials').insert(payload);
      debugPrint('✅ Saved lesson material to task_materials');
    } catch (e) {
      debugPrint('❌ Failed to save lesson material: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lesson saved, but attaching the material failed.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _createClassMaterialRecord({required String classRoomId}) async {
    if (_uploadedFileUrl == null || _uploadedFileExtension == null) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    final title =
        _lessonTitleController.text.trim().isEmpty
            ? 'Lesson Material'
            : _lessonTitleController.text.trim();
    final description = _lessonDescController.text.trim();

    final payload = {
      'class_room_id': classRoomId,
      'uploaded_by': userId,
      'material_title': title,
      'material_type': _uploadedFileType ?? 'pdf',
      if (description.isNotEmpty) 'description': description,
      'material_file_url': _uploadedFileUrl,
      'file_extension': _uploadedFileExtension,
    };

    try {
      await Supabase.instance.client.from('materials').insert(payload);
      debugPrint('✅ Material synced to class materials list');
    } catch (e) {
      debugPrint('❌ Failed to sync material to class materials: $e');
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(QuizQuestion q, int index) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );
    final primaryMedium = Color.alphaBlend(
      primaryColor.withOpacity(0.3),
      Colors.white,
    );

    final hasQuestionErrors = _questionValidationErrors.containsKey(index);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            hasQuestionErrors
                ? BorderSide(color: Colors.red.withOpacity(0.3), width: 2)
                : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hasQuestionErrors ? Colors.red[100] : primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Question ${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: hasQuestionErrors ? Colors.red[800] : primaryColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (hasQuestionErrors)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[100]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red[700],
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_questionValidationErrors[index]!.length} error(s)',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteQuestion(index),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Question image upload (for fill in the blank with image AND multiple choice with images)
            if (q.type == QuestionType.fillInTheBlankWithImage ||
                q.type == QuestionType.multipleChoiceWithImages) ...[
              _buildQuestionImageUpload(q, index),
              const SizedBox(height: 12),
            ],

            TextField(
              focusNode: _getQuestionFocusNode(index),
              controller: TextEditingController(text: q.questionText),
              decoration: InputDecoration(
                labelText:
                    q.type == QuestionType.multipleChoiceWithImages
                        ? 'Question Text (Optional with image)'
                        : 'Enter your question',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                errorText: _getQuestionError(index, 'questionText'),
                errorStyle: const TextStyle(fontSize: 12),
                alignLabelWithHint: true,
              ),
              maxLines: null, // Allows unlimited lines
              minLines: 1, // Start with 1 line
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: (val) {
                q.questionText = val;
                _clearQuestionError(index, 'questionText');
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: DropdownButton<QuestionType>(
                value: q.type,
                isExpanded: true,
                underline: const SizedBox(),
                items:
                    QuestionType.values
                        .where(
                          (e) =>
                              e != QuestionType.dragAndDrop &&
                              e != QuestionType.audio,
                        )
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              _getQuestionTypeDisplayName(e),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (val) {
                  setState(() {
                    q.type = val!;
                    _initializeQuestionOptions(q, index);
                    q.correctAnswer = null;
                  });
                  // Clear validation errors when type changes
                  _questionValidationErrors.remove(index);
                },
              ),
            ),
            const SizedBox(height: 16),
            _buildQuestionTypeContent(q, index),
          ],
        ),
      ),
    );
  }

  String _getQuestionTypeDisplayName(QuestionType type) {
    switch (type) {
      case QuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuestionType.fillInTheBlank:
        return 'Fill in the Blank';
      case QuestionType.trueFalse:
        return 'True/False';
      case QuestionType.matching:
        return 'Matching';
      case QuestionType.dragAndDrop:
        return 'Drag and Drop';
      case QuestionType.audio:
        return 'Audio';
      case QuestionType.multipleChoiceWithImages:
        return 'Multiple Choice with Images';
      case QuestionType.fillInTheBlankWithImage:
        return 'Fill in the Blank with Image';
    }
  }

  void _initializeQuestionOptions(QuizQuestion q, int questionIndex) {
    if (q.type == QuestionType.trueFalse) {
      q.options = ['True', 'False'];
    } else if (q.type == QuestionType.multipleChoice ||
        q.type == QuestionType.multipleChoiceWithImages) {
      q.options = List.generate(4, (i) => 'Option ${i + 1}');

      // Initialize option images for multiple choice with images
      if (q.type == QuestionType.multipleChoiceWithImages) {
        if (!_optionImages.containsKey(questionIndex)) {
          _optionImages[questionIndex] = {};
        }
        for (int i = 0; i < q.options!.length; i++) {
          _optionImages[questionIndex]![i] = null;
        }
      }
    } else if (q.type == QuestionType.fillInTheBlank ||
        q.type == QuestionType.fillInTheBlankWithImage) {
      q.options = [];
    } else if (q.type == QuestionType.dragAndDrop) {
      q.options = List.generate(4, (i) => 'Item ${i + 1}');
    }
  }

  Widget _buildQuestionImageUpload(QuizQuestion q, int questionIndex) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q.type == QuestionType.multipleChoiceWithImages
              ? 'Question Image (Optional, but recommended):'
              : 'Question Image (Optional):',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final imageUrl = await _pickImage();
            if (imageUrl != null) {
              q.questionImageUrl = imageUrl;
              setState(() {});
            }
          },
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            child:
                (q.questionImageUrl ?? '').isEmpty
                    ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate, color: Colors.grey),
                        const SizedBox(height: 4),
                        Text(
                          q.type == QuestionType.multipleChoiceWithImages
                              ? 'Tap to add question image (optional)'
                              : 'Tap to add question image (optional)',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (q.type == QuestionType.multipleChoiceWithImages)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Students will see this image above the question',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                      ],
                    )
                    : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            q.questionImageUrl!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              icon: const Icon(Icons.delete, size: 16),
                              color: Colors.white,
                              onPressed: () {
                                setState(() {
                                  q.questionImageUrl = null;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionTypeContent(QuizQuestion q, int questionIndex) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    switch (q.type) {
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceContent(q, questionIndex, false);

      case QuestionType.multipleChoiceWithImages:
        return _buildMultipleChoiceContent(q, questionIndex, true);

      case QuestionType.dragAndDrop:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag and drop validation error
            if (_getQuestionError(questionIndex, 'dragDropOptions') != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _getQuestionError(questionIndex, 'dragDropOptions')!,
                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                ),
              ),

            // Correct answer validation for drag and drop
            if (_getQuestionError(questionIndex, 'correctAnswer') != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _getQuestionError(questionIndex, 'correctAnswer')!,
                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                ),
              ),

            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = q.options?.removeAt(oldIndex);
                  if (item != null) q.options?.insert(newIndex, item);
                  // Update correct answer to reflect the new order
                  q.correctAnswer = q.options?.join(',');
                  _clearQuestionError(questionIndex, 'correctAnswer');
                });
              },
              children: [
                for (int i = 0; i < q.options!.length; i++)
                  ListTile(
                    key: ValueKey('${q.options![i]}_$i'),
                    leading: const Icon(Icons.drag_handle, color: Colors.grey),
                    title: TextField(
                      controller: TextEditingController(text: q.options?[i]),
                      decoration: InputDecoration(
                        labelText: 'Item ${i + 1}',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        errorText: _getQuestionError(
                          questionIndex,
                          'dragItem_$i',
                        ),
                        errorStyle: const TextStyle(fontSize: 12),
                        alignLabelWithHint: true,
                      ),
                      maxLines: null, // Allows unlimited lines
                      minLines: 1, // Start with 1 line
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: (val) {
                        q.options?[i] = val;
                        _clearQuestionError(questionIndex, 'dragItem_$i');
                        _clearQuestionError(questionIndex, 'dragDropOptions');
                        // Update correct answer when items change
                        q.correctAnswer = q.options?.join(',');
                        _clearQuestionError(questionIndex, 'correctAnswer');
                      },
                    ),
                    trailing:
                        q.options!.length > 2
                            ? IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  q.options!.removeAt(i);
                                  _clearQuestionError(
                                    questionIndex,
                                    'dragItem_$i',
                                  );
                                  // Update correct answer after removal
                                  q.correctAnswer = q.options?.join(',');
                                  _clearQuestionError(
                                    questionIndex,
                                    'correctAnswer',
                                  );
                                });
                              },
                            )
                            : null,
                  ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _addOption(q, questionIndex),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item'),
                  style: TextButton.styleFrom(foregroundColor: primaryColor),
                ),
                const Spacer(),
                if (q.options!.length > 2)
                  TextButton.icon(
                    onPressed: () {
                      if (q.options!.length > 2) {
                        setState(() {
                          q.options!.removeLast();
                          // Update correct answer after removal
                          q.correctAnswer = q.options?.join(',');
                          _clearQuestionError(questionIndex, 'correctAnswer');
                        });
                      }
                    },
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text('Remove Item'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
            // Instructions for drag and drop
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Drag items to arrange in correct order. The current order is saved as the correct answer.',
                style: TextStyle(fontSize: 12, color: primaryColor),
              ),
            ),
          ],
        );

      case QuestionType.fillInTheBlank:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: TextEditingController(text: q.correctAnswer ?? ''),
              decoration: InputDecoration(
                labelText: 'Correct Answer',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
                errorText: _getQuestionError(questionIndex, 'correctAnswer'),
                errorStyle: const TextStyle(fontSize: 12),
                alignLabelWithHint: true,
              ),
              maxLines: null, // Allows unlimited lines
              minLines: 1, // Start with 1 line
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: (val) {
                q.correctAnswer = val;
                _clearQuestionError(questionIndex, 'correctAnswer');
              },
            ),
          ],
        );

      case QuestionType.fillInTheBlankWithImage:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: TextEditingController(text: q.correctAnswer ?? ''),
              decoration: InputDecoration(
                labelText: 'Correct Answer',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
                errorText: _getQuestionError(questionIndex, 'correctAnswer'),
                errorStyle: const TextStyle(fontSize: 12),
                alignLabelWithHint: true,
              ),
              maxLines: null, // Allows unlimited lines
              minLines: 1, // Start with 1 line
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: (val) {
                q.correctAnswer = val;
                _clearQuestionError(questionIndex, 'correctAnswer');
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Students will see the image above and type their answer in a text box.',
                style: TextStyle(fontSize: 12, color: primaryColor),
              ),
            ),
          ],
        );

      case QuestionType.trueFalse:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select the correct answer:',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            if (_getQuestionError(questionIndex, 'correctAnswer') != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _getQuestionError(questionIndex, 'correctAnswer')!,
                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color:
                      q.correctAnswer == 'True'
                          ? Colors.green!
                          : Colors.grey[300]!,
                ),
              ),
              child: RadioListTile<String>(
                title: const Text('True'),
                value: 'True',
                groupValue: q.correctAnswer,
                onChanged: (val) {
                  setState(() {
                    q.correctAnswer = val;
                    _clearQuestionError(questionIndex, 'correctAnswer');
                  });
                },
              ),
            ),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color:
                      q.correctAnswer == 'False'
                          ? Colors.red!
                          : Colors.grey[300]!,
                ),
              ),
              child: RadioListTile<String>(
                title: const Text('False'),
                value: 'False',
                groupValue: q.correctAnswer,
                onChanged: (val) {
                  setState(() {
                    q.correctAnswer = val;
                    _clearQuestionError(questionIndex, 'correctAnswer');
                  });
                },
              ),
            ),
          ],
        );

      case QuestionType.matching:
        return Column(
          children: [
            if (_getQuestionError(questionIndex, 'matchingPairs') != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _getQuestionError(questionIndex, 'matchingPairs')!,
                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                ),
              ),
            ...List.generate(q.matchingPairs?.length ?? 0, (i) {
              final pair = q.matchingPairs![i];
              final hasLeftError =
                  _getQuestionError(questionIndex, 'leftItem_$i') != null;
              final hasRightError =
                  _getQuestionError(questionIndex, 'rightItem_$i') != null;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  side:
                      (hasLeftError || hasRightError)
                          ? BorderSide(
                            color: Colors.red.withOpacity(0.3),
                            width: 2,
                          )
                          : BorderSide.none,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(
                            text: pair.leftItem,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Left Item (Text)',
                            border: const OutlineInputBorder(),
                            errorText: _getQuestionError(
                              questionIndex,
                              'leftItem_$i',
                            ),
                            errorStyle: const TextStyle(fontSize: 12),
                            alignLabelWithHint: true,
                          ),
                          maxLines: null, // Allows unlimited lines
                          minLines: 1, // Start with 1 line
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          onChanged: (val) {
                            pair.leftItem = val;
                            _clearQuestionError(questionIndex, 'leftItem_$i');
                            _clearQuestionError(questionIndex, 'matchingPairs');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.swap_horiz, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final imageUrl = await _pickImage();
                                if (imageUrl != null) {
                                  setState(() {
                                    pair.rightItemUrl = imageUrl;
                                    _clearQuestionError(
                                      questionIndex,
                                      'rightItem_$i',
                                    );
                                    _clearQuestionError(
                                      questionIndex,
                                      'matchingPairs',
                                    );
                                  });
                                }
                              },
                              child: Container(
                                height: 60,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color:
                                        hasRightError
                                            ? Colors.red!
                                            : Colors.grey,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey[50],
                                ),
                                child:
                                    (pair.rightItemUrl ?? '').isEmpty
                                        ? const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_photo_alternate,
                                              color: Colors.grey,
                                            ),
                                            Text(
                                              'Tap to pick image',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        )
                                        : ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            pair.rightItemUrl!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                              ),
                            ),
                            if (hasRightError)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _getQuestionError(
                                    questionIndex,
                                    'rightItem_$i',
                                  )!,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: () {
                          q.matchingPairs!.removeAt(i);
                          // Clear validation errors for this pair
                          _clearQuestionError(questionIndex, 'leftItem_$i');
                          _clearQuestionError(questionIndex, 'rightItem_$i');
                          _clearQuestionError(questionIndex, 'matchingPairs');
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => _addMatchingPair(q),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Matching Pair'),
              style: TextButton.styleFrom(foregroundColor: primaryColor),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMultipleChoiceContent(
    QuizQuestion q,
    int questionIndex,
    bool withImages,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Options validation error
        if (_getQuestionError(questionIndex, 'options') != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _getQuestionError(questionIndex, 'options')!,
              style: TextStyle(color: Colors.red[700], fontSize: 12),
            ),
          ),

        ...List.generate(q.options!.length, (i) {
          final hasOptionError =
              _getQuestionError(questionIndex, 'option_$i') != null;
          final optionImage = _getOptionImage(questionIndex, i);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color:
                      q.correctAnswer == q.options![i]
                          ? Colors.green!
                          : hasOptionError
                          ? Colors.red!
                          : Colors.grey[300]!,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (withImages) ...[
                      // Option image upload for multiple choice with images
                      GestureDetector(
                        onTap: () async {
                          final imageUrl = await _pickImage();
                          if (imageUrl != null) {
                            _setOptionImage(questionIndex, i, imageUrl);
                            _clearQuestionError(questionIndex, 'option_$i');
                            _clearQuestionError(questionIndex, 'options');
                          }
                        },
                        child: Container(
                          height: 100,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child:
                              (optionImage ?? '').isEmpty
                                  ? const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate,
                                        color: Colors.grey,
                                      ),
                                      Text(
                                        'Tap to add image (optional)',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  )
                                  : Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          optionImage!,
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                          height: double.infinity,
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: CircleAvatar(
                                          radius: 14,
                                          backgroundColor: Colors.black54,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              size: 12,
                                            ),
                                            color: Colors.white,
                                            onPressed: () {
                                              _removeOptionImage(
                                                questionIndex,
                                                i,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Option text field
                    TextField(
                      focusNode: _getOptionFocusNode(questionIndex, i),
                      controller: TextEditingController(text: q.options![i]),
                      decoration: InputDecoration(
                        labelText:
                            withImages
                                ? 'Option ${i + 1} (optional text)'
                                : 'Option ${i + 1}',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        errorText: _getQuestionError(
                          questionIndex,
                          'option_$i',
                        ),
                        errorStyle: const TextStyle(fontSize: 12),
                        alignLabelWithHint: true,
                      ),
                      maxLines: null, // Allows unlimited lines
                      minLines: 1, // Start with 1 line
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: (val) {
                        q.options![i] = val;
                        _clearQuestionError(questionIndex, 'option_$i');
                        // Clear the general options error when user starts typing
                        _clearQuestionError(questionIndex, 'options');
                      },
                    ),
                    const SizedBox(height: 8),

                    // Radio button for correct answer
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select as correct answer:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color:
                                q.correctAnswer == q.options![i]
                                    ? Colors.green[50]
                                    : Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  q.correctAnswer == q.options![i]
                                      ? Colors.green!
                                      : Colors.grey[300]!,
                            ),
                          ),
                          child: Radio<String>(
                            value: q.options![i],
                            groupValue: q.correctAnswer,
                            onChanged: (val) {
                              setState(() {
                                q.correctAnswer = val;
                                _clearQuestionError(
                                  questionIndex,
                                  'correctAnswer',
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        if (_getQuestionError(questionIndex, 'correctAnswer') != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _getQuestionError(questionIndex, 'correctAnswer')!,
              style: TextStyle(color: Colors.red[700], fontSize: 12),
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _addOption(q, questionIndex),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Option'),
              style: TextButton.styleFrom(foregroundColor: primaryColor),
            ),
            const Spacer(),
            if (q.options!.length > 2)
              TextButton.icon(
                onPressed:
                    () =>
                        _deleteOption(q, questionIndex, q.options!.length - 1),
                icon: const Icon(Icons.remove, size: 18),
                label: const Text('Remove Option'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
          ],
        ),

        if (withImages) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Multiple Choice with Images:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Question can have text, image, or both',
                  style: TextStyle(fontSize: 11, color: primaryColor),
                ),
                Text(
                  '• Each option can have text, image, or both',
                  style: TextStyle(fontSize: 11, color: primaryColor),
                ),
                Text(
                  '• At least one must be provided for each option',
                  style: TextStyle(fontSize: 11, color: primaryColor),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );
    final primaryMedium = Color.alphaBlend(
      primaryColor.withOpacity(0.3),
      Colors.white,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Lesson & Quiz'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuestion,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text("Add Question"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Lesson Details Section
            _buildSectionHeader('Lesson Details', Icons.menu_book),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _lessonTitleController,
                      decoration: InputDecoration(
                        labelText: 'Lesson Title',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.title),
                        filled: true,
                        fillColor: Colors.grey[50],
                        errorText: _getFieldError('lessonTitle'),
                        errorStyle: const TextStyle(fontSize: 12),
                      ),
                      onChanged: (_) => _clearFieldError('lessonTitle'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lessonDescController,
                      maxLines: 3,
                      minLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.description),
                        filled: true,
                        fillColor: Colors.grey[50],
                        alignLabelWithHint: true,
                      ),
                      keyboardType: TextInputType.multiline,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lessonTimeController,
                      decoration: InputDecoration(
                        labelText: 'Time Limit (minutes)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.timer),
                        filled: true,
                        fillColor: Colors.grey[50],
                        errorText: _getFieldError('timeLimit'),
                        errorStyle: const TextStyle(fontSize: 12),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _clearFieldError('timeLimit'),
                    ),
                    // const SizedBox(height: 12),
                    // Container(
                    //   padding: const EdgeInsets.all(12),
                    //   decoration: BoxDecoration(
                    //     color: Colors.grey[50],
                    //     borderRadius: BorderRadius.circular(8),
                    //     border: Border.all(color: Colors.grey[300]!),
                    //   ),
                    //   child: SwitchListTile(
                    //     title: const Text(
                    //       'Unlocks Next Level',
                    //       style: TextStyle(fontWeight: FontWeight.w500),
                    //     ),
                    //     subtitle: const Text(
                    //       'Enable to allow progression to next level',
                    //     ),
                    //     value: _unlocksNextLevel,
                    //     onChanged:
                    //         (val) => setState(() => _unlocksNextLevel = val),
                    //     contentPadding: EdgeInsets.zero,
                    //   ),
                    // ),
                  ],
                ),
              ),
            ),

            // File Upload Section - Now Required
            const SizedBox(height: 20),
            _buildSectionHeader('Lesson Material *', Icons.attach_file),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text(
                        'Upload File (Image, PDF, Video, Audio)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryLight,
                        foregroundColor: primaryColor,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFilePreview(),
                    if (_getFieldError('lessonMaterial') != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _getFieldError('lessonMaterial')!,
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Quiz Details Section
            const SizedBox(height: 20),
            _buildSectionHeader('Quiz Details', Icons.quiz),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _quizTitleController,
                      decoration: InputDecoration(
                        labelText: 'Quiz Title',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.quiz),
                        filled: true,
                        fillColor: Colors.grey[50],
                        errorText: _getFieldError('quizTitle'),
                        errorStyle: const TextStyle(fontSize: 12),
                      ),
                      onChanged: (_) => _clearFieldError('quizTitle'),
                    ),
                    const SizedBox(height: 16),
                    if (_questions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                _getFieldError('questions') != null
                                    ? Colors.red!
                                    : Colors.grey[300]!,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.help_outline,
                              size: 48,
                              color:
                                  _getFieldError('questions') != null
                                      ? Colors.red
                                      : Colors.grey,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No questions added yet',
                              style: TextStyle(
                                color:
                                    _getFieldError('questions') != null
                                        ? Colors.red
                                        : Colors.grey,
                              ),
                            ),
                            Text(
                              'Use the + button below to add questions',
                              style: TextStyle(
                                color:
                                    _getFieldError('questions') != null
                                        ? Colors.red
                                        : Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            if (_getFieldError('questions') != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _getFieldError('questions')!,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(_questions.length, (index) {
                        return _buildQuestionCard(_questions[index], index);
                      }),
                  ],
                ),
              ),
            ),

            // Submit Button
            const SizedBox(height: 24),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitLessonAndQuiz,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child:
                    _isLoading
                        ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Saving Lesson & Quiz...'),
                          ],
                        )
                        : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save),
                            SizedBox(width: 8),
                            Text(
                              'Save Lesson & Quiz',
                              style: TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Dispose all focus nodes
    for (var node in _questionFocusNodes.values) {
      node.dispose();
    }
    for (var questionMap in _optionFocusNodes.values) {
      for (var node in questionMap.values) {
        node.dispose();
      }
    }
    _lessonTitleController.dispose();
    _lessonDescController.dispose();
    _lessonTimeController.dispose();
    _quizTitleController.dispose();
    super.dispose();
  }
}

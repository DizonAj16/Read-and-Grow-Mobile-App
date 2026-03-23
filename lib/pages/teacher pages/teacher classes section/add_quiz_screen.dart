import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../api/supabase_api_service.dart';
import '../../../../models/quiz_questions.dart';
import '../../../../utils/file_validator.dart';

class AddQuizScreen extends StatefulWidget {
  final String? lessonId;
  final String? classRoomId;
  final String? quizId; // For editing mode
  final Map<String, dynamic>? initialQuizData; // For editing mode

  const AddQuizScreen({
    super.key,
    this.lessonId,
    this.classRoomId,
    this.quizId,
    this.initialQuizData,
  });

  @override
  State<AddQuizScreen> createState() => _AddQuizScreenState();
}

class _AddQuizScreenState extends State<AddQuizScreen> {
  final _quizTitleController = TextEditingController();
  List<QuizQuestion> _questions = [];
  bool _isLoading = false;
  bool _isLoadingData = false;
  String? _selectedLessonId;

  // Track option images for multiple choice with pictures
  final Map<int, Map<int, String?>> _optionImages = {};

  // Track question images for fill in the blank with image
  final Map<int, String?> _questionImages = {};

  bool get _isEditMode => widget.quizId != null;

  @override
  void initState() {
    super.initState();
    _selectedLessonId = widget.lessonId;
    if (_isEditMode && widget.initialQuizData != null) {
      _loadQuizData();
    }
  }

Future<void> _loadQuizData() async {
  if (widget.initialQuizData == null) return;

  setState(() => _isLoadingData = true);

  try {
    final quiz = widget.initialQuizData!['quiz'] as Map<String, dynamic>?;
    final questions = widget.initialQuizData!['questions'];

    if (quiz != null) {
      _quizTitleController.text = quiz['title']?.toString() ?? '';
    }

    if (questions != null && questions is List) {
      // Check if questions are already QuizQuestion objects or raw data
      if (questions.isNotEmpty && questions.first is QuizQuestion) {
        // Already QuizQuestion objects - just use them directly
        _questions = List<QuizQuestion>.from(questions);
        
        // Load option images for multiple choice with images
        for (int i = 0; i < _questions.length; i++) {
          final q = _questions[i];
          
          // Load option images
          if (q.type == QuestionType.multipleChoiceWithImages && 
              q.optionImages != null) {
            final optionImagesMap = q.optionImages!;
            _optionImages[i] = {};
            
            for (var entry in optionImagesMap.entries) {
              final optIndex = int.tryParse(entry.key);
              if (optIndex != null && optIndex < (q.options?.length ?? 0)) {
                _optionImages[i]![optIndex] = entry.value;
              }
            }
          }
          
          // Load question image
          if ((q.type == QuestionType.fillInTheBlankWithImage || 
               q.type == QuestionType.multipleChoiceWithImages) && 
              q.questionImageUrl != null) {
            _questionImages[i] = q.questionImageUrl;
          }
        }
      } else {
        // Raw data - need to convert using QuizQuestion.fromMap
        _questions = questions.map<QuizQuestion>((q) {
          final question = QuizQuestion.fromMap(q is Map<String, dynamic> ? q : {});
          
          // Load option images for multiple choice with images
          if (question.type == QuestionType.multipleChoiceWithImages && 
              question.optionImages != null) {
            final optionImagesMap = question.optionImages!;
            final questionIndex = questions.indexOf(q);
            _optionImages[questionIndex] = {};
            
            for (var entry in optionImagesMap.entries) {
              final optIndex = int.tryParse(entry.key);
              if (optIndex != null) {
                _optionImages[questionIndex]![optIndex] = entry.value;
              }
            }
          }
          
          // Load question image
          if ((question.type == QuestionType.fillInTheBlankWithImage || 
               question.type == QuestionType.multipleChoiceWithImages) && 
              question.questionImageUrl != null) {
            final questionIndex = questions.indexOf(q);
            _questionImages[questionIndex] = question.questionImageUrl;
          }
          
          return question;
        }).toList();
      }
    }
    
    debugPrint("✅ Total questions loaded: ${_questions.length}");
  } catch (e) {
    debugPrint('❌ Error loading quiz data: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading quiz: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isLoadingData = false);
    }
  }
}

  void _addQuestion() {
    final defaultOptions = List.generate(4, (i) => 'Option ${i + 1}');
    _questions.add(
      QuizQuestion(
        questionText: '',
        type: QuestionType.multipleChoice,
        options: defaultOptions,
        matchingPairs: [],
      ),
    );
    setState(() {});
  }

void _deleteQuestion(int index) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Question'),
      content: const Text('Are you sure you want to delete this question?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _questions.removeAt(index);
            // Remove associated images
            _optionImages.remove(index);
            _questionImages.remove(index);
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Question deleted'),
                backgroundColor: Colors.red,
              ),
            );
          },
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

  void _addOption(QuizQuestion question, int questionIndex) {
    final newIndex = (question.options?.length ?? 0) + 1;
    question.options?.add('Option $newIndex');
    
    // Initialize option image for multiple choice with images
    if (question.type == QuestionType.multipleChoiceWithImages) {
      if (!_optionImages.containsKey(questionIndex)) {
        _optionImages[questionIndex] = {};
      }
      _optionImages[questionIndex]![question.options!.length - 1] = null;
    }
    
    setState(() {});
  }

  void _deleteOption(QuizQuestion question, int questionIndex, int optionIndex) {
    if (question.options != null && question.options!.length > 2) {
      // Don't allow deletion if it would leave less than 2 options
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Option'),
          content: const Text('Are you sure you want to delete this option?'),
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
                  for (int i = optionIndex + 1; i < _optionImages[questionIndex]!.length + 1; i++) {
                    final image = _optionImages[questionIndex]![i];
                    if (image != null) {
                      _optionImages[questionIndex]![i - 1] = image;
                    }
                  }
                  _optionImages[questionIndex]!.remove(_optionImages[questionIndex]!.length);
                }
                
                // If the deleted option was the correct answer, clear it
                if (question.correctAnswer == question.options?[optionIndex]) {
                  question.correctAnswer = null;
                }
                setState(() {});
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
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

  void _deleteMatchingPair(QuizQuestion question, int pairIndex) {
    if (question.matchingPairs != null) {
      question.matchingPairs!.removeAt(pairIndex);
      setState(() {});
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

  Future<void> _submitQuiz() async {
    if (_quizTitleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a quiz title'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one question'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

// Validate all questions have text
for (int i = 0; i < _questions.length; i++) {
  final q = _questions[i];
  if (q.questionText.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Question ${i + 1} cannot be empty'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  // Validate multiple choice with images
  if (q.type == QuestionType.multipleChoiceWithImages && q.options != null) {
    for (int j = 0; j < q.options!.length; j++) {
      final hasText = q.options![j].trim().isNotEmpty;
      final hasImage = _getOptionImage(i, j) != null;
      if (!hasText && !hasImage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question ${i + 1}, Option ${j + 1} needs either text or image'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
  }

      // Validate correct answer selection
      if ((q.type == QuestionType.multipleChoice || 
           q.type == QuestionType.multipleChoiceWithImages ||
           q.type == QuestionType.trueFalse) &&
          (q.correctAnswer == null || q.correctAnswer!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question ${i + 1}: Please select a correct answer'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Validate fill in the blank answers
      if ((q.type == QuestionType.fillInTheBlank || 
           q.type == QuestionType.fillInTheBlankWithImage) &&
          (q.correctAnswer == null || q.correctAnswer!.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question ${i + 1}: Please provide a correct answer'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!_isEditMode && _selectedLessonId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a lesson')),
      );
      return;
    }

    final classRoomId = widget.classRoomId;
    if (!_isEditMode && (classRoomId == null || classRoomId.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing class information. Please reopen this screen.'),
        ),
      );
      return;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
bool success;
if (_isEditMode) {
  // Update existing quiz
  success = await ApiService.updateQuiz(
    quizId: widget.quizId!,
    title: _quizTitleController.text,
    questions: _questions,
    optionImages: _optionImages,
    questionImages: _questionImages, // Add this line
  );
} else {
  // Create new quiz
  final quiz = await ApiService.addQuiz(
    taskId: _selectedLessonId!,
    title: _quizTitleController.text,
    questions: _questions,
    classRoomId: classRoomId!,
    optionImages: _optionImages,
    questionImages: _questionImages, // Add this line
  );
  success = quiz != null;
}

      if (mounted) {
        setState(() => _isLoading = false);
      }

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEditMode
                    ? 'Quiz updated successfully!'
                    : 'Quiz added successfully!',
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Return true to indicate success
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEditMode ? 'Failed to update quiz' : 'Failed to add quiz',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

Widget _buildQuestionCard(QuizQuestion q, int index) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${index + 1}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              if (_isEditMode)
                IconButton(
                  icon: Icon(Icons.delete, color: colorScheme.error),
                  onPressed: () => _deleteQuestion(index),
                  tooltip: 'Delete question',
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
            controller: q.textController ?? TextEditingController(text: q.questionText),
            decoration: InputDecoration(
              labelText: 'Question Text',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            maxLines: 3,
            onChanged: (val) => q.questionText = val,
          ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
              ),
              child: DropdownButton<QuestionType>(
                value: q.type,
                isExpanded: true,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(8),
                items: QuestionType.values.where((type) => 
                  type != QuestionType.audio // Exclude audio type for now
                ).map((e) {
                  return DropdownMenuItem(
                    value: e,
                    child: Row(
                      children: [
                        Icon(_getQuestionTypeIcon(e), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _getQuestionTypeName(e),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      q.type = val;
                      _initializeQuestionOptions(q, index);
                      q.correctAnswer = null;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 16),

            // Build the appropriate content based on question type
            _buildQuestionTypeContent(q, index),
          ],
        ),
      ),
    );
  }

Widget _buildQuestionImageUpload(QuizQuestion q, int questionIndex) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  String label = 'Question Image (Optional):';
  String description = '';
  
  if (q.type == QuestionType.fillInTheBlankWithImage) {
    description = 'Students will see this image and type their answer.';
  } else if (q.type == QuestionType.multipleChoiceWithImages) {
    description = 'This image will be displayed above the multiple choice options.';
  }
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
      ),
      if (description.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () async {
          final imageUrl = await _pickImage();
          if (imageUrl != null) {
            setState(() {
              q.questionImageUrl = imageUrl;
              _questionImages[questionIndex] = imageUrl;
            });
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
          child: (q.questionImageUrl ?? '').isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate, color: Colors.grey),
                    Text('Tap to add question image (optional)',
                        style: TextStyle(fontSize: 12)),
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
                              _questionImages.remove(questionIndex);
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
      
      // Clear any existing question image when switching to this type
      q.questionImageUrl = null;
      _questionImages.remove(questionIndex);
    }
  } else if (q.type == QuestionType.fillInTheBlank ||
             q.type == QuestionType.fillInTheBlankWithImage) {
    q.options = [];
  } else if (q.type == QuestionType.dragAndDrop) {
    q.options = List.generate(3, (i) => 'Item ${i + 1}');
  }
  
  // Clear correct answer when changing question type
  q.correctAnswer = null;
}

  Widget _buildQuestionTypeContent(QuizQuestion q, int questionIndex) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    switch (q.type) {
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceContent(q, questionIndex, false);
        
      case QuestionType.multipleChoiceWithImages:
        return _buildMultipleChoiceContent(q, questionIndex, true);

      case QuestionType.dragAndDrop:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Items (Drag to reorder)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = q.options?.removeAt(oldIndex);
                  if (item != null) q.options?.insert(newIndex, item);
                });
              },
              children: [
                for (int i = 0; i < (q.options?.length ?? 0); i++)
                  Card(
                    key: ValueKey('${q.options![i]}_$i'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle),
                      title: TextField(
                        controller: TextEditingController(text: q.options?[i] ?? ''),
                        decoration: InputDecoration(
                          labelText: 'Item ${i + 1}',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => q.options?[i] = val,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _deleteOption(q, questionIndex, i),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _addOption(q, questionIndex),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Item'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.surfaceVariant,
                foregroundColor: colorScheme.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );

      case QuestionType.fillInTheBlank:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correct Answer',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: TextEditingController(text: q.correctAnswer ?? ''),
              decoration: InputDecoration(
                labelText: 'Enter the correct answer',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                hintText: 'The correct answer goes here...',
              ),
              onChanged: (val) => q.correctAnswer = val,
            ),
          ],
        );

      case QuestionType.fillInTheBlankWithImage:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correct Answer',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: TextEditingController(text: q.correctAnswer ?? ''),
              decoration: InputDecoration(
                labelText: 'Enter the correct answer for the image',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                hintText: 'What is shown in the image?',
              ),
              onChanged: (val) => q.correctAnswer = val,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Students will see the image above and type their answer in a text box.',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        );

      case QuestionType.trueFalse:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select the correct answer:',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('True'),
                    value: 'True',
                    groupValue: q.correctAnswer,
                    onChanged: (val) {
                      setState(() {
                        q.correctAnswer = val;
                      });
                    },
                    tileColor: colorScheme.surfaceVariant.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  RadioListTile<String>(
                    title: const Text('False'),
                    value: 'False',
                    groupValue: q.correctAnswer,
                    onChanged: (val) {
                      setState(() {
                        q.correctAnswer = val;
                      });
                    },
                    tileColor: colorScheme.surfaceVariant.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case QuestionType.matching:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Matching Pairs',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...List.generate(q.matchingPairs?.length ?? 0, (i) {
              final pair = q.matchingPairs![i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: pair.leftItem),
                          decoration: InputDecoration(
                            labelText: 'Left Item (Text)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (val) => pair.leftItem = val,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picker = ImagePicker();
                            final pickedFile = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80,
                            );
                            if (pickedFile != null) {
                              File file = File(pickedFile.path);
                              String? uploadedUrl = await ApiService.uploadFile(file);
                              if (uploadedUrl != null) {
                                setState(() {
                                  pair.rightItemUrl = uploadedUrl;
                                });
                              }
                            }
                          },
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.grey,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: colorScheme.surfaceVariant.withOpacity(0.3),
                            ),
                            child: (pair.rightItemUrl ?? '').isEmpty
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate,
                                        size: 40,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap to add image',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      pair.rightItemUrl!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete, color: colorScheme.error),
                        onPressed: () => _deleteMatchingPair(q, i),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _addMatchingPair(q),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Matching Pair'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.surfaceVariant,
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      default:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'This question type is not yet supported in the editor.',
            style: TextStyle(color: Colors.orange.shade800),
          ),
        );
    }
  }

  Widget _buildMultipleChoiceContent(QuizQuestion q, int questionIndex, bool withImages) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Options',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(q.options?.length ?? 0, (i) {
          final optionImage = _getOptionImage(questionIndex, i);
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: q.correctAnswer == q.options![i]
                      ? colorScheme.primary
                      : colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (withImages) ...[
                      // Option image upload for multiple choice with images
                      GestureDetector(
                        onTap: () async {
                          final imageUrl = await _pickImage();
                          if (imageUrl != null) {
                            _setOptionImage(questionIndex, i, imageUrl);
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
                          child: (optionImage ?? '').isEmpty
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate, color: Colors.grey),
                                    Text('Tap to add image (optional)',
                                        style: TextStyle(fontSize: 12)),
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
                                          icon: const Icon(Icons.delete, size: 12),
                                          color: Colors.white,
                                          onPressed: () {
                                            _removeOptionImage(questionIndex, i);
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
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(text: q.options![i]),
                            decoration: InputDecoration(
                              labelText: withImages 
                                  ? 'Option ${i + 1} (optional text)' 
                                  : 'Option ${i + 1}',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceVariant.withOpacity(0.1),
                            ),
                            onChanged: (val) => q.options![i] = val,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Radio<String>(
                          value: q.options![i],
                          groupValue: q.correctAnswer,
                          onChanged: (val) {
                            setState(() {
                              q.correctAnswer = val;
                            });
                          },
                        ),
                        if (q.options!.length > 2)
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            onPressed: () => _deleteOption(q, questionIndex, i),
                            tooltip: 'Delete option',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _addOption(q, questionIndex),
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add Option'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.surfaceVariant,
            foregroundColor: colorScheme.onSurfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        
        if (withImages) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Each option can have either text, image, or both. At least one must be provided.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  IconData _getQuestionTypeIcon(QuestionType type) {
    switch (type) {
      case QuestionType.multipleChoice:
        return Icons.checklist;
      case QuestionType.multipleChoiceWithImages:
        return Icons.photo_library;
      case QuestionType.trueFalse:
        return Icons.check_circle;
      case QuestionType.fillInTheBlank:
        return Icons.short_text;
      case QuestionType.fillInTheBlankWithImage:
        return Icons.image;
      case QuestionType.dragAndDrop:
        return Icons.drag_handle;
      case QuestionType.matching:
        return Icons.compare_arrows;
      case QuestionType.audio:
        return Icons.audiotrack;
    }
  }

  String _getQuestionTypeName(QuestionType type) {
    switch (type) {
      case QuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuestionType.multipleChoiceWithImages:
        return 'Multiple Choice with Images';
      case QuestionType.trueFalse:
        return 'True/False';
      case QuestionType.fillInTheBlank:
        return 'Fill in the Blank';
      case QuestionType.fillInTheBlankWithImage:
        return 'Fill in the Blank with Image';
      case QuestionType.dragAndDrop:
        return 'Drag and Drop';
      case QuestionType.matching:
        return 'Matching';
      case QuestionType.audio:
        return 'Audio';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Quiz' : 'Add Quiz'),
          backgroundColor: colorScheme.surface,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading quiz data...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Quiz' : 'Create New Quiz'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          if (_questions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text('${_questions.length} question${_questions.length == 1 ? '' : 's'}'),
                backgroundColor: colorScheme.primary.withOpacity(0.1),
                labelStyle: TextStyle(color: colorScheme.primary),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Quiz Title
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quiz Title',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _quizTitleController,
                      decoration: InputDecoration(
                        hintText: 'Enter quiz title...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      ),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Lesson Selector (only for new quizzes)
            if (!_isEditMode && widget.lessonId == null)
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Lesson',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: ApiService.getLessons(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'No lessons found. Please add a lesson first.',
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          final lessons = snapshot.data!;
                          return DropdownButtonFormField<String>(
                            value: _selectedLessonId,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                            ),
                            hint: const Text("Select a lesson"),
                            items: lessons.map((lesson) {
                              return DropdownMenuItem<String>(
                                value: lesson['id'].toString(),
                                child: Text(
                                  lesson['title']?.toString() ?? 'Untitled Lesson',
                                ),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedLessonId = val),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (!_isEditMode && widget.lessonId == null) const SizedBox(height: 16),

            // Questions Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Questions',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _addQuestion,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Question'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Questions List
            Expanded(
              child: _questions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.quiz,
                            size: 80,
                            color: colorScheme.onSurface.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No questions added yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Click "Add Question" to start',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _questions.length,
                      itemBuilder: (context, index) => _buildQuestionCard(_questions[index], index),
                    ),
            ),

            // Save Button
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(top: BorderSide(color: colorScheme.outline.withOpacity(0.1))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitQuiz,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(_isEditMode ? Icons.save : Icons.add),
                                const SizedBox(width: 8),
                                Text(
                                  _isEditMode ? 'Update Quiz' : 'Save Quiz',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onPrimary,
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
    );
  }
}
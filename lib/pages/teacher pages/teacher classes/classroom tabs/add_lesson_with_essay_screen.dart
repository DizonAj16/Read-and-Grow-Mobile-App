import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../api/supabase_api_service.dart';
import '../../../../utils/file_validator.dart';

class AddLessonWithEssayScreen extends StatefulWidget {
  final String? readingLevelId;
  final Map<String, dynamic> classDetails;

  const AddLessonWithEssayScreen({
    super.key,
    this.readingLevelId,
    required this.classDetails,
  });

  @override
  State<AddLessonWithEssayScreen> createState() => _AddLessonWithEssayScreenState();
}

class _AddLessonWithEssayScreenState extends State<AddLessonWithEssayScreen> {
  // Lesson controllers
  final _lessonTitleController = TextEditingController();
  final _lessonDescController = TextEditingController();
  // final _lessonTimeController = TextEditingController();
  bool _unlocksNextLevel = false;

  // Essay controllers
  final _essayTitleController = TextEditingController();
  final List<EssayQuestion> _essayQuestions = [];

  bool _isLoading = false;
  String? _uploadedFileUrl;
  String? _uploadedFilePath;
  String? _uploadedFileType;
  String? _uploadedFileExtension;

  // Validation
  final Map<String, String> _validationErrors = {};
  final Map<int, Map<String, String>> _questionValidationErrors = {};

  // Track focus nodes
  final Map<int, FocusNode> _questionFocusNodes = {};

  FocusNode _getQuestionFocusNode(int index) {
    if (!_questionFocusNodes.containsKey(index)) {
      _questionFocusNodes[index] = FocusNode();
    }
    return _questionFocusNodes[index]!;
  }

  void _addEssayQuestion() {
    final newQuestion = EssayQuestion(
      questionText: '',
      wordLimit: 250, // Default word limit
      questionImageUrl: null,
    );
    _essayQuestions.add(newQuestion);
    setState(() {});
  }

  void _deleteEssayQuestion(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Essay Question'),
        content: const Text('Are you sure you want to delete this essay question?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _questionFocusNodes.remove(index);
              _essayQuestions.removeAt(index);
              _questionValidationErrors.remove(index);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Essay question deleted'),
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

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'mp4', 'mp3', 'wav', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      
      // Front-end validation
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
        return;
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
        return null;
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

  bool _validateForm() {
    _validationErrors.clear();
    _questionValidationErrors.clear();

    // Validate lesson title
    if (_lessonTitleController.text.trim().isEmpty) {
      _validationErrors['lessonTitle'] = 'Lesson title is required';
    }

    // Validate essay title
    if (_essayTitleController.text.trim().isEmpty) {
      _validationErrors['essayTitle'] = 'Essay title is required';
    }

    // // Validate time limit
    // if (_lessonTimeController.text.trim().isEmpty) {
    //   _validationErrors['timeLimit'] = 'Time limit is required';
    // } else {
    //   final timeLimit = int.tryParse(_lessonTimeController.text.trim());
    //   if (timeLimit == null || timeLimit <= 0) {
    //     _validationErrors['timeLimit'] = 'Please enter a valid time limit';
    //   }
    // }

    // Validate lesson material
    if (_uploadedFileUrl == null) {
      _validationErrors['lessonMaterial'] = 'Lesson material is required';
    }

    // Validate essay questions
    if (_essayQuestions.isEmpty) {
      _validationErrors['questions'] = 'At least one essay question is required';
    } else {
      for (int i = 0; i < _essayQuestions.length; i++) {
        final question = _essayQuestions[i];
        final questionErrors = <String, String>{};

        // Validate question text (unless there's an image)
        if (question.questionText.trim().isEmpty &&
            question.questionImageUrl == null) {
          questionErrors['questionText'] = 'Essay question needs text or image';
        }

        // Validate word limit
        if (question.wordLimit != null && question.wordLimit! <= 0) {
          questionErrors['wordLimit'] = 'Word limit must be positive';
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

  Future<void> _submitLessonAndEssay() async {
    if (!_validateForm()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
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

    setState(() => _isLoading = true);

    try {
      final readingLevelId = widget.readingLevelId ?? widget.classDetails['reading_level_id'];

      // 1️⃣ Add Lesson
      debugPrint('Adding lesson for essay...');
      final lesson = await ApiService.addLesson(
        readingLevelId: readingLevelId,
        classRoomId: widget.classDetails['id'] as String,
        title: _lessonTitleController.text,
        description: _lessonDescController.text,
        // timeLimitMinutes: int.tryParse(_lessonTimeController.text),
        unlocksNextLevel: _unlocksNextLevel,
      );

      if (lesson == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add lesson')),
        );
        return;
      }

      debugPrint('Lesson added: ${lesson['id']}');

      // 2️⃣ Determine teacherId
      String? teacherId = widget.classDetails['teacher_id'];
      if (teacherId == null) {
        final teacherData = await Supabase.instance.client
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

      // 3️⃣ Insert assignment row
      final assignmentRes = await Supabase.instance.client
          .from('assignments')
          .insert({
            'class_room_id': widget.classDetails['id'],
            'task_id': lesson['id'],
            'teacher_id': teacherId,
            'assignment_type': 'essay', // Mark as essay assignment
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

      // 5️⃣ Add Essay Assignment
      debugPrint('Adding essay assignment...');
      final essay = await ApiService.addEssayAssignment(
        taskId: lesson['id'],
        title: _essayTitleController.text,
        questions: _essayQuestions,
        classRoomId: widget.classDetails['id'] as String,
        assignmentId: assignmentId,
      );

      if (essay == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add essay assignment')),
        );
        return;
      }

      debugPrint('Essay assignment created successfully');

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lesson & Essay added successfully!')),
      );

      // Navigate back
      Navigator.pop(context);
      
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error submitting lesson & essay: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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

    final title = _lessonTitleController.text.trim().isEmpty
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

    final title = _lessonTitleController.text.trim().isEmpty
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

  Widget _buildEssayQuestionCard(EssayQuestion q, int index) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    final hasQuestionErrors = _questionValidationErrors.containsKey(index);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasQuestionErrors
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasQuestionErrors ? Colors.red[100] : primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Essay Question ${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: hasQuestionErrors ? Colors.red[800] : primaryColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (hasQuestionErrors)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  onPressed: () => _deleteEssayQuestion(index),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Question image upload
            _buildQuestionImageUpload(q, index),
            const SizedBox(height: 12),

            // Question text
            TextField(
              focusNode: _getQuestionFocusNode(index),
              controller: TextEditingController(text: q.questionText),
              decoration: InputDecoration(
                labelText: 'Essay Question (Text or Image required)',
                hintText: 'Enter the essay prompt or question...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[50],
                errorText: _getQuestionError(index, 'questionText'),
                errorStyle: const TextStyle(fontSize: 12),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              minLines: 2,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: (val) {
                q.questionText = val;
                _clearQuestionError(index, 'questionText');
              },
            ),
            const SizedBox(height: 12),

            // Word limit
            TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Word Limit (optional)',
                hintText: 'e.g., 250 (leave empty for unlimited)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[50],
                errorText: _getQuestionError(index, 'wordLimit'),
                errorStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.text_fields),
              ),
              onChanged: (val) {
                q.wordLimit = val.isEmpty ? null : int.tryParse(val);
                _clearQuestionError(index, 'wordLimit');
              },
            ),
            const SizedBox(height: 12),

            // Instructions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Essay Question Information',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Students will write their response in a text box\n'
                    '• You can add an image prompt (optional)\n'
                    '• Word limit is optional\n'
                    '• You will manually grade these responses later',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
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

  Widget _buildQuestionImageUpload(EssayQuestion q, int questionIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Question Image (Optional, but recommended):',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700]),
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
            child: (q.questionImageUrl ?? '').isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, color: Colors.grey),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to add image prompt (optional)',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Students will see this image above the essay prompt',
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

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Lesson & Essay'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEssayQuestion,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text("Add Essay Question"),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _lessonTitleController,
                      decoration: InputDecoration(
                        labelText: 'Lesson Title',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.description),
                        filled: true,
                        fillColor: Colors.grey[50],
                        alignLabelWithHint: true,
                      ),
                      keyboardType: TextInputType.multiline,
                    ),
                    // const SizedBox(height: 12),
                    // TextField(
                    //   controller: _lessonTimeController,
                    //   decoration: InputDecoration(
                    //     labelText: 'Time Limit (minutes)',
                    //     border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    //     prefixIcon: const Icon(Icons.timer),
                    //     filled: true,
                    //     fillColor: Colors.grey[50],
                    //     errorText: _getFieldError('timeLimit'),
                    //     errorStyle: const TextStyle(fontSize: 12),
                    //   ),
                    //   keyboardType: TextInputType.number,
                    //   onChanged: (_) => _clearFieldError('timeLimit'),
                    // ),
                    const SizedBox(height: 12),
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
                    //     subtitle: const Text('Enable to allow progression to next level'),
                    //     value: _unlocksNextLevel,
                    //     onChanged: (val) => setState(() => _unlocksNextLevel = val),
                    //     contentPadding: EdgeInsets.zero,
                    //   ),
                    // ),
                  ],
                ),
              ),
            ),

            // File Upload Section
            const SizedBox(height: 20),
            _buildSectionHeader('Lesson Material *', Icons.attach_file),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Upload File (Image, PDF, Video, Audio)'),
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

            // Essay Details Section
            const SizedBox(height: 20),
            _buildSectionHeader('Essay Assignment', Icons.assignment),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _essayTitleController,
                      decoration: InputDecoration(
                        labelText: 'Essay Assignment Title',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.assignment),
                        filled: true,
                        fillColor: Colors.grey[50],
                        errorText: _getFieldError('essayTitle'),
                        errorStyle: const TextStyle(fontSize: 12),
                      ),
                      onChanged: (_) => _clearFieldError('essayTitle'),
                    ),
                    const SizedBox(height: 16),
                    if (_essayQuestions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getFieldError('questions') != null
                                ? Colors.red!
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.assignment_outlined,
                              size: 48,
                              color: _getFieldError('questions') != null
                                  ? Colors.red
                                  : Colors.grey,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No essay questions added yet',
                              style: TextStyle(
                                color: _getFieldError('questions') != null
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                            ),
                            Text(
                              'Use the + button below to add essay questions',
                              style: TextStyle(
                                color: _getFieldError('questions') != null
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
                      ...List.generate(_essayQuestions.length, (index) {
                        return _buildEssayQuestionCard(_essayQuestions[index], index);
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
                onPressed: _isLoading ? null : _submitLessonAndEssay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Saving Lesson & Essay...'),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save),
                          SizedBox(width: 8),
                          Text(
                            'Save Lesson & Essay',
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
    for (var node in _questionFocusNodes.values) {
      node.dispose();
    }
    _lessonTitleController.dispose();
    _lessonDescController.dispose();
    // _lessonTimeController.dispose();
    _essayTitleController.dispose();
    super.dispose();
  }
}

// Essay Question Model
class EssayQuestion {
  String id;
  String questionText;
  String? questionImageUrl;
  int? wordLimit;
  String? teacherFeedback;
  double? teacherScore;
  bool isGraded;
  String userAnswer;

  EssayQuestion({
    this.id = '',
    required this.questionText,
    this.questionImageUrl,
    this.wordLimit,
    this.teacherFeedback,
    this.teacherScore,
    this.isGraded = false,
    this.userAnswer = '',
  });

  factory EssayQuestion.fromMap(Map<String, dynamic> map) {
    return EssayQuestion(
      id: map['id']?.toString() ?? '',
      questionText: map['question_text']?.toString() ?? '',
      questionImageUrl: map['question_image_url']?.toString(),
      wordLimit: map['word_limit'] as int?,
      teacherFeedback: map['teacher_feedback']?.toString(),
      teacherScore: map['teacher_score'] as double?,
      isGraded: map['is_graded'] as bool? ?? false,
      userAnswer: map['user_answer']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question_text': questionText,
      'question_image_url': questionImageUrl,
      'word_limit': wordLimit,
      'teacher_feedback': teacherFeedback,
      'teacher_score': teacherScore,
      'is_graded': isGraded,
      'user_answer': userAnswer,
    };
  }
}
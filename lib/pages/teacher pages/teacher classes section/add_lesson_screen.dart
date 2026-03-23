import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../api/supabase_api_service.dart';
import 'add_quiz_screen.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../../utils/file_validator.dart';

class AddLessonScreen extends StatefulWidget {
  final String? readingLevelId;
  final String classRoomId;
  const AddLessonScreen({
    super.key,
    this.readingLevelId,
    required this.classRoomId,
  });

  @override
  State<AddLessonScreen> createState() => _AddLessonScreenState();
}

class _AddLessonScreenState extends State<AddLessonScreen> {
  final _lessonTitleController = TextEditingController();
  final _lessonDescController = TextEditingController();
  final _lessonTimeController = TextEditingController();
  bool _unlocksNextLevel = false;
  bool _isLoading = false;

  String? _uploadedFileUrl;
  String? _uploadedFilePath;
  String? _uploadedFileType;
  String? _uploadedFileExtension;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'mp4', 'mp3', 'wav', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      
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

      String fileExtension = file.path.split('.').last.toLowerCase();

      String? uploadedUrl = await ApiService.uploadFile(file);
      
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

  Future<void> _submitLesson() async {
    if (_lessonTitleController.text.isEmpty) return;

    setState(() => _isLoading = true);

    final lesson = await ApiService.addLesson(
      readingLevelId: widget.readingLevelId,
      classRoomId: widget.classRoomId,
      title: _lessonTitleController.text,
      description: _lessonDescController.text,
      timeLimitMinutes: int.tryParse(_lessonTimeController.text),
      unlocksNextLevel: _unlocksNextLevel,
    );

    if (lesson == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to add lesson')));
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    final teacher = await Supabase.instance.client
        .from('teachers')
        .select('id')
        .eq('id', userId!)
        .maybeSingle();

    if (teacher == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teacher record not found')),
      );
      return;
    }

    final teacherId = teacher['id'];

    await Supabase.instance.client.from('assignments').insert({
      'class_room_id': widget.classRoomId,
      'task_id': lesson['id'],
      'teacher_id': teacherId,
    });

    await _saveTaskMaterial(taskId: lesson['id'].toString());
    await _createClassMaterialRecord(
      classRoomId: widget.classRoomId,
    );

    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Lesson added successfully!')));

    // Ask if they want to add a quiz
    final shouldAddQuiz = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Quiz?'),
        content: const Text('Do you want to add a quiz to this lesson?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldAddQuiz == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AddQuizScreen(
            lessonId: lesson['id'],
            classRoomId: widget.classRoomId,
          ),
        ),
      );
    } else {
      Navigator.pop(context, lesson);
    }
  }

  Widget _buildFilePreview() {
    if (_uploadedFileUrl == null) return const SizedBox();

    switch (_uploadedFileType) {
      case 'image':
        return Image.network(_uploadedFileUrl!, height: 150);
      case 'pdf':
        return Row(
          children: [
            const Icon(Icons.picture_as_pdf),
            const SizedBox(width: 8),
            Expanded(child: Text(_uploadedFileUrl!)),
          ],
        );
      case 'video':
        return Row(
          children: [
            const Icon(Icons.videocam),
            const SizedBox(width: 8),
            Expanded(child: Text(_uploadedFileUrl!)),
          ],
        );
      case 'audio':
        return Row(
          children: [
            const Icon(Icons.audiotrack),
            const SizedBox(width: 8),
            Expanded(child: Text(_uploadedFileUrl!)),
          ],
        );
      default:
        return const SizedBox();
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
    if (storagePath == null || storagePath.isEmpty) {
      return;
    }

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
    if (_uploadedFileUrl == null || _uploadedFileExtension == null) {
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Lesson')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _lessonTitleController,
              decoration: const InputDecoration(labelText: 'Lesson Title'),
            ),
            TextField(
              controller: _lessonDescController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _lessonTimeController,
              decoration: const InputDecoration(labelText: 'Time Limit (minutes)'),
              keyboardType: TextInputType.number,
            ),
            SwitchListTile(
              title: const Text('Unlocks Next Level'),
              value: _unlocksNextLevel,
              onChanged: (val) => setState(() => _unlocksNextLevel = val),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickFile,
              child: const Text('Upload File (Image, PDF, Video, Audio)'),
            ),
            const SizedBox(height: 10),
            _buildFilePreview(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitLesson,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Save Lesson'),
            ),
          ],
        ),
      ),
    );
  }
}

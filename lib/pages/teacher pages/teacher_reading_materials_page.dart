import 'dart:io';
import 'dart:async';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/reading_materials_grading_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:iconsax/iconsax.dart';
import '../../api/reading_materials_service.dart';

// NEW: Audio File Manager Class for handling persistent storage
class _AudioFileManager {
  static Future<void> cleanupOldRecordings({int keepLast = 5}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final persistentDir = Directory('${appDir.path}/teacher_recordings');

      if (!await persistentDir.exists()) {
        return;
      }

      final files = await persistentDir.list().toList();

      // Filter only files
      final fileList = files.whereType<File>().toList();

      if (fileList.length > keepLast) {
        // Sort by modification date (newest first)
        fileList.sort((a, b) {
          final aStat = a.statSync();
          final bStat = b.statSync();
          return bStat.modified.compareTo(aStat.modified);
        });

        // Delete older files
        for (int i = keepLast; i < fileList.length; i++) {
          try {
            await fileList[i].delete();
          } catch (e) {
            debugPrint('Failed to delete old file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up old recordings: $e');
    }
  }

  static Future<bool> isFileValid(File file) async {
    try {
      if (!await file.exists()) {
        debugPrint('❌ [FILE_VALIDATION] File does not exist: ${file.path}');
        return false;
      }

      // Check file size is reasonable (not 0 bytes)
      final length = await file.length();
      if (length == 0) {
        debugPrint('❌ [FILE_VALIDATION] File is empty: ${file.path}');
        return false;
      }

      // Check if file is readable
      try {
        final stat = file.statSync();
        if (!stat.modeString().contains('r')) {
          debugPrint('❌ [FILE_VALIDATION] File is not readable: ${file.path}');
          return false;
        }
      } catch (e) {
        debugPrint('❌ [FILE_VALIDATION] Error checking file permissions: $e');
      }

      debugPrint(
        '✅ [FILE_VALIDATION] File is valid: ${file.path}, Size: $length bytes',
      );
      return true;
    } catch (e) {
      debugPrint('❌ [FILE_VALIDATION] General error: $e');
      return false;
    }
  }
}

class TeacherReadingMaterialsPage extends StatefulWidget {
  final String? classId;
  final VoidCallback? onWillPop;

  const TeacherReadingMaterialsPage({super.key, this.classId, this.onWillPop});

  @override
  State<TeacherReadingMaterialsPage> createState() =>
      _TeacherReadingMaterialsPageState();
}

class _TeacherReadingMaterialsPageState
    extends State<TeacherReadingMaterialsPage> {
  final supabase = Supabase.instance.client;
  List<ReadingMaterial> _materials = [];
  List<Map<String, dynamic>> _readingLevels = [];
  bool _isLoading = true;
  String? _className;
  final ScrollController _scrollController = ScrollController();

  // Audio recording state variables
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecordingAudio = false;
  bool _hasAudioRecording = false;
  String? _audioRecordingPath;
  String? _uploadedAudioUrl;
  bool _isPlayingAudioPreview = false;
  Duration _audioCurrentDuration = Duration.zero;
  Duration _audioTotalDuration = Duration.zero;
  Timer? _audioRecordingTimer;
  int _audioRecordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _cleanupOldTempFiles();
    _cleanupUploadedFiles(); // ADD THIS LINE
    _loadData();
    _setupAudioPlayerListeners();
    // Cleanup old recordings on init
    _AudioFileManager.cleanupOldRecordings();
    // Cleanup old preview audio
    _cleanupOldPreviewAudio();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _audioRecordingTimer?.cancel();
    // Clear audio recording state
    _clearAudioRecording();
    super.dispose();
  }

  Future<void> _cleanupOldPreviewAudio({int keepLast = 5}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final previewDir = Directory('${appDir.path}/teacher_preview_audio');

      if (!await previewDir.exists()) {
        return;
      }

      final files = await previewDir.list().toList();
      final fileList = files.whereType<File>().toList();

      if (fileList.length > keepLast) {
        // Sort by modification date (newest first)
        fileList.sort((a, b) {
          final aStat = a.statSync();
          final bStat = b.statSync();
          return bStat.modified.compareTo(aStat.modified);
        });

        // Delete older files
        for (int i = keepLast; i < fileList.length; i++) {
          try {
            await fileList[i].delete();
            debugPrint(
              '🗑️ [PREVIEW_CLEANUP] Deleted old preview file: ${fileList[i].path}',
            );
          } catch (e) {
            debugPrint('Failed to delete old preview file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up old preview audio: $e');
    }
  }

  void _setupAudioPlayerListeners() {
    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _audioCurrentDuration = position;
        });
      }
    });

    _audioPlayer.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _audioTotalDuration = duration ?? Duration.zero;
        });
      }
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlayingAudioPreview = false;
            _audioCurrentDuration = Duration.zero;
          });
        }
      }
    });
  }

  void _stopAudioRecordingTimer() {
    _audioRecordingTimer?.cancel();
    _audioRecordingTimer = null;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadReadingLevels(),
        _loadMaterials(),
        if (widget.classId != null) _loadClassName(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadClassName() async {
    try {
      final response =
          await supabase
              .from('class_rooms')
              .select('class_name')
              .eq('id', widget.classId!)
              .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _className = response['class_name'] as String?;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading classroom name: $e');
    }
  }

  Future<void> _loadReadingLevels() async {
    try {
      final levels = await ReadingMaterialsService.getAllReadingLevels();
      if (mounted) {
        setState(() => _readingLevels = levels);
      }
    } catch (e) {
      debugPrint('❌ Error loading reading levels: $e');
    }
  }

  Future<void> _loadMaterials() async {
    try {
      final materials =
          widget.classId != null
              ? await ReadingMaterialsService.getReadingMaterialsByClassroom(
                widget.classId!,
              )
              : await ReadingMaterialsService.getAllReadingMaterials();

      if (mounted) {
        setState(() => _materials = materials ?? []);
      }
    } catch (e) {
      debugPrint('❌ Error loading materials: $e');
      if (mounted) {
        setState(() => _materials = []);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAvailablePrerequisites({
    String? excludeMaterialId,
  }) async {
    try {
      // Get all materials except the ones already uploaded (for editing)
      final materials =
          widget.classId != null
              ? await ReadingMaterialsService.getReadingMaterialsByClassroom(
                widget.classId!,
              )
              : await ReadingMaterialsService.getAllReadingMaterials();

      // Convert to format needed for dropdown
      return (materials ?? [])
          .where((material) => material.id != excludeMaterialId)
          .map((material) {
            return {
              'id': material.id,
              'title': material.title,
              'level': material.levelNumber ?? 'N/A',
            };
          })
          .toList();
    } catch (e) {
      debugPrint('❌ Error loading prerequisites: $e');
      return [];
    }
  }

  Future<void> _handleRefresh() async {
    await _loadData();
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    int maxLines = 1,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(icon, color: primaryColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  String _truncateFileName(String fileName, {int maxLength = 30}) {
    if (fileName.length <= maxLength) return fileName;
    return '${fileName.substring(0, maxLength - 3)}...';
  }

  // FIXED: File preview with audio recording capability
  Future<String?> _showFilePreviewWithAudio(
    File file,
    String? fileType, {
    String? title,
    bool allowAudioRecording = false,
  }) async {
    final primaryColor = Theme.of(context).colorScheme.primary;

    try {
      final audioPathResult = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder:
              (context) => _FilePreviewWithAudioScreen(
                file: file,
                fileType: fileType,
                title: title,
                allowAudioRecording: allowAudioRecording,
                primaryColor: primaryColor,
              ),
        ),
      );

      // IMPORTANT: Add a delay to ensure audio resources are released
      await Future.delayed(const Duration(milliseconds: 200));

      return audioPathResult;
    } catch (e) {
      debugPrint('Error in file preview: $e');
      return null;
    }
  }

  Future<void> _showUploadDialog({ReadingMaterial? materialToEdit}) async {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String? selectedLevelId;
    File? selectedFile;
    String? fileType;
    bool hasPrerequisite = false;
    String? selectedPrerequisiteId;
    bool isEditMode = materialToEdit != null;

    // Set initial values if in edit mode
    if (isEditMode) {
      titleController.text = materialToEdit!.title;
      if (materialToEdit.description != null) {
        descriptionController.text = materialToEdit.description!;
      }
      selectedLevelId = materialToEdit.levelId;
      hasPrerequisite = materialToEdit.prerequisiteId != null;
      selectedPrerequisiteId = materialToEdit.prerequisiteId;
    }

    // Load available prerequisites
    final availablePrerequisites = await _loadAvailablePrerequisites(
      excludeMaterialId: isEditMode ? materialToEdit!.id : null,
    );

    // Reset audio recording state when dialog opens
    _clearAudioRecording();

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                insetPadding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isEditMode ? Icons.edit : Icons.upload_file,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isEditMode
                                    ? 'Edit Reading Material'
                                    : widget.classId != null
                                    ? 'Upload Classroom Material'
                                    : 'Upload Reading Material',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Classroom indicator if classId is provided
                              if (widget.classId != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue[200]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.class_rounded,
                                        color: Colors.blue[700],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _className != null
                                              ? 'Classroom: $_className'
                                              : 'Classroom Material',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blue[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              _buildFormField(
                                controller: titleController,
                                label: 'Title *',
                                hintText: 'Enter material title',
                                icon: Icons.title,
                              ),
                              const SizedBox(height: 16),
                              _buildFormField(
                                controller: descriptionController,
                                label: 'Description',
                                hintText: 'Optional description',
                                icon: Icons.description,
                                maxLines: 3,
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    labelText: 'Reading Level *',
                                    border: InputBorder.none,
                                    labelStyle: TextStyle(color: primaryColor),
                                  ),
                                  value: selectedLevelId,
                                  items:
                                      _readingLevels.map((level) {
                                        return DropdownMenuItem(
                                          value: level['id'] as String,
                                          child: Text(
                                            'Level ${level['level_number']}: ${level['title']}',
                                            style: TextStyle(
                                              color: Colors.blueGrey[800],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                  onChanged:
                                      (value) => setDialogState(
                                        () => selectedLevelId = value,
                                      ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Prerequisite Toggle Section
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Toggle Row
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.lock_outline,
                                              color:
                                                  hasPrerequisite
                                                      ? primaryColor
                                                      : Colors.grey,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Add Prerequisite',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    hasPrerequisite
                                                        ? primaryColor
                                                        : Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                        Switch(
                                          value: hasPrerequisite,
                                          onChanged: (value) {
                                            setDialogState(() {
                                              hasPrerequisite = value;
                                              if (!value) {
                                                selectedPrerequisiteId = null;
                                              }
                                            });
                                          },
                                          activeColor: primaryColor,
                                          inactiveTrackColor: Colors.grey[300],
                                        ),
                                      ],
                                    ),

                                    // Prerequisite Dropdown (only shown when toggle is on)
                                    if (hasPrerequisite) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[300]!,
                                          ),
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            labelText: 'Select Prerequisite *',
                                            border: InputBorder.none,
                                            labelStyle: TextStyle(
                                              color: primaryColor,
                                            ),
                                            hintText: 'Choose a material',
                                          ),
                                          value: selectedPrerequisiteId,
                                          items: [
                                            // Default option
                                            DropdownMenuItem(
                                              value: null,
                                              child: Text(
                                                'Select a material',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                            ...availablePrerequisites.map((
                                              material,
                                            ) {
                                              return DropdownMenuItem(
                                                value: material['id'] as String,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      material['title']
                                                          as String,
                                                      style: TextStyle(
                                                        color:
                                                            Colors
                                                                .blueGrey[800],
                                                      ),
                                                    ),
                                                    Text(
                                                      'Level ${material['level']}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ],
                                          onChanged:
                                              (value) => setDialogState(
                                                () =>
                                                    selectedPrerequisiteId =
                                                        value,
                                              ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue[200]!,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              size: 18,
                                              color: Colors.blue[700],
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Students must complete this prerequisite before accessing the new material',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.blue[700],
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
                              const SizedBox(height: 20),

                              // File Upload Section (only show for new uploads, not for editing)
                              if (!isEditMode) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // File type indicator
                                      if (fileType == 'pdf')
                                        Icon(
                                          Icons.picture_as_pdf,
                                          size: 40,
                                          color: Colors.red[600],
                                        )
                                      else if (fileType == 'image')
                                        Icon(
                                          Icons.image,
                                          size: 40,
                                          color: Colors.green[600],
                                        )
                                      else
                                        Icon(
                                          Icons.insert_drive_file,
                                          size: 40,
                                          color: primaryColor,
                                        ),

                                      const SizedBox(height: 12),

                                      // File selection buttons
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () async {
                                                final result = await FilePicker
                                                    .platform
                                                    .pickFiles(
                                                      type: FileType.custom,
                                                      allowedExtensions: [
                                                        'pdf',
                                                      ],
                                                    );
                                                if (result != null &&
                                                    result.files.single.path !=
                                                        null) {
                                                  try {
                                                    final originalPath =
                                                        result
                                                            .files
                                                            .single
                                                            .path!;
                                                    final originalFile = File(
                                                      originalPath,
                                                    );

                                                    // Read the file bytes immediately
                                                    final bytes =
                                                        await originalFile
                                                            .readAsBytes();
                                                    debugPrint(
                                                      '📁 [FILE_PICKER] Original file bytes loaded: ${bytes.length} bytes',
                                                    );

                                                    // Save to app's documents directory for persistence (not cache)
                                                    final appDir =
                                                        await getApplicationDocumentsDirectory();
                                                    final persistentDir = Directory(
                                                      '${appDir.path}/teacher_uploads',
                                                    );

                                                    if (!await persistentDir
                                                        .exists()) {
                                                      await persistentDir
                                                          .create(
                                                            recursive: true,
                                                          );
                                                    }

                                                    final timestamp =
                                                        DateTime.now()
                                                            .millisecondsSinceEpoch;
                                                    final fileName =
                                                        result
                                                            .files
                                                            .single
                                                            .name;
                                                    final persistentFilePath =
                                                        '${persistentDir.path}/persistent_${timestamp}_$fileName';
                                                    final persistentFile = File(
                                                      persistentFilePath,
                                                    );

                                                    await persistentFile
                                                        .writeAsBytes(bytes);
                                                    debugPrint(
                                                      '📁 [FILE_PICKER] Saved to persistent location: $persistentFilePath',
                                                    );

                                                    // Verify the file exists
                                                    final persistentFileExists =
                                                        await persistentFile
                                                            .exists();
                                                    debugPrint(
                                                      '📁 [FILE_PICKER] Persistent file exists: $persistentFileExists',
                                                    );
                                                    if (persistentFileExists) {
                                                      final fileSize =
                                                          await persistentFile
                                                              .length();
                                                      debugPrint(
                                                        '📁 [FILE_PICKER] Persistent file size: $fileSize bytes',
                                                      );
                                                    }

                                                    setDialogState(() {
                                                      selectedFile =
                                                          persistentFile;
                                                      fileType = 'pdf';
                                                    });
                                                  } catch (e) {
                                                    debugPrint(
                                                      '❌ [FILE_PICKER] Error processing file: $e',
                                                    );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Error saving file: ${e.toString()}',
                                                          ),
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                      );
                                                    }
                                                  }
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.picture_as_pdf,
                                                size: 20,
                                              ),
                                              label: const Text(
                                                'PDF',
                                                style: TextStyle(fontSize: 14),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red[50],
                                                foregroundColor:
                                                    Colors.red[700],
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  side: BorderSide(
                                                    color: Colors.red[200]!,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () async {
                                                final result = await FilePicker
                                                    .platform
                                                    .pickFiles(
                                                      type: FileType.image,
                                                    );
                                                if (result != null &&
                                                    result.files.single.path !=
                                                        null) {
                                                  try {
                                                    final originalPath =
                                                        result
                                                            .files
                                                            .single
                                                            .path!;
                                                    final originalFile = File(
                                                      originalPath,
                                                    );

                                                    // Read the file bytes immediately
                                                    final bytes =
                                                        await originalFile
                                                            .readAsBytes();
                                                    debugPrint(
                                                      '📁 [FILE_PICKER] Original file bytes loaded: ${bytes.length} bytes',
                                                    );

                                                    // Save to app's documents directory for persistence (not cache)
                                                    final appDir =
                                                        await getApplicationDocumentsDirectory();
                                                    final persistentDir = Directory(
                                                      '${appDir.path}/teacher_uploads',
                                                    );

                                                    if (!await persistentDir
                                                        .exists()) {
                                                      await persistentDir
                                                          .create(
                                                            recursive: true,
                                                          );
                                                    }

                                                    final timestamp =
                                                        DateTime.now()
                                                            .millisecondsSinceEpoch;
                                                    final fileName =
                                                        result
                                                            .files
                                                            .single
                                                            .name;
                                                    final persistentFilePath =
                                                        '${persistentDir.path}/persistent_${timestamp}_$fileName';
                                                    final persistentFile = File(
                                                      persistentFilePath,
                                                    );

                                                    await persistentFile
                                                        .writeAsBytes(bytes);
                                                    debugPrint(
                                                      '📁 [FILE_PICKER] Saved to persistent location: $persistentFilePath',
                                                    );

                                                    // Verify the file exists
                                                    final persistentFileExists =
                                                        await persistentFile
                                                            .exists();
                                                    debugPrint(
                                                      '📁 [FILE_PICKER] Persistent file exists: $persistentFileExists',
                                                    );
                                                    if (persistentFileExists) {
                                                      final fileSize =
                                                          await persistentFile
                                                              .length();
                                                      debugPrint(
                                                        '📁 [FILE_PICKER] Persistent file size: $fileSize bytes',
                                                      );
                                                    }

                                                    setDialogState(() {
                                                      selectedFile =
                                                          persistentFile;
                                                      fileType = 'image';
                                                    });
                                                  } catch (e) {
                                                    debugPrint(
                                                      '❌ [FILE_PICKER] Error processing file: $e',
                                                    );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Error saving file: ${e.toString()}',
                                                          ),
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                      );
                                                    }
                                                  }
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.image,
                                                size: 20,
                                              ),
                                              label: const Text(
                                                'Image',
                                                style: TextStyle(fontSize: 14),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.green[50],
                                                foregroundColor:
                                                    Colors.green[700],
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  side: BorderSide(
                                                    color: Colors.green[200]!,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      if (selectedFile != null) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color:
                                                fileType == 'pdf'
                                                    ? Colors.red[50]
                                                    : Colors.green[50],
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color:
                                                  fileType == 'pdf'
                                                      ? Colors.red[200]!
                                                      : Colors.green[200]!,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    fileType == 'pdf'
                                                        ? Icons.picture_as_pdf
                                                        : Icons.image,
                                                    color:
                                                        fileType == 'pdf'
                                                            ? Colors.red[600]
                                                            : Colors.green[600],
                                                    size: 24,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          _truncateFileName(
                                                            selectedFile!.path
                                                                .split('/')
                                                                .last,
                                                          ),
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                fileType ==
                                                                        'pdf'
                                                                    ? Colors
                                                                        .red[700]
                                                                    : Colors
                                                                        .green[700],
                                                          ),
                                                        ),
                                                        Text(
                                                          fileType == 'pdf'
                                                              ? 'PDF Document'
                                                              : 'Image File',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                fileType ==
                                                                        'pdf'
                                                                    ? Colors
                                                                        .red[600]
                                                                    : Colors
                                                                        .green[600],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Row(
                                                    children: [
                                                      // Preview button - NOW INCLUDES AUDIO RECORDING
                                                      IconButton(
                                                        icon: Icon(
                                                          Icons.remove_red_eye,
                                                          size: 20,
                                                          color: primaryColor,
                                                        ),
                                                        onPressed: () async {
                                                          try {
                                                            // Look for this section in your _showUploadDialog method and replace it:
                                                            final audioPath =
                                                                await _showFilePreviewWithAudio(
                                                                  selectedFile!,
                                                                  fileType,
                                                                  title:
                                                                      titleController
                                                                          .text
                                                                          .trim(),
                                                                  allowAudioRecording:
                                                                      true,
                                                                );

                                                            if (audioPath !=
                                                                null) {
                                                              // Validate the audio file before setting state
                                                              final audioFile =
                                                                  File(
                                                                    audioPath,
                                                                  );
                                                              final isValid =
                                                                  await _AudioFileManager.isFileValid(
                                                                    audioFile,
                                                                  );

                                                              if (isValid) {
                                                                setDialogState(() {
                                                                  _audioRecordingPath =
                                                                      audioPath;
                                                                  _hasAudioRecording =
                                                                      true;
                                                                });

                                                                // DEBUG: Log file info
                                                                final fileSize =
                                                                    await audioFile
                                                                        .length();
                                                                debugPrint(
                                                                  '📁 [AUDIO_UPLOAD] Preview audio ready: $audioPath, Size: $fileSize bytes',
                                                                );

                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      'Audio instructions added successfully',
                                                                    ),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .green,
                                                                  ),
                                                                );
                                                              } else {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      'Audio file is invalid. Please record again.',
                                                                    ),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                  ),
                                                                );
                                                              }
                                                            }
                                                          } catch (e) {
                                                            debugPrint(
                                                              'Error in preview: $e',
                                                            );
                                                            ScaffoldMessenger.of(
                                                              context,
                                                            ).showSnackBar(
                                                              SnackBar(
                                                                content: Text(
                                                                  'Error: ${e.toString()}',
                                                                ),
                                                                backgroundColor:
                                                                    Colors.red,
                                                              ),
                                                            );
                                                          }
                                                        },
                                                        tooltip:
                                                            'Preview & Add Audio',
                                                      ),
                                                      // Remove button
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.close,
                                                          size: 18,
                                                          color: Colors.grey,
                                                        ),
                                                        onPressed: () {
                                                          setDialogState(() {
                                                            selectedFile = null;
                                                            fileType = null;
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Tap the eye icon to preview the file and add audio instructions',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                              // Show audio recording status if exists
                                              if (_hasAudioRecording &&
                                                  _audioRecordingPath !=
                                                      null) ...[
                                                const SizedBox(height: 8),
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green[50],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.green[200]!,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.check_circle,
                                                        color: Colors.green,
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Audio instructions added',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.green[700],
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      IconButton(
                                                        icon: Icon(
                                                          Icons.delete_outline,
                                                          size: 16,
                                                          color: Colors.red,
                                                        ),
                                                        onPressed: () {
                                                          setDialogState(() {
                                                            _hasAudioRecording =
                                                                false;
                                                            _audioRecordingPath =
                                                                null;
                                                          });
                                                        },
                                                        padding:
                                                            EdgeInsets.zero,
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Select PDF or Image file',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ] else ...[
                                // Show current file info in edit mode
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        materialToEdit!.fileUrl
                                                .toLowerCase()
                                                .endsWith('.pdf')
                                            ? Icons.picture_as_pdf
                                            : Icons.image,
                                        color:
                                            materialToEdit.fileUrl
                                                    .toLowerCase()
                                                    .endsWith('.pdf')
                                                ? Colors.red[600]
                                                : Colors.green[600],
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Current File',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                            Text(
                                              materialToEdit.fileUrl
                                                  .split('/')
                                                  .last,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Cannot Change',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                      // Actions
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: BorderSide(color: Colors.grey[400]!),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    isEditMode
                                        ? (selectedLevelId != null &&
                                                titleController.text
                                                    .trim()
                                                    .isNotEmpty &&
                                                (!hasPrerequisite ||
                                                    selectedPrerequisiteId !=
                                                        null))
                                            ? () async {
                                              Navigator.pop(context);
                                              await _updateMaterial(
                                                materialId: materialToEdit!.id,
                                                title:
                                                    titleController.text.trim(),
                                                levelId: selectedLevelId!,
                                                description:
                                                    descriptionController.text
                                                            .trim()
                                                            .isEmpty
                                                        ? null
                                                        : descriptionController
                                                            .text
                                                            .trim(),
                                                prerequisiteId:
                                                    hasPrerequisite
                                                        ? selectedPrerequisiteId
                                                        : null,
                                              );
                                            }
                                            : null
                                        : (selectedFile != null &&
                                            selectedLevelId != null &&
                                            titleController.text
                                                .trim()
                                                .isNotEmpty &&
                                            (!hasPrerequisite ||
                                                selectedPrerequisiteId != null))
                                        ? () async {
                                          // PUT THE DEBUG CODE RIGHT HERE:
                                          debugPrint(
                                            '📁 [UPLOAD_DIALOG] Starting upload...',
                                          );
                                          debugPrint(
                                            '📁 [UPLOAD_DIALOG] Selected file: ${selectedFile?.path}',
                                          );
                                          debugPrint(
                                            '📁 [UPLOAD_DIALOG] Audio file: ${_audioRecordingPath}',
                                          );
                                          if (_audioRecordingPath != null) {
                                            final audioFile = File(
                                              _audioRecordingPath!,
                                            );
                                            final exists =
                                                await audioFile.exists();
                                            final size =
                                                exists
                                                    ? await audioFile.length()
                                                    : 0;
                                            debugPrint(
                                              '📁 [UPLOAD_DIALOG] Audio exists: $exists, Size: $size bytes',
                                            );
                                          }

                                          Navigator.pop(context);
                                          // Check if we have an audio recording to upload
                                          File? audioFile;
                                          if (_hasAudioRecording &&
                                              _audioRecordingPath != null) {
                                            audioFile = File(
                                              _audioRecordingPath!,
                                            );
                                            final isValid =
                                                await _AudioFileManager.isFileValid(
                                                  audioFile,
                                                );
                                            if (!isValid) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Audio file is invalid. Please record again.',
                                                    ),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                              return;
                                            }
                                          }

                                          await _uploadMaterial(
                                            file: selectedFile!,
                                            title: titleController.text.trim(),
                                            levelId: selectedLevelId!,
                                            description:
                                                descriptionController.text
                                                        .trim()
                                                        .isEmpty
                                                    ? null
                                                    : descriptionController.text
                                                        .trim(),
                                            prerequisiteId:
                                                hasPrerequisite
                                                    ? selectedPrerequisiteId
                                                    : null,
                                            audioFile: audioFile,
                                          );
                                        }
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  isEditMode ? 'Update' : 'Upload',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
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
            },
          ),
    );
  }

  void _clearAudioRecording() {
    if (_isRecordingAudio) {
      // Stop recording if in progress
      _audioRecorder.stop();
      _stopAudioRecordingTimer();
    }

    setState(() {
      _isRecordingAudio = false;
      _hasAudioRecording = false;
      _audioRecordingPath = null;
      _uploadedAudioUrl = null;
      _isPlayingAudioPreview = false;
      _audioCurrentDuration = Duration.zero;
      _audioTotalDuration = Duration.zero;
      _audioRecordingSeconds = 0;
    });

    _audioPlayer.stop();
  }

  Future<void> _uploadMaterial({
    required File file,
    required String title,
    required String levelId,
    String? description,
    String? prerequisiteId,
    File? audioFile,
  }) async {
    if (!mounted) return;

    // NEW: Check if audio file exists before uploading
    if (audioFile != null) {
      debugPrint('📁 [UPLOAD] Validating audio file: ${audioFile.path}');

      // Check if file actually exists
      if (!await audioFile.exists()) {
        debugPrint('❌ [UPLOAD] Audio file does not exist: ${audioFile.path}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio file was deleted. Please record again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Check file size
      final fileSize = await audioFile.length();
      if (fileSize == 0) {
        debugPrint('❌ [UPLOAD] Audio file is empty: ${audioFile.path}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio file is empty. Please record again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      debugPrint(
        '✅ [UPLOAD] Audio file validated: ${audioFile.path}, Size: $fileSize bytes',
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.classId != null
                          ? 'Uploading Classroom Material...'
                          : 'Uploading Material...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    try {
      final result = await ReadingMaterialsService.uploadReadingMaterial(
        file: file,
        title: title,
        levelId: levelId,
        description: description,
        classroomId: widget.classId,
        prerequisiteId: prerequisiteId,
        audioFile: audioFile,
      );

      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      if (result != null && !result.containsKey('error')) {
        // Clear audio recording state after successful upload
        setState(() {
          _hasAudioRecording = false;
          _audioRecordingPath = null;
        });

        // Clean up old preview audio files
        await _cleanupPreviewAudioAfterUpload();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.classId != null
                      ? 'Classroom material uploaded successfully!'
                      : 'Material uploaded successfully!',
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        await _loadMaterials();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(result?['error'] ?? 'Upload failed'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      debugPrint('❌ [UPLOAD] Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Upload error: ${e.toString()}'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _updateMaterial({
    required String materialId,
    required String title,
    required String levelId,
    String? description,
    String? prerequisiteId,
  }) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Updating Material...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    try {
      final success = await ReadingMaterialsService.updateReadingMaterial(
        materialId: materialId,
        title: title,
        description: description,
        levelId: levelId,
        classRoomId: widget.classId,
        prerequisiteId: prerequisiteId,
      );

      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('Material updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        await _loadMaterials();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('Failed to update material'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Error: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showAssignMaterialsDialog() async {
    if (widget.classId == null) return;

    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    setState(() => _isLoading = true);

    final unassignedMaterials =
        await ReadingMaterialsService.getUnassignedReadingMaterials(
          classroomId: widget.classId!,
        );

    setState(() => _isLoading = false);

    if (unassignedMaterials.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No unassigned materials available'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              final selectedMaterials = <String>{};

              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                insetPadding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_to_photos,
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Assign Existing Materials',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      // Materials list
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: unassignedMaterials.length,
                          itemBuilder: (context, index) {
                            final material = unassignedMaterials[index];
                            final isSelected = selectedMaterials.contains(
                              material.id,
                            );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: CheckboxListTile(
                                title: Text(material.title),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Level ${material.levelNumber ?? 'N/A'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    if (material.description != null)
                                      Text(
                                        material.description!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                                secondary: Icon(
                                  material.fileUrl.toLowerCase().endsWith(
                                        '.pdf',
                                      )
                                      ? Icons.picture_as_pdf
                                      : Icons.image,
                                  color: primaryColor,
                                ),
                                value: isSelected,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selectedMaterials.add(material.id);
                                    } else {
                                      selectedMaterials.remove(material.id);
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      // Actions
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(20),
                          ),
                          border: Border(
                            top: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    selectedMaterials.isEmpty
                                        ? null
                                        : () async {
                                          await _assignMaterialsToClassroom(
                                            materialIds:
                                                selectedMaterials.toList(),
                                          );
                                          Navigator.pop(context);
                                        },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Assign (${selectedMaterials.length})',
                                  style: const TextStyle(color: Colors.white),
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
            },
          ),
    );
  }

  Future<void> _assignMaterialsToClassroom({
    required List<String> materialIds,
  }) async {
    if (widget.classId == null) return;

    int successCount = 0;
    int failCount = 0;

    for (final materialId in materialIds) {
      final success = await ReadingMaterialsService.assignMaterialToClassroom(
        materialId: materialId,
        classroomId: widget.classId!,
      );

      if (success) {
        successCount++;
      } else {
        failCount++;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assigned $successCount materials. Failed: $failCount'),
          backgroundColor: successCount > 0 ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );

      if (successCount > 0) {
        await _loadMaterials();
      }
    }
  }

  Future<void> _deleteMaterial(ReadingMaterial material) async {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (widget.classId != null) {
      final action = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Remove Material'),
              content: Text(
                'Do you want to remove "${material.title}" from this classroom, or delete it entirely?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'delete'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text(
                    'Delete Permanently',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
      );

      if (action == 'remove') {
        final success =
            await ReadingMaterialsService.removeMaterialFromClassroom(
              materialId: material.id,
              classroomId: widget.classId!,
            );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Material removed from classroom'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          await _loadMaterials();
        }
        return;
      } else if (action != 'delete') {
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Deletion'),
            content: Text(
              'Are you sure you want to permanently delete "${material.title}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    final success = await ReadingMaterialsService.deleteReadingMaterial(
      material.id,
    );
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Material deleted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await _loadMaterials();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete material'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _viewSubmissions(ReadingMaterial material) async {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final submissions = await ReadingMaterialsService.getSubmissionsForMaterial(
      material.id,
    );

    if (!mounted) return;

    final audioPlayer = AudioPlayer();
    String? playingUrl;
    bool isPlaying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                height:
                    MediaQuery.of(context).size.height * (isMobile ? 0.9 : 0.8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.people,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Submissions for "${material.title}"',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 24,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              audioPlayer.dispose();
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: Container(
                        color: Colors.grey[50],
                        child:
                            submissions.isEmpty
                                ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.assignment_outlined,
                                          size: isMobile ? 60 : 80,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No submissions yet',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: isMobile ? 16 : 18,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Students haven\'t submitted recordings for this material',
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: isMobile ? 12 : 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: submissions.length,
                                  itemBuilder: (context, index) {
                                    final submission = submissions[index];
                                    final student =
                                        submission['students']
                                            as Map<String, dynamic>?;
                                    final recordingUrl =
                                        submission['recording_url']
                                            as String? ??
                                        submission['file_url'] as String?;
                                    final isThisPlaying =
                                        playingUrl == recordingUrl;
                                    final needsGrading =
                                        submission['needs_grading'] == true;

                                    final profilePic =
                                        student?['profile_picture'] as String?;

                                    final submissionDate =
                                        submission['created_at'] ??
                                        submission['recorded_at'];
                                    final formattedDate = _formatSubmissionDate(
                                      submissionDate,
                                    );

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: Material(
                                        borderRadius: BorderRadius.circular(16),
                                        elevation: 1,
                                        color: Colors.white,
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(
                                            16,
                                          ),
                                          leading: _buildStudentAvatar(
                                            studentName:
                                                student?['student_name']
                                                    as String?,
                                            profilePic: profilePic,
                                            primaryColor: primaryColor,
                                          ),
                                          title: Text(
                                            student?['student_name'] ??
                                                'Unknown',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blueGrey[800],
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Submitted: $formattedDate',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              if (needsGrading) ...[
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange[100],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Needs Grading',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.orange[800],
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          trailing:
                                              recordingUrl != null
                                                  ? Container(
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          isThisPlaying &&
                                                                  isPlaying
                                                              ? primaryColor
                                                              : primaryColor
                                                                  .withOpacity(
                                                                    0.1,
                                                                  ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),
                                                    ),
                                                    child: IconButton(
                                                      icon: Icon(
                                                        isThisPlaying &&
                                                                isPlaying
                                                            ? Icons.stop
                                                            : Icons.play_arrow,
                                                        color:
                                                            isThisPlaying &&
                                                                    isPlaying
                                                                ? Colors.white
                                                                : primaryColor,
                                                        size: 20,
                                                      ),
                                                      onPressed: () async {
                                                        try {
                                                          if (isThisPlaying &&
                                                              isPlaying) {
                                                            await audioPlayer
                                                                .stop();
                                                            setModalState(() {
                                                              isPlaying = false;
                                                              playingUrl = null;
                                                            });
                                                          } else {
                                                            if (playingUrl !=
                                                                null) {
                                                              await audioPlayer
                                                                  .stop();
                                                            }

                                                            await audioPlayer
                                                                .setUrl(
                                                                  recordingUrl!,
                                                                );
                                                            await audioPlayer
                                                                .play();
                                                            setModalState(() {
                                                              playingUrl =
                                                                  recordingUrl;
                                                              isPlaying = true;
                                                            });

                                                            audioPlayer.playerStateStream.listen((
                                                              state,
                                                            ) {
                                                              if (state
                                                                      .processingState ==
                                                                  ProcessingState
                                                                      .completed) {
                                                                setModalState(
                                                                  () {
                                                                    isPlaying =
                                                                        false;
                                                                    playingUrl =
                                                                        null;
                                                                  },
                                                                );
                                                              }
                                                            });
                                                          }
                                                        } catch (e) {
                                                          debugPrint(
                                                            'Error playing audio: $e',
                                                          );
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'Error playing audio: $e',
                                                              ),
                                                              backgroundColor:
                                                                  Colors.red,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                    ),
                                                  )
                                                  : Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[100],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      Icons.error,
                                                      size: 20,
                                                      color: Colors.grey[500],
                                                    ),
                                                  ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    ).whenComplete(() => audioPlayer.dispose());
  }

  Widget _buildStudentAvatar({
    required String? studentName,
    required String? profilePic,
    required Color primaryColor,
  }) {
    final name = studentName ?? 'U';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    if (profilePic != null && profilePic.isNotEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: primaryColor.withOpacity(0.2), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.network(
            profilePic,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    value:
                        loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                    strokeWidth: 2,
                    color: primaryColor,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryColor,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  String _formatSubmissionDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown date';

    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} minutes ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hours ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        final formatter = DateFormat('MMM d, y • h:mm a');
        return formatter.format(date.toLocal());
      }
    } catch (e) {
      debugPrint('Error parsing date: $e');
      return 'Invalid date';
    }
  }

  Widget _buildMaterialItem(ReadingMaterial material, int index) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final isPdf = material.fileUrl.toLowerCase().endsWith('.pdf');
    final isImage =
        material.fileUrl.toLowerCase().endsWith('.jpg') ||
        material.fileUrl.toLowerCase().endsWith('.jpeg') ||
        material.fileUrl.toLowerCase().endsWith('.png');

    IconData fileIcon;
    Color iconColor;
    Color backgroundColor;

    if (isPdf) {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.white;
      backgroundColor = Colors.red[600]!;
    } else if (isImage) {
      fileIcon = Icons.image;
      iconColor = Colors.white;
      backgroundColor = Colors.green[600]!;
    } else {
      fileIcon = Icons.insert_drive_file;
      iconColor = Colors.white;
      backgroundColor = primaryColor;
    }

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        color: Colors.white,
        child: ListTile(
          contentPadding: EdgeInsets.all(isMobile ? 16 : 20),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(fileIcon, color: iconColor, size: isMobile ? 24 : 28),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  material.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 15 : 16,
                    color: Colors.blueGrey[800],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (material.hasPrerequisite ?? false) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Has prerequisite',
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.amber[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      size: isMobile ? 14 : 16,
                      color: Colors.amber[800],
                    ),
                  ),
                ),
              ],
              if (material.audioUrl != null &&
                  material.audioUrl!.isNotEmpty) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Has audio instructions',
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.volume_up,
                      size: isMobile ? 12 : 14,
                      color: Colors.purple[800],
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Level ${material.levelNumber ?? 'N/A'}',
                      style: TextStyle(
                        fontSize: isMobile ? 10 : 12,
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (material.className != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        material.className!,
                        style: TextStyle(
                          fontSize: isMobile ? 10 : 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (material.audioUrl != null &&
                      material.audioUrl!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.volume_up,
                            size: isMobile ? 8 : 10,
                            color: Colors.purple[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Audio',
                            style: TextStyle(
                              fontSize: isMobile ? 10 : 12,
                              color: Colors.purple[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (material.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  material.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              if (material.prerequisiteTitle != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: Colors.amber[700],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Requires: ${material.prerequisiteTitle!}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (value == 'edit') {
                _showUploadDialog(materialToEdit: material);
              } else if (value == 'submissions') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => ReadingMaterialGradingPage(
                          materialId: material.id,
                          materialTitle: material.title,
                          onWillPop: () {
                            // Optional callback when returning
                            _loadData();
                          },
                        ),
                  ),
                );
              } else if (value == 'delete') {
                _deleteMaterial(material);
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 10),
                        Text("Edit"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'submissions',
                    child: Row(
                      children: [
                        Icon(Icons.grading, size: 20),
                        SizedBox(width: 10),
                        Text("Grade Submissions"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 10),
                        Text("Delete"),
                      ],
                    ),
                  ),
                ],
          ),
          onTap: () {
            if (isPdf) {
              _showPdfPreview(material);
            } else if (isImage) {
              _showImagePreview(material);
            }
          },
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Future<void> _showPdfPreview(ReadingMaterial material) async {
    final primaryColor = Theme.of(context).colorScheme.primary;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PdfPreviewWithAudioScreen(
              pdfUrl: material.fileUrl,
              audioUrl: material.audioUrl,
              title: material.title,
              primaryColor: primaryColor,
            ),
      ),
    );
  }

  Future<void> _showImagePreview(ReadingMaterial material) async {
    final primaryColor = Theme.of(context).colorScheme.primary;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ImagePreviewWithAudioScreen(
              imageUrl: material.fileUrl,
              audioUrl: material.audioUrl,
              title: material.title,
              primaryColor: primaryColor,
            ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Stack(
      children: [
        Container(
          color: Colors.grey[50],
          child: Column(
            children: [
              // Classroom indicator if classId is provided
              if (widget.classId != null && _className != null)
                Container(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  color: Colors.blue[50],
                  child: Row(
                    children: [
                      Icon(
                        Icons.class_rounded,
                        color: Colors.blue[700],
                        size: isMobile ? 18 : 20,
                      ),
                      SizedBox(width: isMobile ? 8 : 12),
                      Expanded(
                        child: Text(
                          'Classroom: $_className',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child:
                    _isLoading
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: primaryColor,
                                strokeWidth: 2.5,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.classId != null
                                    ? 'Loading Classroom Materials...'
                                    : 'Loading Materials...',
                                style: TextStyle(
                                  fontSize: isMobile ? 14 : 16,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                        : Column(
                          children: [
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _handleRefresh,
                                color: primaryColor,
                                backgroundColor: Colors.white,
                                child:
                                    _materials.isEmpty
                                        ? Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                              isMobile ? 24 : 32,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.library_books_outlined,
                                                  size: isMobile ? 60 : 80,
                                                  color: Colors.grey[400],
                                                ),
                                                SizedBox(
                                                  height: isMobile ? 16 : 24,
                                                ),
                                                Text(
                                                  widget.classId != null
                                                      ? 'No Classroom Materials Yet'
                                                      : 'No Reading Materials Yet',
                                                  style: TextStyle(
                                                    fontSize:
                                                        isMobile ? 16 : 18,
                                                    color: Colors.grey[600],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                SizedBox(
                                                  height: isMobile ? 8 : 12,
                                                ),
                                                Text(
                                                  widget.classId != null
                                                      ? 'Tap + to upload or assign materials'
                                                      : 'Tap + to upload your first material',
                                                  style: TextStyle(
                                                    fontSize:
                                                        isMobile ? 12 : 14,
                                                    color: Colors.grey[500],
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        : ListView.builder(
                                          controller: _scrollController,
                                          padding: EdgeInsets.all(
                                            isMobile ? 12 : 16,
                                          ),
                                          itemCount: _materials.length,
                                          itemBuilder: (context, index) {
                                            final material = _materials[index];
                                            return _buildMaterialItem(
                                              material,
                                              index,
                                            );
                                          },
                                        ),
                              ),
                            ),
                          ],
                        ),
              ),
            ],
          ),
        ),
        // Floating Action Button
        Positioned(
          bottom: isMobile ? 16 : 20,
          right: isMobile ? 16 : 20,
          child: FloatingActionButton(
            onPressed: _showUploadDialog,
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            child: Icon(Icons.add, size: isMobile ? 24 : 28),
          ),
        ),
      ],
    );
  }

  Future<void> _cleanupPreviewAudioAfterUpload() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final previewDir = Directory('${appDir.path}/teacher_preview_audio');

      if (!await previewDir.exists()) {
        return;
      }

      // Delete all preview audio files older than 1 hour
      final files = await previewDir.list().toList();
      final cutoffTime = DateTime.now().subtract(const Duration(hours: 1));

      for (var file in files) {
        if (file is File && file.path.endsWith('.m4a')) {
          try {
            final stat = await file.stat();
            if (stat.modified.isBefore(cutoffTime)) {
              await file.delete();
              debugPrint(
                '🗑️ [CLEANUP] Deleted old preview file: ${file.path}',
              );
            }
          } catch (e) {
            debugPrint('Failed to delete old preview file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up preview audio: $e');
    }
  }

  // Add this method to clean up old temporary files
  Future<void> _cleanupOldTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = await tempDir.list().toList();
      final cutoffTime = DateTime.now().subtract(const Duration(hours: 1));

      for (var file in files) {
        if (file is File && file.path.contains('persistent_')) {
          try {
            final stat = await file.stat();
            if (stat.modified.isBefore(cutoffTime)) {
              await file.delete();
              debugPrint('🗑️ Cleaned up old temp file: ${file.path}');
            }
          } catch (e) {
            debugPrint('Failed to delete old temp file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up temp files: $e');
    }
  }

  Future<void> _cleanupUploadedFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final uploadDir = Directory('${appDir.path}/teacher_uploads');

      if (!await uploadDir.exists()) {
        return;
      }

      final files = await uploadDir.list().toList();
      final cutoffTime = DateTime.now().subtract(const Duration(hours: 1));

      for (var file in files) {
        if (file is File) {
          try {
            final stat = await file.stat();
            if (stat.modified.isBefore(cutoffTime)) {
              await file.delete();
              debugPrint('🗑️ Cleaned up old upload file: ${file.path}');
            }
          } catch (e) {
            debugPrint('Failed to delete old upload file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up uploaded files: $e');
    }
  }
}

class PdfPreviewWithAudioScreen extends StatefulWidget {
  final String pdfUrl;

  final String? audioUrl;

  final String title;

  final Color primaryColor;

  const PdfPreviewWithAudioScreen({
    super.key,

    required this.pdfUrl,

    this.audioUrl,

    required this.title,

    required this.primaryColor,
  });

  @override
  State<PdfPreviewWithAudioScreen> createState() =>
      _PdfPreviewWithAudioScreenState();
}

class _PdfPreviewWithAudioScreenState extends State<PdfPreviewWithAudioScreen> {
  final _audioPlayer = AudioPlayer();

  bool _isPlaying = false;

  bool _isBuffering = false;

  bool _hasError = false;

  Duration _position = Duration.zero;

  Duration _duration = Duration.zero;

  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();

    _initAudio();
  }

  Future<void> _initAudio() async {
    if (widget.audioUrl == null || widget.audioUrl!.isEmpty) return;

    try {
      // ── Modern just_audio syntax ──
      final audioSource =
          widget.audioUrl!.startsWith('http')
              ? AudioSource.uri(Uri.parse(widget.audioUrl!))
              : AudioSource.file(File(widget.audioUrl!) as String);

      await _audioPlayer.setAudioSource(audioSource, preload: true);
      await _audioPlayer.load();

      // Position & duration
      _audioPlayer.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _audioPlayer.durationStream.listen((dur) {
        if (mounted) setState(() => _duration = dur ?? Duration.zero);
      });

      // Core state sync
      _audioPlayer.playerStateStream.listen((playerState) {
        if (!mounted) return;

        final playing = playerState.playing;
        final processing = playerState.processingState;

        setState(() {
          _isPlaying =
              playing &&
              processing != ProcessingState.completed &&
              processing != ProcessingState.idle;
          _isBuffering = processing == ProcessingState.buffering;
          _hasError =
              (processing == ProcessingState.idle &&
                  !playing &&
                  _duration > Duration.zero);
        });
      });
    } catch (e, stack) {
      debugPrint("Audio init failed: $e\n$stack");
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        // If finished → restart from beginning

        if (_audioPlayer.processingState == ProcessingState.completed) {
          await _audioPlayer.seek(Duration.zero);
        }

        await _audioPlayer.play();
      }

      // No setState here — stream will update UI
    } catch (e) {
      debugPrint("Playback control error: $e");

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Playback error: $e")));
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');

    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pdfViewer = SfPdfViewer.network(widget.pdfUrl);

    return Scaffold(
      appBar:
          _isFullscreen
              ? null
              : AppBar(
                title: Text(widget.title),

                backgroundColor: widget.primaryColor,

                foregroundColor: Colors.white,

                actions: [
                  if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty)
                    IconButton(
                      icon:
                          _isBuffering
                              ? const SizedBox(
                                width: 24,

                                height: 24,

                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                              : Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                              ),

                      onPressed: _togglePlayback,

                      tooltip: _isPlaying ? 'Pause' : 'Play',
                    ),

                  IconButton(
                    icon: Icon(
                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),

                    onPressed:
                        () => setState(() => _isFullscreen = !_isFullscreen),
                  ),
                ],
              ),

      body: Stack(
        children: [
          // PDF Content
          _isFullscreen
              ? pdfViewer
              : Column(
                children: [
                  if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty)
                    _buildAudioControls(),

                  Expanded(child: pdfViewer),
                ],
              ),

          // Fullscreen exit button
          if (_isFullscreen)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,

                child: Padding(
                  padding: const EdgeInsets.all(16.0),

                  child: FloatingActionButton(
                    mini: true,

                    backgroundColor: Colors.black.withOpacity(0.6),

                    onPressed: () => setState(() => _isFullscreen = false),

                    child: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

      color: Colors.blueGrey[900],

      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.white70, size: 20),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  "Teacher's Audio Instructions",

                  style: TextStyle(color: Colors.white, fontSize: 14),

                  overflow: TextOverflow.ellipsis,
                ),
              ),

              if (_hasError)
                const Padding(
                  padding: EdgeInsets.only(left: 8),

                  child: Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,

              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),

            child: Slider(
              value: _position.inSeconds.toDouble(),

              min: 0,

              max: _duration.inSeconds.toDouble().clamp(0, double.infinity),

              onChanged: (value) {
                _audioPlayer.seek(Duration(seconds: value.toInt()));
              },

              activeColor: Colors.blue[300],

              inactiveColor: Colors.grey[600],
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              Text(
                _formatDuration(_position),

                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),

              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white70),

                    onPressed: () {
                      final newPos = _position - const Duration(seconds: 10);

                      _audioPlayer.seek(
                        newPos < Duration.zero ? Duration.zero : newPos,
                      );
                    },
                  ),

                  IconButton(
                    icon:
                        _isBuffering
                            ? const SizedBox(
                              width: 36,

                              height: 36,

                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                            : Icon(
                              _isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,

                              color: Colors.white,

                              size: 48,
                            ),

                    onPressed: _togglePlayback,
                  ),

                  IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white70),

                    onPressed: () {
                      _audioPlayer.seek(
                        _position + const Duration(seconds: 10),
                      );
                    },
                  ),
                ],
              ),

              Text(
                _formatDuration(_duration),

                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ImagePreviewWithAudioScreen extends StatefulWidget {
  final String imageUrl;
  final String? audioUrl;
  final String title;
  final Color primaryColor;

  const ImagePreviewWithAudioScreen({
    super.key,
    required this.imageUrl,
    this.audioUrl,
    required this.title,
    required this.primaryColor,
  });

  @override
  State<ImagePreviewWithAudioScreen> createState() =>
      _ImagePreviewWithAudioScreenState();
}

class _ImagePreviewWithAudioScreenState
    extends State<ImagePreviewWithAudioScreen> {
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isFullscreen = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  bool _isBuffering = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

Future<void> _initAudio() async {
  if (widget.audioUrl == null || widget.audioUrl!.isEmpty) return;

  try {
    // ── Modern just_audio syntax ──
    final audioSource = widget.audioUrl!.startsWith('http')
        ? AudioSource.uri(Uri.parse(widget.audioUrl!))
        : AudioSource.file(File(widget.audioUrl!) as String);

    await _audioPlayer.setAudioSource(audioSource, preload: true);
    await _audioPlayer.load();

    // Rest of the code remains the same...
    _audioPlayer.positionStream.listen((pos) { if (mounted) setState(() => _position = pos); });
    _audioPlayer.durationStream.listen((dur) { if (mounted) setState(() => _duration = dur ?? Duration.zero); });

    _audioPlayer.playerStateStream.listen((playerState) {
      if (!mounted) return;
      final playing = playerState.playing;
      final processing = playerState.processingState;
      setState(() {
        _isPlaying = playing && processing != ProcessingState.completed && processing != ProcessingState.idle;
        _isBuffering = processing == ProcessingState.buffering;
        _hasError = (processing == ProcessingState.idle && !playing && _duration > Duration.zero);
      });
    });
  } catch (e, stack) {
    debugPrint("Audio init failed: $e\n$stack");
    if (mounted) setState(() => _hasError = true);
  }
}
  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final imageWidget = InteractiveViewer(
      panEnabled: true,
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.5,
      maxScale: 4.0,
      child: Image.network(
        widget.imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('Failed to load image'),
              ],
            ),
          );
        },
      ),
    );

    return Scaffold(
      appBar:
          _isFullscreen
              ? null
              : AppBar(
                title: Text(widget.title),
                backgroundColor: widget.primaryColor,
                foregroundColor: Colors.white,
                actions: [
                  if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty)
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: () async {
                        if (_isPlaying) {
                          await _audioPlayer.pause();
                        } else {
                          await _audioPlayer.play();
                        }
                        setState(() => _isPlaying = !_isPlaying);
                      },
                    ),
                  IconButton(
                    icon: Icon(
                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                    onPressed:
                        () => setState(() => _isFullscreen = !_isFullscreen),
                  ),
                ],
              ),
      body: Stack(
        children: [
          _isFullscreen
              ? imageWidget
              : Column(
                children: [
                  if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty)
                    _buildAudioControls(),
                  Expanded(child: imageWidget),
                ],
              ),

          // Fullscreen exit button
          if (_isFullscreen)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.black.withOpacity(0.6),
                    onPressed: () => setState(() => _isFullscreen = false),
                    child: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioControls() {
    // Same audio control UI as in PDF version (you can extract to a shared widget)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.blueGrey[900],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Teacher's Audio Instructions",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _position.inSeconds.toDouble(),
              min: 0,
              max: _duration.inSeconds.toDouble().clamp(0, double.infinity),
              onChanged: (value) {
                _audioPlayer.seek(Duration(seconds: value.toInt()));
              },
              activeColor: Colors.blue[300],
              inactiveColor: Colors.grey[600],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white70),
                    onPressed: () {
                      final newPos = _position - const Duration(seconds: 10);
                      _audioPlayer.seek(
                        newPos < Duration.zero ? Duration.zero : newPos,
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 40,
                    ),
                    onPressed: () async {
                      if (_isPlaying) {
                        await _audioPlayer.pause();
                      } else {
                        await _audioPlayer.play();
                      }
                      setState(() => _isPlaying = !_isPlaying);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white70),
                    onPressed: () {
                      _audioPlayer.seek(
                        _position + const Duration(seconds: 10),
                      );
                    },
                  ),
                ],
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// FIXED: Separate widget for the preview screen to handle state properly
class _FilePreviewWithAudioScreen extends StatefulWidget {
  final File file;
  final String? fileType;
  final String? title;
  final bool allowAudioRecording;
  final Color primaryColor;

  const _FilePreviewWithAudioScreen({
    required this.file,
    required this.fileType,
    this.title,
    required this.allowAudioRecording,
    required this.primaryColor,
  });

  @override
  __FilePreviewWithAudioScreenState createState() =>
      __FilePreviewWithAudioScreenState();
}

class __FilePreviewWithAudioScreenState
    extends State<_FilePreviewWithAudioScreen> {
  final AudioRecorder _localAudioRecorder = AudioRecorder();
  final AudioPlayer _localAudioPlayer = AudioPlayer();
  bool _localIsRecording = false;
  String? _localAudioPath; // Persistent path for upload
  bool _localHasAudio = false;
  bool _localIsPlaying = false;
  Duration _localCurrentDuration = Duration.zero;
  Duration _localTotalDuration = Duration.zero;
  Timer? _localRecordingTimer;
  int _localRecordingSeconds = 0;

  // ADD THIS LINE - Flag to track if audio player is initialized
  bool _isAudioPlayerInitialized = false;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayerListeners();
  }

  @override
  void dispose() {
    // IMPORTANT: Stop and dispose audio player FIRST
    _stopLocalAudioPreview();
    _localAudioPlayer.dispose();

    // Stop recording if active
    if (_localIsRecording) {
      _localAudioRecorder.stop();
    }
    _localAudioRecorder.dispose();

    _localRecordingTimer?.cancel();

    // IMPORTANT: Only clean up if audio wasn't saved
    if (!_localHasAudio && _localAudioPath != null) {
      try {
        final file = File(_localAudioPath!);
        if (file.existsSync()) {
          file.deleteSync();
          debugPrint(
            '🗑️ [PREVIEW] Cleaned up unsaved audio: $_localAudioPath',
          );
        }
      } catch (e) {
        debugPrint('Error cleaning up audio: $e');
      }
    }

    super.dispose();
  }

  void _setupAudioPlayerListeners() {
    _localAudioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _localCurrentDuration = position;
        });
      }
    });

    _localAudioPlayer.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _localTotalDuration = duration ?? Duration.zero;
        });
      }
    });

    _localAudioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _localIsPlaying = false;
            _localCurrentDuration = Duration.zero;
          });
        }
      }
    });
  }

  void _startLocalRecordingTimer() {
    _localRecordingTimer?.cancel();
    _localRecordingSeconds = 0;
    _localRecordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _localRecordingSeconds = timer.tick;
        });
      }
    });
  }

  void _stopLocalRecordingTimer() {
    _localRecordingTimer?.cancel();
    _localRecordingTimer = null;
  }

  Future<void> _startLocalRecording() async {
    try {
      // IMPORTANT: Stop audio player completely before recording
      await _stopLocalAudioPreview();

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final hasPermission = await _localAudioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission required'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Use Application Documents Directory for persistent storage
      final dir = await getApplicationDocumentsDirectory();
      final persistentDir = Directory('${dir.path}/teacher_preview_audio');

      if (!await persistentDir.exists()) {
        await persistentDir.create(recursive: true);
      }

      final filePath =
          '${persistentDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _localAudioRecorder.start(const RecordConfig(), path: filePath);

      setState(() {
        _localIsRecording = true;
        _localAudioPath = filePath;
        _localHasAudio = false;
        _isAudioPlayerInitialized = false;
      });

      _startLocalRecordingTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.mic, color: Colors.white),
                SizedBox(width: 8),
                Text('Recording audio instructions...'),
              ],
            ),
            backgroundColor: widget.primaryColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting audio recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopLocalRecording() async {
    try {
      final path = await _localAudioRecorder.stop();
      _stopLocalRecordingTimer();

      setState(() {
        _localIsRecording = false;
      });

      if (path != null) {
        try {
          // The file is already in persistent storage
          final audioFile = File(_localAudioPath!);
          if (!await audioFile.exists()) {
            throw Exception('Audio file was not saved properly');
          }

          // IMPORTANT: Initialize audio player with the file
          await _initializeAudioPlayer();

          setState(() {
            _localHasAudio = true;
          });

          // Debug: print file info
          final fileSize = await audioFile.length();
          debugPrint(
            '✅ [TEACHER_PREVIEW] Audio saved: $_localAudioPath, Size: $fileSize bytes',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Audio recording saved successfully!'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (e) {
          debugPrint('Error saving audio: $e');
          setState(() {
            _localHasAudio = false;
            _localAudioPath = null;
            _isAudioPlayerInitialized = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save recording: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error stopping audio recording: $e');
    }
  }

  Future<void> _playLocalAudioPreview() async {
    if (_localAudioPath == null) return;

    final file = File(_localAudioPath!);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio file not found. Please record again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _localHasAudio = false;
        _localAudioPath = null;
        _isAudioPlayerInitialized = false;
      });
      return;
    }

    try {
      // Initialize if not already initialized
      if (!_isAudioPlayerInitialized) {
        await _initializeAudioPlayer();
      }

      // Stop any current playback and reset
      await _stopLocalAudioPreview();
      await Future.delayed(const Duration(milliseconds: 50));

      await _localAudioPlayer.seek(Duration.zero);
      setState(() {
        _localIsPlaying = true;
        _localCurrentDuration = Duration.zero;
      });

      await _localAudioPlayer.play();
    } catch (e) {
      debugPrint('Error playing audio preview: $e');
      setState(() => _localIsPlaying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pauseLocalAudioPreview() async {
    try {
      await _localAudioPlayer.pause();
      setState(() => _localIsPlaying = false);
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }

  Future<void> _stopLocalAudioPreview() async {
    try {
      if (_isAudioPlayerInitialized) {
        await _localAudioPlayer.stop();
        await _localAudioPlayer.seek(Duration.zero);
      }
      setState(() {
        _localIsPlaying = false;
        _localCurrentDuration = Duration.zero;
      });
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  String _formatRecordingTimer(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  String _formatAudioDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'File Preview'),
        backgroundColor: widget.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (widget.allowAudioRecording &&
              (widget.fileType == 'pdf' || widget.fileType == 'image')) ...[
            IconButton(
              icon: Icon(_localIsRecording ? Icons.stop : Icons.mic),
              onPressed:
                  _localIsRecording
                      ? _stopLocalRecording
                      : _startLocalRecording,
              tooltip: _localIsRecording ? 'Stop Recording' : 'Start Recording',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Audio recording section (only for new file previews)
          if (widget.allowAudioRecording &&
              (widget.fileType == 'pdf' || widget.fileType == 'image')) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.record_voice_over,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Add Reading Instructions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                      const Spacer(),
                      if (_localIsRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            _formatRecordingTimer(_localRecordingSeconds),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Audio player when recording exists
                  if (_localHasAudio && _localAudioPath != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[100]!),
                      ),
                      child: Column(
                        children: [
                          Slider(
                            value: _localCurrentDuration.inSeconds.toDouble(),
                            min: 0,
                            max: _localTotalDuration.inSeconds.toDouble().clamp(
                              0,
                              _localTotalDuration.inSeconds.toDouble(),
                            ),
                            onChanged: (value) {
                              _localAudioPlayer.seek(
                                Duration(seconds: value.toInt()),
                              );
                            },
                            activeColor: Colors.blue,
                            inactiveColor: Colors.blue.withOpacity(0.3),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatAudioDuration(_localCurrentDuration),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Iconsax.previous,
                                      size: 20,
                                    ),
                                    onPressed:
                                        () => _localAudioPlayer.seek(
                                          Duration.zero,
                                        ),
                                    tooltip: 'Restart',
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _localIsPlaying
                                          ? Iconsax.pause
                                          : Iconsax.play,
                                      size: 24,
                                      color: Colors.blue,
                                    ),
                                    onPressed:
                                        _localIsPlaying
                                            ? _pauseLocalAudioPreview
                                            : _playLocalAudioPreview,
                                    tooltip: _localIsPlaying ? 'Pause' : 'Play',
                                  ),
                                  IconButton(
                                    icon: const Icon(Iconsax.stop, size: 20),
                                    onPressed: _stopLocalAudioPreview,
                                    tooltip: 'Stop',
                                  ),
                                ],
                              ),
                              Text(
                                _formatAudioDuration(_localTotalDuration),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // Recording status
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          _localIsRecording
                              ? Colors.red.withOpacity(0.1)
                              : _localHasAudio
                              ? Colors.green.withOpacity(0.1)
                              : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _localIsRecording
                              ? Icons.circle
                              : _localHasAudio
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color:
                              _localIsRecording
                                  ? Colors.red
                                  : _localHasAudio
                                  ? Colors.green
                                  : Colors.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _localIsRecording
                                ? 'Recording in progress...'
                                : _localHasAudio
                                ? 'Audio recording saved! (Persistent)'
                                : 'Record audio instructions for students',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  _localIsRecording
                                      ? Colors.red[800]
                                      : _localHasAudio
                                      ? Colors.green[800]
                                      : Colors.blue[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // File preview
          Expanded(
            child:
                widget.fileType == 'pdf'
                    ? SfPdfViewer.file(widget.file)
                    : Center(
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: Image.file(widget.file, fit: BoxFit.contain),
                      ),
                    ),
          ),
        ],
      ),
      floatingActionButton:
          widget.allowAudioRecording && _localHasAudio && !_localIsRecording
              ? FloatingActionButton(
                onPressed: () async {
                  // IMPORTANT: Stop audio player before returning
                  await _stopLocalAudioPreview();

                  // Return the persistent audio path when navigating back
                  if (_localAudioPath != null) {
                    final file = File(_localAudioPath!);
                    if (await file.exists()) {
                      // Add a small delay to ensure audio player is fully stopped
                      await Future.delayed(const Duration(milliseconds: 100));
                      Navigator.pop(context, _localAudioPath);
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Audio file not found. Please record again.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Icon(Icons.check),
                backgroundColor: Colors.green,
              )
              : null,
    );
  }

  Future<void> _initializeAudioPlayer() async {
    if (_localAudioPath == null || _isAudioPlayerInitialized) return;

    try {
      final file = File(_localAudioPath!);
      if (!await file.exists()) {
        throw Exception('Audio file not found');
      }

      await _localAudioPlayer.setFilePath(_localAudioPath!);
      final duration = await _localAudioPlayer.duration;

      setState(() {
        _localTotalDuration = duration ?? Duration.zero;
        _isAudioPlayerInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing audio player: $e');
      throw e;
    }
  }
}

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

// ---------------------------------------------------------------------------
// Audio File Manager
// ---------------------------------------------------------------------------

class _AudioFileManager {
  static Future<void> cleanupOldRecordings({int keepLast = 5}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/teacher_recordings');
      if (!await dir.exists()) return;

      final files = (await dir.list().toList()).whereType<File>().toList();
      if (files.length <= keepLast) return;

      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      for (int i = keepLast; i < files.length; i++) {
        try {
          await files[i].delete();
        } catch (e) {
          debugPrint('⚠️ [AUDIO_MANAGER] Failed to delete old file: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AUDIO_MANAGER] Cleanup error: $e');
    }
  }

  static Future<bool> isFileValid(File file) async {
    try {
      if (!await file.exists()) {
        debugPrint('❌ [FILE_VALIDATION] Does not exist: ${file.path}');
        return false;
      }
      final length = await file.length();
      if (length == 0) {
        debugPrint('❌ [FILE_VALIDATION] Empty file: ${file.path}');
        return false;
      }
      debugPrint('✅ [FILE_VALIDATION] Valid: ${file.path} ($length bytes)');
      return true;
    } catch (e) {
      debugPrint('❌ [FILE_VALIDATION] Error: $e');
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Page widget
// ---------------------------------------------------------------------------

class TeacherReadingMaterialsPage extends StatefulWidget {
  const TeacherReadingMaterialsPage({super.key, this.classId, this.onWillPop});

  final String? classId;
  final VoidCallback? onWillPop;

  @override
  State<TeacherReadingMaterialsPage> createState() =>
      _TeacherReadingMaterialsPageState();
}

class _TeacherReadingMaterialsPageState
    extends State<TeacherReadingMaterialsPage> {
  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  final _supabase = Supabase.instance.client;
  final _scrollController = ScrollController();

  List<ReadingMaterial> _materials = [];
  List<Map<String, dynamic>> _readingLevels = [];
  bool _isLoading = true;
  String? _className;

  // — Audio recording —
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecordingAudio = false;
  bool _hasAudioRecording = false;
  String? _audioRecordingPath;
  String? _uploadedAudioUrl;
  bool _isPlayingAudioPreview = false;
  Duration _audioCurrentDuration = Duration.zero;
  Duration _audioTotalDuration = Duration.zero;
  Timer? _audioRecordingTimer;
  int _audioRecordingSeconds = 0;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _cleanupOldTempFiles();
    _cleanupUploadedFiles();
    _loadData();
    _setupAudioPlayerListeners();
    _AudioFileManager.cleanupOldRecordings();
    _cleanupOldPreviewAudio();
  }

  @override
  void dispose() {
    _scrollController.dispose();

    // ✅ FIX: Release resources directly — NO setState allowed in dispose().
    _audioRecordingTimer?.cancel();

    // Stop recording silently if still active.
    if (_isRecordingAudio) {
      _audioRecorder.stop().catchError((_) {});
    }

    _audioRecorder.dispose();

    // Stop & dispose the player without touching widget state.
    _audioPlayer.stop().catchError((_) {});
    _audioPlayer.dispose();

    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Audio setup
  // -------------------------------------------------------------------------

  void _setupAudioPlayerListeners() {
    _audioPlayer.positionStream.listen((position) {
      if (mounted) setState(() => _audioCurrentDuration = position);
    });

    _audioPlayer.durationStream.listen((duration) {
      if (mounted) setState(() => _audioTotalDuration = duration ?? Duration.zero);
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted && state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlayingAudioPreview = false;
          _audioCurrentDuration = Duration.zero;
        });
      }
    });
  }

  void _stopAudioRecordingTimer() {
    _audioRecordingTimer?.cancel();
    _audioRecordingTimer = null;
  }

  // -------------------------------------------------------------------------
  // Data loading
  // -------------------------------------------------------------------------

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadReadingLevels(),
        _loadMaterials(),
        if (widget.classId != null) _loadClassName(),
      ]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClassName() async {
    try {
      final response = await _supabase
          .from('class_rooms')
          .select('class_name')
          .eq('id', widget.classId!)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() => _className = response['class_name'] as String?);
      }
    } catch (e) {
      debugPrint('❌ [MATERIALS] Error loading classroom name: $e');
    }
  }

  Future<void> _loadReadingLevels() async {
    try {
      final levels = await ReadingMaterialsService.getAllReadingLevels();
      if (mounted) setState(() => _readingLevels = levels);
    } catch (e) {
      debugPrint('❌ [MATERIALS] Error loading reading levels: $e');
    }
  }

  Future<void> _loadMaterials() async {
    try {
      final materials = widget.classId != null
          ? await ReadingMaterialsService.getReadingMaterialsByClassroom(
              widget.classId!)
          : await ReadingMaterialsService.getAllReadingMaterials();

      if (mounted) setState(() => _materials = materials ?? []);
    } catch (e) {
      debugPrint('❌ [MATERIALS] Error loading materials: $e');
      if (mounted) setState(() => _materials = []);
    }
  }

  Future<List<Map<String, dynamic>>> _loadAvailablePrerequisites({
    String? excludeMaterialId,
  }) async {
    try {
      final materials = widget.classId != null
          ? await ReadingMaterialsService.getReadingMaterialsByClassroom(
              widget.classId!)
          : await ReadingMaterialsService.getAllReadingMaterials();

      return (materials ?? [])
          .where((m) => m.id != excludeMaterialId)
          .map((m) => {'id': m.id, 'title': m.title, 'level': m.levelNumber ?? 'N/A'})
          .toList();
    } catch (e) {
      debugPrint('❌ [MATERIALS] Error loading prerequisites: $e');
      return [];
    }
  }

  Future<void> _handleRefresh() => _loadData();

  // -------------------------------------------------------------------------
  // Audio recording (called from UI — setState is safe here)
  // -------------------------------------------------------------------------

  /// Resets audio recording state. Safe to call from UI callbacks only.
  /// ⚠️  Do NOT call this from dispose().
  void _clearAudioRecording() {
    if (_isRecordingAudio) {
      _audioRecorder.stop().catchError((_) {});
      _stopAudioRecordingTimer();
    }

    // Safe: this is only called while widget is still mounted (from dialog/button)
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

    _audioPlayer.stop().catchError((_) {});
  }

  // -------------------------------------------------------------------------
  // File helpers
  // -------------------------------------------------------------------------

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
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
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

  /// Saves a picked file to the persistent app documents directory.
  Future<File?> _saveToPersistentStorage(
    String originalPath,
    String fileName,
  ) async {
    final bytes = await File(originalPath).readAsBytes();
    debugPrint('📁 [FILE_PICKER] Loaded ${bytes.length} bytes from $originalPath');

    final appDir = await getApplicationDocumentsDirectory();
    final persistentDir = Directory('${appDir.path}/teacher_uploads');
    if (!await persistentDir.exists()) {
      await persistentDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dest = File('${persistentDir.path}/persistent_${timestamp}_$fileName');
    await dest.writeAsBytes(bytes);

    debugPrint('📁 [FILE_PICKER] Saved to: ${dest.path} (${await dest.length()} bytes)');
    return dest;
  }

  // -------------------------------------------------------------------------
  // File preview with audio
  // -------------------------------------------------------------------------

  Future<String?> _showFilePreviewWithAudio(
    File file,
    String? fileType, {
    String? title,
    bool allowAudioRecording = false,
  }) async {
    try {
      final audioPath = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => _FilePreviewWithAudioScreen(
            file: file,
            fileType: fileType,
            title: title,
            allowAudioRecording: allowAudioRecording,
            primaryColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

      // Brief delay so the screen's audio resources are fully released.
      await Future.delayed(const Duration(milliseconds: 200));
      return audioPath;
    } catch (e) {
      debugPrint('❌ [PREVIEW] Error: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Upload dialog
  // -------------------------------------------------------------------------

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
    final isEditMode = materialToEdit != null;

    if (isEditMode) {
      titleController.text = materialToEdit!.title;
      descriptionController.text = materialToEdit.description ?? '';
      selectedLevelId = materialToEdit.levelId;
      hasPrerequisite = materialToEdit.prerequisiteId != null;
      selectedPrerequisiteId = materialToEdit.prerequisiteId;
    }

    final availablePrerequisites = await _loadAvailablePrerequisites(
      excludeMaterialId: isEditMode ? materialToEdit!.id : null,
    );

    // Reset audio state (safe — still mounted at this point).
    _clearAudioRecording();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // ------------------------------------------------------------------
          // Helpers scoped to the dialog
          // ------------------------------------------------------------------

          Future<void> pickFile(FileType type) async {
            final result = await FilePicker.platform.pickFiles(
              type: type,
              allowedExtensions: type == FileType.custom ? ['pdf'] : null,
            );
            if (result == null || result.files.single.path == null) return;

            try {
              final saved = await _saveToPersistentStorage(
                result.files.single.path!,
                result.files.single.name,
              );
              if (saved != null) {
                setDialogState(() {
                  selectedFile = saved;
                  fileType = type == FileType.custom ? 'pdf' : 'image';
                });
              }
            } catch (e) {
              debugPrint('❌ [FILE_PICKER] $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error saving file: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }

          // ------------------------------------------------------------------
          // Dialog UI
          // ------------------------------------------------------------------

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            insetPadding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24)),
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
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 24),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // ── Content ──
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Classroom badge
                          if (widget.classId != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue[200]!,
                                    width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.class_rounded,
                                      color: Colors.blue[700], size: 20),
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

                          // Reading level dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                              items: _readingLevels.map((level) {
                                return DropdownMenuItem(
                                  value: level['id'] as String,
                                  child: Text(
                                    'Level ${level['level_number']}: ${level['title']}',
                                    style:
                                        TextStyle(color: Colors.blueGrey[800]),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) =>
                                  setDialogState(() => selectedLevelId = v),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Prerequisite toggle
                          _buildPrerequisiteSection(
                            setDialogState: setDialogState,
                            primaryColor: primaryColor,
                            hasPrerequisite: hasPrerequisite,
                            selectedPrerequisiteId: selectedPrerequisiteId,
                            availablePrerequisites: availablePrerequisites,
                            onToggle: (v) {
                              setDialogState(() {
                                hasPrerequisite = v;
                                if (!v) selectedPrerequisiteId = null;
                              });
                            },
                            onPrerequisiteSelected: (v) => setDialogState(
                                () => selectedPrerequisiteId = v),
                          ),
                          const SizedBox(height: 20),

                          // File section
                          if (!isEditMode)
                            _buildFileUploadSection(
                              setDialogState: setDialogState,
                              primaryColor: primaryColor,
                              selectedFile: selectedFile,
                              fileType: fileType,
                              titleController: titleController,
                              onPickPdf: () => pickFile(FileType.custom),
                              onPickImage: () => pickFile(FileType.image),
                              onRemoveFile: () => setDialogState(() {
                                selectedFile = null;
                                fileType = null;
                              }),
                              onAudioAdded: (path) => setDialogState(() {
                                _audioRecordingPath = path;
                                _hasAudioRecording = true;
                              }),
                              onAudioRemoved: () => setDialogState(() {
                                _hasAudioRecording = false;
                                _audioRecordingPath = null;
                              }),
                              hasAudioRecording: _hasAudioRecording,
                              audioRecordingPath: _audioRecordingPath,
                            )
                          else
                            _buildCurrentFileInfo(materialToEdit!),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // ── Actions ──
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                          top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: Colors.grey[400]!),
                            ),
                            child: const Text('Cancel',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: isEditMode
                                ? _canSubmitEdit(
                                        selectedLevelId,
                                        titleController,
                                        hasPrerequisite,
                                        selectedPrerequisiteId)
                                    ? () async {
                                        Navigator.pop(context);
                                        await _updateMaterial(
                                          materialId: materialToEdit!.id,
                                          title: titleController.text.trim(),
                                          levelId: selectedLevelId!,
                                          description: _emptyToNull(
                                              descriptionController.text),
                                          prerequisiteId: hasPrerequisite
                                              ? selectedPrerequisiteId
                                              : null,
                                        );
                                      }
                                    : null
                                : _canSubmitUpload(
                                        selectedFile,
                                        selectedLevelId,
                                        titleController,
                                        hasPrerequisite,
                                        selectedPrerequisiteId)
                                    ? () async {
                                        Navigator.pop(context);
                                        await _handleUploadAction(
                                          selectedFile: selectedFile!,
                                          title: titleController.text.trim(),
                                          levelId: selectedLevelId!,
                                          description: _emptyToNull(
                                              descriptionController.text),
                                          prerequisiteId: hasPrerequisite
                                              ? selectedPrerequisiteId
                                              : null,
                                        );
                                      }
                                    : null,
                            child: Text(
                              isEditMode ? 'Update' : 'Upload',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
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

  // -------------------------------------------------------------------------
  // Dialog sub-sections (extracted for readability)
  // -------------------------------------------------------------------------

  bool _canSubmitEdit(
    String? levelId,
    TextEditingController title,
    bool hasPrereq,
    String? prereqId,
  ) {
    return levelId != null &&
        title.text.trim().isNotEmpty &&
        (!hasPrereq || prereqId != null);
  }

  bool _canSubmitUpload(
    File? file,
    String? levelId,
    TextEditingController title,
    bool hasPrereq,
    String? prereqId,
  ) {
    return file != null &&
        levelId != null &&
        title.text.trim().isNotEmpty &&
        (!hasPrereq || prereqId != null);
  }

  String? _emptyToNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Widget _buildPrerequisiteSection({
    required StateSetter setDialogState,
    required Color primaryColor,
    required bool hasPrerequisite,
    required String? selectedPrerequisiteId,
    required List<Map<String, dynamic>> availablePrerequisites,
    required ValueChanged<bool> onToggle,
    required ValueChanged<String?> onPrerequisiteSelected,
  }) {
    return Container(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline,
                      color: hasPrerequisite ? primaryColor : Colors.grey,
                      size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Add Prerequisite',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: hasPrerequisite ? primaryColor : Colors.grey[700],
                    ),
                  ),
                ],
              ),
              Switch(
                value: hasPrerequisite,
                onChanged: onToggle,
                activeColor: primaryColor,
                inactiveTrackColor: Colors.grey[300],
              ),
            ],
          ),
          if (hasPrerequisite) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Select Prerequisite *',
                  border: InputBorder.none,
                  labelStyle: TextStyle(color: primaryColor),
                  hintText: 'Choose a material',
                ),
                value: selectedPrerequisiteId,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Select a material',
                        style: TextStyle(color: Colors.grey[600])),
                  ),
                  ...availablePrerequisites.map((m) => DropdownMenuItem(
                        value: m['id'] as String,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['title'] as String,
                                style: TextStyle(color: Colors.blueGrey[800])),
                            Text('Level ${m['level']}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      )),
                ],
                onChanged: onPrerequisiteSelected,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Students must complete this prerequisite before accessing the new material',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileUploadSection({
    required StateSetter setDialogState,
    required Color primaryColor,
    required File? selectedFile,
    required String? fileType,
    required TextEditingController titleController,
    required VoidCallback onPickPdf,
    required VoidCallback onPickImage,
    required VoidCallback onRemoveFile,
    required ValueChanged<String> onAudioAdded,
    required VoidCallback onAudioRemoved,
    required bool hasAudioRecording,
    required String? audioRecordingPath,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // File type icon
          if (fileType == 'pdf')
            Icon(Icons.picture_as_pdf, size: 40, color: Colors.red[600])
          else if (fileType == 'image')
            Icon(Icons.image, size: 40, color: Colors.green[600])
          else
            Icon(Icons.insert_drive_file, size: 40, color: primaryColor),
          const SizedBox(height: 12),

          // Pick buttons
          Row(
            children: [
              Expanded(
                child: _filePickButton(
                  label: 'PDF',
                  icon: Icons.picture_as_pdf,
                  bgColor: Colors.red[50]!,
                  fgColor: Colors.red[700]!,
                  borderColor: Colors.red[200]!,
                  onPressed: onPickPdf,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _filePickButton(
                  label: 'Image',
                  icon: Icons.image,
                  bgColor: Colors.green[50]!,
                  fgColor: Colors.green[700]!,
                  borderColor: Colors.green[200]!,
                  onPressed: onPickImage,
                ),
              ),
            ],
          ),

          // Selected file info
          if (selectedFile != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fileType == 'pdf' ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      fileType == 'pdf' ? Colors.red[200]! : Colors.green[200]!,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image,
                        color: fileType == 'pdf'
                            ? Colors.red[600]
                            : Colors.green[600],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _truncateFileName(
                                  selectedFile.path.split('/').last),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: fileType == 'pdf'
                                    ? Colors.red[700]
                                    : Colors.green[700],
                              ),
                            ),
                            Text(
                              fileType == 'pdf' ? 'PDF Document' : 'Image File',
                              style: TextStyle(
                                fontSize: 12,
                                color: fileType == 'pdf'
                                    ? Colors.red[600]
                                    : Colors.green[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.remove_red_eye,
                                size: 20, color: primaryColor),
                            tooltip: 'Preview & Add Audio',
                            onPressed: () async {
                              try {
                                final audioPath =
                                    await _showFilePreviewWithAudio(
                                  selectedFile,
                                  fileType,
                                  title: titleController.text.trim(),
                                  allowAudioRecording: true,
                                );
                                if (audioPath != null) {
                                  final isValid =
                                      await _AudioFileManager.isFileValid(
                                          File(audioPath));
                                  if (isValid) {
                                    onAudioAdded(audioPath);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Audio instructions added successfully'),
                                        backgroundColor: Colors.green,
                                      ));
                                    }
                                  } else {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Audio file is invalid. Please record again.'),
                                        backgroundColor: Colors.red,
                                      ));
                                    }
                                  }
                                }
                              } catch (e) {
                                debugPrint('❌ [PREVIEW] $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: Colors.grey),
                            onPressed: onRemoveFile,
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
                        fontStyle: FontStyle.italic),
                  ),

                  // Audio badge
                  if (hasAudioRecording && audioRecordingPath != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Text('Audio instructions added',
                              style: TextStyle(
                                  color: Colors.green[700], fontSize: 12)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: Colors.red),
                            onPressed: onAudioRemoved,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
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
            Text('Select PDF or Image file',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _filePickButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color fgColor,
    required Color borderColor,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
      ),
    );
  }

  Widget _buildCurrentFileInfo(ReadingMaterial material) {
    final isPdf = material.fileUrl.toLowerCase().endsWith('.pdf');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(isPdf ? Icons.picture_as_pdf : Icons.image,
              color: isPdf ? Colors.red[600] : Colors.green[600], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current File',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.grey[700])),
                Text(
                  material.fileUrl.split('/').last,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Cannot Change',
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Upload / update
  // -------------------------------------------------------------------------

  Future<void> _handleUploadAction({
    required File selectedFile,
    required String title,
    required String levelId,
    String? description,
    String? prerequisiteId,
  }) async {
    debugPrint('📁 [UPLOAD_DIALOG] File: ${selectedFile.path}');
    debugPrint('📁 [UPLOAD_DIALOG] Audio: $_audioRecordingPath');

    File? audioFile;
    if (_hasAudioRecording && _audioRecordingPath != null) {
      audioFile = File(_audioRecordingPath!);
      final isValid = await _AudioFileManager.isFileValid(audioFile);
      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Audio file is invalid. Please record again.'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
    }

    await _uploadMaterial(
      file: selectedFile,
      title: title,
      levelId: levelId,
      description: description,
      prerequisiteId: prerequisiteId,
      audioFile: audioFile,
    );
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

    if (audioFile != null) {
      if (!await audioFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Audio file was deleted. Please record again.'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
      final size = await audioFile.length();
      if (size == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Audio file is empty. Please record again.'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
      debugPrint('✅ [UPLOAD] Audio validated: ${audioFile.path} ($size bytes)');
    }

    _showProgressDialog(
      widget.classId != null
          ? 'Uploading Classroom Material...'
          : 'Uploading Material...',
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

      _dismissProgressDialog();
      if (!mounted) return;

      if (result != null && !result.containsKey('error')) {
        setState(() {
          _hasAudioRecording = false;
          _audioRecordingPath = null;
        });
        await _cleanupPreviewAudioAfterUpload();
        _showSuccessSnackBar(widget.classId != null
            ? 'Classroom material uploaded successfully!'
            : 'Material uploaded successfully!');
        await _loadMaterials();
      } else {
        _showErrorSnackBar(result?['error'] ?? 'Upload failed');
      }
    } catch (e) {
      _dismissProgressDialog();
      if (!mounted) return;
      debugPrint('❌ [UPLOAD] $e');
      _showErrorSnackBar('Upload error: $e');
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

    _showProgressDialog('Updating Material...');

    try {
      final success = await ReadingMaterialsService.updateReadingMaterial(
        materialId: materialId,
        title: title,
        description: description,
        levelId: levelId,
        classRoomId: widget.classId,
        prerequisiteId: prerequisiteId,
      );

      _dismissProgressDialog();
      if (!mounted) return;

      if (success) {
        _showSuccessSnackBar('Material updated successfully!');
        await _loadMaterials();
      } else {
        _showErrorSnackBar('Failed to update material');
      }
    } catch (e) {
      _dismissProgressDialog();
      if (!mounted) return;
      _showErrorSnackBar('Error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Snackbar / dialog helpers
  // -------------------------------------------------------------------------

  void _showProgressDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(message,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dismissProgressDialog() {
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text(message),
      ]),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  // -------------------------------------------------------------------------
  // Assign materials
  // -------------------------------------------------------------------------

  Future<void> _showAssignMaterialsDialog() async {
    if (widget.classId == null) return;

    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    setState(() => _isLoading = true);
    final unassignedMaterials =
        await ReadingMaterialsService.getUnassignedReadingMaterials(
            classroomId: widget.classId!);
    setState(() => _isLoading = false);

    if (unassignedMaterials.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No unassigned materials available'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ));
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedMaterials = <String>{};

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            insetPadding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.add_to_photos,
                            color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Assign Existing Materials',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: unassignedMaterials.length,
                      itemBuilder: (context, index) {
                        final material = unassignedMaterials[index];
                        final isSelected =
                            selectedMaterials.contains(material.id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: CheckboxListTile(
                            title: Text(material.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Level ${material.levelNumber ?? 'N/A'}',
                                    style: const TextStyle(fontSize: 12)),
                                if (material.description != null)
                                  Text(material.description!,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                            secondary: Icon(
                              material.fileUrl.toLowerCase().endsWith('.pdf')
                                  ? Icons.picture_as_pdf
                                  : Icons.image,
                              color: primaryColor,
                            ),
                            value: isSelected,
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) {
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20)),
                      border:
                          Border(top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedMaterials.isEmpty
                                ? null
                                : () async {
                                    await _assignMaterialsToClassroom(
                                        materialIds:
                                            selectedMaterials.toList());
                                    Navigator.pop(context);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                                'Assign (${selectedMaterials.length})',
                                style: const TextStyle(color: Colors.white)),
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

  Future<void> _assignMaterialsToClassroom(
      {required List<String> materialIds}) async {
    if (widget.classId == null) return;

    int successCount = 0;
    int failCount = 0;

    for (final id in materialIds) {
      final ok = await ReadingMaterialsService.assignMaterialToClassroom(
        materialId: id,
        classroomId: widget.classId!,
      );
      ok ? successCount++ : failCount++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Assigned $successCount materials. Failed: $failCount'),
        backgroundColor: successCount > 0 ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ));
      if (successCount > 0) await _loadMaterials();
    }
  }

  // -------------------------------------------------------------------------
  // Delete material
  // -------------------------------------------------------------------------

  Future<void> _deleteMaterial(ReadingMaterial material) async {
    if (widget.classId != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Remove Material'),
          content: Text(
              'Do you want to remove "${material.title}" from this classroom, or delete it entirely?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete Permanently',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (action == 'remove') {
        final ok = await ReadingMaterialsService.removeMaterialFromClassroom(
          materialId: material.id,
          classroomId: widget.classId!,
        );
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Material removed from classroom'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ));
          await _loadMaterials();
        }
        return;
      } else if (action != 'delete') {
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
            'Are you sure you want to permanently delete "${material.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok =
        await ReadingMaterialsService.deleteReadingMaterial(material.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Material deleted successfully' : 'Failed to delete material'),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ));
      if (ok) await _loadMaterials();
    }
  }

  // -------------------------------------------------------------------------
  // Submissions
  // -------------------------------------------------------------------------

  Future<void> _viewSubmissions(ReadingMaterial material) async {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final submissions =
        await ReadingMaterialsService.getSubmissionsForMaterial(material.id);
    if (!mounted) return;

    final audioPlayer = AudioPlayer();
    String? playingUrl;
    bool isPlaying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * (isMobile ? 0.9 : 0.8),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.people,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Submissions for "${material.title}"',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 24, color: Colors.white),
                        onPressed: () {
                          audioPlayer.dispose();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),

                // Body
                Expanded(
                  child: Container(
                    color: Colors.grey[50],
                    child: submissions.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.assignment_outlined,
                                      size: isMobile ? 60 : 80,
                                      color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text('No submissions yet',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: isMobile ? 16 : 18,
                                          fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Students haven't submitted recordings for this material",
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: isMobile ? 12 : 14),
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
                              final student = submission['students']
                                  as Map<String, dynamic>?;
                              final recordingUrl =
                                  submission['recording_url'] as String? ??
                                      submission['file_url'] as String?;
                              final isThisPlaying =
                                  playingUrl == recordingUrl;
                              final needsGrading =
                                  submission['needs_grading'] == true;
                              final profilePic =
                                  student?['profile_picture'] as String?;
                              final formattedDate = _formatSubmissionDate(
                                submission['created_at'] ??
                                    submission['recorded_at'],
                              );

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  elevation: 1,
                                  color: Colors.white,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: _buildStudentAvatar(
                                      studentName: student?['student_name']
                                          as String?,
                                      profilePic: profilePic,
                                      primaryColor: primaryColor,
                                    ),
                                    title: Text(
                                      student?['student_name'] ?? 'Unknown',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey[800]),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Submitted: $formattedDate',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600])),
                                        if (needsGrading) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange[100],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text('Needs Grading',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.orange[800],
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    trailing: recordingUrl != null
                                        ? _buildPlayButton(
                                            isThisPlaying: isThisPlaying,
                                            isPlaying: isPlaying,
                                            primaryColor: primaryColor,
                                            onPressed: () async {
                                              try {
                                                if (isThisPlaying && isPlaying) {
                                                  await audioPlayer.stop();
                                                  setModalState(() {
                                                    isPlaying = false;
                                                    playingUrl = null;
                                                  });
                                                } else {
                                                  if (playingUrl != null) {
                                                    await audioPlayer.stop();
                                                  }
                                                  await audioPlayer.setUrl(
                                                      recordingUrl!);
                                                  await audioPlayer.play();
                                                  setModalState(() {
                                                    playingUrl = recordingUrl;
                                                    isPlaying = true;
                                                  });
                                                  audioPlayer.playerStateStream
                                                      .listen((s) {
                                                    if (s.processingState ==
                                                        ProcessingState
                                                            .completed) {
                                                      setModalState(() {
                                                        isPlaying = false;
                                                        playingUrl = null;
                                                      });
                                                    }
                                                  });
                                                }
                                              } catch (e) {
                                                debugPrint(
                                                    '❌ [AUDIO] Play error: $e');
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(SnackBar(
                                                    content: Text(
                                                        'Error playing audio: $e'),
                                                    backgroundColor: Colors.red,
                                                  ));
                                                }
                                              }
                                            },
                                          )
                                        : Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(Icons.error,
                                                size: 20,
                                                color: Colors.grey[500]),
                                          ),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
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

  Widget _buildPlayButton({
    required bool isThisPlaying,
    required bool isPlaying,
    required Color primaryColor,
    required VoidCallback onPressed,
  }) {
    final active = isThisPlaying && isPlaying;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: active ? primaryColor : primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconButton(
        icon: Icon(
          active ? Icons.stop : Icons.play_arrow,
          color: active ? Colors.white : primaryColor,
          size: 20,
        ),
        onPressed: onPressed,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Student avatar
  // -------------------------------------------------------------------------

  Widget _buildStudentAvatar({
    required String? studentName,
    required String? profilePic,
    required Color primaryColor,
  }) {
    final initials =
        (studentName?.isNotEmpty == true) ? studentName![0].toUpperCase() : 'U';

    final fallback = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
      child: Center(
          child: Text(initials,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                  fontSize: 16))),
    );

    if (profilePic == null || profilePic.isEmpty) return fallback;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: primaryColor.withOpacity(0.2), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.network(
          profilePic,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: Colors.grey[100], shape: BoxShape.circle),
              child: Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                  color: primaryColor,
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Formatting
  // -------------------------------------------------------------------------

  String _formatSubmissionDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown date';
    try {
      final date = DateTime.parse(dateString);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
      if (diff.inHours < 24) return '${diff.inHours} hours ago';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return DateFormat('MMM d, y • h:mm a').format(date.toLocal());
    } catch (e) {
      return 'Invalid date';
    }
  }

  String _formatDuration(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(duration.inMinutes.remainder(60))}:${two(duration.inSeconds.remainder(60))}';
  }

  // -------------------------------------------------------------------------
  // Material list item
  // -------------------------------------------------------------------------

  Widget _buildMaterialItem(ReadingMaterial material, int index) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final isPdf = material.fileUrl.toLowerCase().endsWith('.pdf');
    final isImage = material.fileUrl.toLowerCase().endsWith('.jpg') ||
        material.fileUrl.toLowerCase().endsWith('.jpeg') ||
        material.fileUrl.toLowerCase().endsWith('.png');

    final Color iconBg;
    final IconData fileIcon;
    if (isPdf) {
      iconBg = Colors.red[600]!;
      fileIcon = Icons.picture_as_pdf;
    } else if (isImage) {
      iconBg = Colors.green[600]!;
      fileIcon = Icons.image;
    } else {
      iconBg = primaryColor;
      fileIcon = Icons.insert_drive_file;
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
                color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(fileIcon, color: Colors.white,
                size: isMobile ? 24 : 28),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  material.title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 15 : 16,
                      color: Colors.blueGrey[800]),
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
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.lock_outline,
                        size: isMobile ? 14 : 16,
                        color: Colors.amber[800]),
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
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.volume_up,
                        size: isMobile ? 12 : 14,
                        color: Colors.purple[800]),
                  ),
                ),
              ],
            ],
          ),
          subtitle: _buildMaterialSubtitle(material, primaryColor, isMobile),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              if (value == 'edit') {
                _showUploadDialog(materialToEdit: material);
              } else if (value == 'submissions') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReadingMaterialGradingPage(
                      materialId: material.id,
                      materialTitle: material.title,
                      onWillPop: _loadData,
                    ),
                  ),
                );
              } else if (value == 'delete') {
                _deleteMaterial(material);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 10),
                  Text('Edit'),
                ]),
              ),
              PopupMenuItem(
                value: 'submissions',
                child: Row(children: [
                  Icon(Icons.grading, size: 20),
                  SizedBox(width: 10),
                  Text('Grade Submissions'),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Delete'),
                ]),
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
              borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildMaterialSubtitle(
    ReadingMaterial material,
    Color primaryColor,
    bool isMobile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            _badge('Level ${material.levelNumber ?? 'N/A'}',
                primaryColor.withOpacity(0.1), primaryColor, isMobile),
            if (material.className != null)
              _badge(material.className!, Colors.blue[50]!,
                  Colors.blue[700]!, isMobile),
            if (material.audioUrl != null && material.audioUrl!.isNotEmpty)
              _badge('Audio', Colors.purple[50]!, Colors.purple[700]!,
                  isMobile,
                  icon: Icons.volume_up),
          ],
        ),
        if (material.description != null) ...[
          const SizedBox(height: 8),
          Text(material.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: isMobile ? 12 : 14, color: Colors.grey[600])),
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
                Icon(Icons.lock_outline, size: 14, color: Colors.amber[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Requires: ${material.prerequisiteTitle!}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber[800],
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _badge(String label, Color bg, Color fg, bool isMobile,
      {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: isMobile ? 8 : 10, color: fg),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: isMobile ? 10 : 12,
                        color: fg,
                        fontWeight: FontWeight.w600)),
              ],
            )
          : Text(label,
              style: TextStyle(
                  fontSize: isMobile ? 10 : 12,
                  color: fg,
                  fontWeight: FontWeight.w600)),
    );
  }

  // -------------------------------------------------------------------------
  // Preview screens
  // -------------------------------------------------------------------------

  Future<void> _showPdfPreview(ReadingMaterial material) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewWithAudioScreen(
          pdfUrl: material.fileUrl,
          audioUrl: material.audioUrl,
          title: material.title,
          primaryColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Future<void> _showImagePreview(ReadingMaterial material) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImagePreviewWithAudioScreen(
          imageUrl: material.fileUrl,
          audioUrl: material.audioUrl,
          title: material.title,
          primaryColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

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
              if (widget.classId != null && _className != null)
                Container(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  color: Colors.blue[50],
                  child: Row(
                    children: [
                      Icon(Icons.class_rounded,
                          color: Colors.blue[700],
                          size: isMobile ? 18 : 20),
                      SizedBox(width: isMobile ? 8 : 12),
                      Expanded(
                        child: Text(
                          'Classroom: $_className',
                          style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                                color: primaryColor, strokeWidth: 2.5),
                            const SizedBox(height: 16),
                            Text(
                              widget.classId != null
                                  ? 'Loading Classroom Materials...'
                                  : 'Loading Materials...',
                              style: TextStyle(
                                  fontSize: isMobile ? 14 : 16,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _handleRefresh,
                        color: primaryColor,
                        backgroundColor: Colors.white,
                        child: _materials.isEmpty
                            ? Center(
                                child: Padding(
                                  padding:
                                      EdgeInsets.all(isMobile ? 24 : 32),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.library_books_outlined,
                                          size: isMobile ? 60 : 80,
                                          color: Colors.grey[400]),
                                      SizedBox(
                                          height: isMobile ? 16 : 24),
                                      Text(
                                        widget.classId != null
                                            ? 'No Classroom Materials Yet'
                                            : 'No Reading Materials Yet',
                                        style: TextStyle(
                                            fontSize: isMobile ? 16 : 18,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500),
                                        textAlign: TextAlign.center,
                                      ),
                                      SizedBox(height: isMobile ? 8 : 12),
                                      Text(
                                        widget.classId != null
                                            ? 'Tap + to upload or assign materials'
                                            : 'Tap + to upload your first material',
                                        style: TextStyle(
                                            fontSize: isMobile ? 12 : 14,
                                            color: Colors.grey[500]),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding:
                                    EdgeInsets.all(isMobile ? 12 : 16),
                                itemCount: _materials.length,
                                itemBuilder: (_, i) =>
                                    _buildMaterialItem(_materials[i], i),
                              ),
                      ),
              ),
            ],
          ),
        ),
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

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  Future<void> _cleanupPreviewAudioAfterUpload() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/teacher_preview_audio');
      if (!await dir.exists()) return;

      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      for (var file in await dir.list().toList()) {
        if (file is File && file.path.endsWith('.m4a')) {
          try {
            if ((await file.stat()).modified.isBefore(cutoff)) {
              await file.delete();
              debugPrint('🗑️ [CLEANUP] Deleted: ${file.path}');
            }
          } catch (e) {
            debugPrint('⚠️ [CLEANUP] $e');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CLEANUP] Preview audio cleanup error: $e');
    }
  }

  Future<void> _cleanupOldPreviewAudio({int keepLast = 5}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/teacher_preview_audio');
      if (!await dir.exists()) return;

      final files = (await dir.list().toList()).whereType<File>().toList();
      if (files.length <= keepLast) return;

      files.sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified));

      for (int i = keepLast; i < files.length; i++) {
        try {
          await files[i].delete();
          debugPrint('🗑️ [PREVIEW_CLEANUP] Deleted: ${files[i].path}');
        } catch (e) {
          debugPrint('⚠️ [PREVIEW_CLEANUP] $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PREVIEW_CLEANUP] Error: $e');
    }
  }

  Future<void> _cleanupOldTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      for (var file in await tempDir.list().toList()) {
        if (file is File && file.path.contains('persistent_')) {
          try {
            if ((await file.stat()).modified.isBefore(cutoff)) {
              await file.delete();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CLEANUP] Temp files: $e');
    }
  }

  Future<void> _cleanupUploadedFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/teacher_uploads');
      if (!await dir.exists()) return;

      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      for (var file in await dir.list().toList()) {
        if (file is File) {
          try {
            if ((await file.stat()).modified.isBefore(cutoff)) {
              await file.delete();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CLEANUP] Upload files: $e');
    }
  }
}

// ===========================================================================
// PDF preview screen
// ===========================================================================

class PdfPreviewWithAudioScreen extends StatefulWidget {
  const PdfPreviewWithAudioScreen({
    super.key,
    required this.pdfUrl,
    this.audioUrl,
    required this.title,
    required this.primaryColor,
  });

  final String pdfUrl;
  final String? audioUrl;
  final String title;
  final Color primaryColor;

  @override
  State<PdfPreviewWithAudioScreen> createState() =>
      _PdfPreviewWithAudioScreenState();
}

class _PdfPreviewWithAudioScreenState
    extends State<PdfPreviewWithAudioScreen> {
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
      final source = widget.audioUrl!.startsWith('http')
          ? AudioSource.uri(Uri.parse(widget.audioUrl!))
          : AudioSource.file(widget.audioUrl!);

      await _audioPlayer.setAudioSource(source, preload: true);
      await _audioPlayer.load();

      _audioPlayer.positionStream
          .listen((p) { if (mounted) setState(() => _position = p); });
      _audioPlayer.durationStream
          .listen((d) { if (mounted) setState(() => _duration = d ?? Duration.zero); });
      _audioPlayer.playerStateStream.listen((s) {
        if (!mounted) return;
        final playing = s.playing;
        final proc = s.processingState;
        setState(() {
          _isPlaying = playing &&
              proc != ProcessingState.completed &&
              proc != ProcessingState.idle;
          _isBuffering = proc == ProcessingState.buffering;
          _hasError = proc == ProcessingState.idle &&
              !playing &&
              _duration > Duration.zero;
        });
      });
    } catch (e, stack) {
      debugPrint('❌ [AUDIO] Init failed: $e\n$stack');
      if (mounted) setState(() => _hasError = true);
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.completed) {
          await _audioPlayer.seek(Duration.zero);
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('❌ [AUDIO] Playback error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pdfViewer = SfPdfViewer.network(widget.pdfUrl);

    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(widget.title),
              backgroundColor: widget.primaryColor,
              foregroundColor: Colors.white,
              actions: [
                if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty)
                  IconButton(
                    icon: _isBuffering
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: _togglePlayback,
                    tooltip: _isPlaying ? 'Pause' : 'Play',
                  ),
                IconButton(
                  icon: Icon(_isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen),
                  onPressed: () =>
                      setState(() => _isFullscreen = !_isFullscreen),
                ),
              ],
            ),
      body: Stack(
        children: [
          _isFullscreen
              ? pdfViewer
              : Column(
                  children: [
                    if (widget.audioUrl != null &&
                        widget.audioUrl!.isNotEmpty)
                      _buildAudioControls(),
                    Expanded(child: pdfViewer),
                  ],
                ),
          if (_isFullscreen)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.black.withOpacity(0.6),
                    onPressed: () =>
                        setState(() => _isFullscreen = false),
                    child: const Icon(Icons.fullscreen_exit,
                        color: Colors.white),
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
                child: Text("Teacher's Audio Instructions",
                    style: TextStyle(color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
              ),
              if (_hasError)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _position.inSeconds.toDouble(),
              min: 0,
              max: _duration.inSeconds.toDouble().clamp(0, double.infinity),
              onChanged: (v) =>
                  _audioPlayer.seek(Duration(seconds: v.toInt())),
              activeColor: Colors.blue[300],
              inactiveColor: Colors.grey[600],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_position),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10,
                        color: Colors.white70),
                    onPressed: () {
                      final p = _position - const Duration(seconds: 10);
                      _audioPlayer.seek(
                          p < Duration.zero ? Duration.zero : p);
                    },
                  ),
                  IconButton(
                    icon: _isBuffering
                        ? const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                                strokeWidth: 3))
                        : Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 48),
                    onPressed: _togglePlayback,
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10,
                        color: Colors.white70),
                    onPressed: () => _audioPlayer.seek(
                        _position + const Duration(seconds: 10)),
                  ),
                ],
              ),
              Text(_fmt(_duration),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Image preview screen
// ===========================================================================

class ImagePreviewWithAudioScreen extends StatefulWidget {
  const ImagePreviewWithAudioScreen({
    super.key,
    required this.imageUrl,
    this.audioUrl,
    required this.title,
    required this.primaryColor,
  });

  final String imageUrl;
  final String? audioUrl;
  final String title;
  final Color primaryColor;

  @override
  State<ImagePreviewWithAudioScreen> createState() =>
      _ImagePreviewWithAudioScreenState();
}

class _ImagePreviewWithAudioScreenState
    extends State<ImagePreviewWithAudioScreen> {
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasError = false;
  bool _isFullscreen = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    if (widget.audioUrl == null || widget.audioUrl!.isEmpty) return;
    try {
      final source = widget.audioUrl!.startsWith('http')
          ? AudioSource.uri(Uri.parse(widget.audioUrl!))
          : AudioSource.file(widget.audioUrl!);

      await _audioPlayer.setAudioSource(source, preload: true);
      await _audioPlayer.load();

      _audioPlayer.positionStream
          .listen((p) { if (mounted) setState(() => _position = p); });
      _audioPlayer.durationStream
          .listen((d) { if (mounted) setState(() => _duration = d ?? Duration.zero); });
      _audioPlayer.playerStateStream.listen((s) {
        if (!mounted) return;
        final playing = s.playing;
        final proc = s.processingState;
        setState(() {
          _isPlaying = playing &&
              proc != ProcessingState.completed &&
              proc != ProcessingState.idle;
          _isBuffering = proc == ProcessingState.buffering;
          _hasError = proc == ProcessingState.idle &&
              !playing &&
              _duration > Duration.zero;
        });
      });
    } catch (e, stack) {
      debugPrint('❌ [AUDIO] Init failed: $e\n$stack');
      if (mounted) setState(() => _hasError = true);
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.completed) {
          await _audioPlayer.seek(Duration.zero);
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('❌ [AUDIO] Playback error: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('Failed to load image'),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(widget.title),
              backgroundColor: widget.primaryColor,
              foregroundColor: Colors.white,
              actions: [
                if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty)
                  IconButton(
                    icon: _isBuffering
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: _togglePlayback,
                  ),
                IconButton(
                  icon: Icon(_isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen),
                  onPressed: () =>
                      setState(() => _isFullscreen = !_isFullscreen),
                ),
              ],
            ),
      body: Stack(
        children: [
          _isFullscreen
              ? imageWidget
              : Column(
                  children: [
                    if (widget.audioUrl != null &&
                        widget.audioUrl!.isNotEmpty)
                      _buildAudioControls(),
                    Expanded(child: imageWidget),
                  ],
                ),
          if (_isFullscreen)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.black.withOpacity(0.6),
                    onPressed: () =>
                        setState(() => _isFullscreen = false),
                    child: const Icon(Icons.fullscreen_exit,
                        color: Colors.white),
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
          const Row(
            children: [
              Icon(Icons.volume_up, color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text("Teacher's Audio Instructions",
                    style: TextStyle(color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _position.inSeconds.toDouble(),
              min: 0,
              max: _duration.inSeconds.toDouble().clamp(0, double.infinity),
              onChanged: (v) =>
                  _audioPlayer.seek(Duration(seconds: v.toInt())),
              activeColor: Colors.blue[300],
              inactiveColor: Colors.grey[600],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_position),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10,
                        color: Colors.white70),
                    onPressed: () {
                      final p = _position - const Duration(seconds: 10);
                      _audioPlayer.seek(
                          p < Duration.zero ? Duration.zero : p);
                    },
                  ),
                  IconButton(
                    icon: _isBuffering
                        ? const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                                strokeWidth: 3))
                        : Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 40),
                    onPressed: _togglePlayback,
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10,
                        color: Colors.white70),
                    onPressed: () => _audioPlayer.seek(
                        _position + const Duration(seconds: 10)),
                  ),
                ],
              ),
              Text(_fmt(_duration),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// File preview with audio recording screen
// ===========================================================================

class _FilePreviewWithAudioScreen extends StatefulWidget {
  const _FilePreviewWithAudioScreen({
    required this.file,
    required this.fileType,
    this.title,
    required this.allowAudioRecording,
    required this.primaryColor,
  });

  final File file;
  final String? fileType;
  final String? title;
  final bool allowAudioRecording;
  final Color primaryColor;

  @override
  __FilePreviewWithAudioScreenState createState() =>
      __FilePreviewWithAudioScreenState();
}

class __FilePreviewWithAudioScreenState
    extends State<_FilePreviewWithAudioScreen> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  bool _isRecording = false;
  String? _audioPath;
  bool _hasAudio = false;
  bool _isPlaying = false;
  bool _isPlayerInitialized = false;
  Duration _current = Duration.zero;
  Duration _total = Duration.zero;
  Timer? _timer;
  int _recordingSeconds = 0;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _setupPlayerListeners();
  }

  @override
  void dispose() {
    // ✅ Release resources only — no setState allowed here.
    _timer?.cancel();

    if (_isRecording) _recorder.stop().catchError((_) {});
    _recorder.dispose();

    _player.stop().catchError((_) {});
    _player.dispose();

    // Clean up if the user closed the screen without saving.
    if (!_hasAudio && _audioPath != null) {
      try {
        final f = File(_audioPath!);
        if (f.existsSync()) {
          f.deleteSync();
          debugPrint('🗑️ [PREVIEW] Cleaned up unsaved audio: $_audioPath');
        }
      } catch (e) {
        debugPrint('⚠️ [PREVIEW] Cleanup error: $e');
      }
    }

    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Audio player
  // -------------------------------------------------------------------------

  void _setupPlayerListeners() {
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _current = p);
    });
    _player.durationStream.listen((d) {
      if (mounted) setState(() => _total = d ?? Duration.zero);
    });
    _player.playerStateStream.listen((s) {
      if (mounted && s.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
          _current = Duration.zero;
        });
      }
    });
  }

  Future<void> _initPlayer() async {
    if (_audioPath == null || _isPlayerInitialized) return;
    final f = File(_audioPath!);
    if (!await f.exists()) throw Exception('Audio file not found');
    await _player.setFilePath(_audioPath!);
    final dur = await _player.duration;
    if (mounted) {
      setState(() {
        _total = dur ?? Duration.zero;
        _isPlayerInitialized = true;
      });
    }
  }

  Future<void> _playPreview() async {
    if (_audioPath == null) return;

    final f = File(_audioPath!);
    if (!await f.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Audio file not found. Please record again.'),
          backgroundColor: Colors.red,
        ));
        setState(() {
          _hasAudio = false;
          _audioPath = null;
          _isPlayerInitialized = false;
        });
      }
      return;
    }

    try {
      if (!_isPlayerInitialized) await _initPlayer();
      await _stopPreview();
      await Future.delayed(const Duration(milliseconds: 50));
      await _player.seek(Duration.zero);
      if (mounted) setState(() { _isPlaying = true; _current = Duration.zero; });
      await _player.play();
    } catch (e) {
      debugPrint('❌ [PREVIEW] Play error: $e');
      if (mounted) setState(() => _isPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _pausePreview() async {
    try {
      await _player.pause();
      if (mounted) setState(() => _isPlaying = false);
    } catch (e) {
      debugPrint('⚠️ [PREVIEW] Pause error: $e');
    }
  }

  Future<void> _stopPreview() async {
    try {
      if (_isPlayerInitialized) {
        await _player.stop();
        await _player.seek(Duration.zero);
      }
      if (mounted) setState(() { _isPlaying = false; _current = Duration.zero; });
    } catch (e) {
      debugPrint('⚠️ [PREVIEW] Stop error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  Future<void> _startRecording() async {
    try {
      await _stopPreview();

      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Microphone permission required'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final persistDir =
          Directory('${dir.path}/teacher_preview_audio');
      if (!await persistDir.exists()) {
        await persistDir.create(recursive: true);
      }

      final path =
          '${persistDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);

      if (mounted) {
        setState(() {
          _isRecording = true;
          _audioPath = path;
          _hasAudio = false;
          _isPlayerInitialized = false;
        });
      }

      _timer?.cancel();
      _recordingSeconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _recordingSeconds = t.tick);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(
            children: [
              Icon(Icons.mic, color: Colors.white),
              SizedBox(width: 8),
              Text('Recording audio instructions...'),
            ],
          ),
          backgroundColor: widget.primaryColor,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('❌ [RECORDING] Start error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stop();
      _timer?.cancel();
      _timer = null;

      if (mounted) setState(() => _isRecording = false);

      if (_audioPath != null) {
        final f = File(_audioPath!);
        if (!await f.exists()) {
          throw Exception('Audio file was not saved properly');
        }

        await _initPlayer();
        if (mounted) setState(() => _hasAudio = true);

        final size = await f.length();
        debugPrint(
            '✅ [RECORDING] Saved: $_audioPath ($size bytes)');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Audio recording saved successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      debugPrint('❌ [RECORDING] Stop error: $e');
      if (mounted) {
        setState(() {
          _hasAudio = false;
          _audioPath = null;
          _isPlayerInitialized = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to save recording: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _fmtTimer(int s) {
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canRecord = widget.allowAudioRecording &&
        (widget.fileType == 'pdf' || widget.fileType == 'image');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'File Preview'),
        backgroundColor: widget.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (canRecord)
            IconButton(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              onPressed:
                  _isRecording ? _stopRecording : _startRecording,
              tooltip:
                  _isRecording ? 'Stop Recording' : 'Start Recording',
            ),
        ],
      ),
      body: Column(
        children: [
          if (canRecord) _buildRecordingPanel(),
          Expanded(
            child: widget.fileType == 'pdf'
                ? SfPdfViewer.file(widget.file)
                : Center(
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 3.0,
                      child: Image.file(widget.file,
                          fit: BoxFit.contain),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton:
          (widget.allowAudioRecording && _hasAudio && !_isRecording)
              ? FloatingActionButton(
                  backgroundColor: Colors.green,
                  onPressed: () async {
                    await _stopPreview();
                    if (_audioPath == null) return;
                    final f = File(_audioPath!);
                    if (await f.exists()) {
                      await Future.delayed(
                          const Duration(milliseconds: 100));
                      if (mounted) Navigator.pop(context, _audioPath);
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                          content: Text(
                              'Audio file not found. Please record again.'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    }
                  },
                  child: const Icon(Icons.check),
                )
              : null,
    );
  }

  Widget _buildRecordingPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over,
                  color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text('Add Reading Instructions',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700])),
              const Spacer(),
              if (_isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(_fmtTimer(_recordingSeconds),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Audio player
          if (_hasAudio && _audioPath != null)
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
                    value: _current.inSeconds.toDouble(),
                    min: 0,
                    max: _total.inSeconds
                        .toDouble()
                        .clamp(0, double.infinity),
                    onChanged: (v) =>
                        _player.seek(Duration(seconds: v.toInt())),
                    activeColor: Colors.blue,
                    inactiveColor: Colors.blue.withOpacity(0.3),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmtDuration(_current),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Iconsax.previous, size: 20),
                            onPressed: () =>
                                _player.seek(Duration.zero),
                            tooltip: 'Restart',
                          ),
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Iconsax.pause : Iconsax.play,
                              size: 24,
                              color: Colors.blue,
                            ),
                            onPressed: _isPlaying
                                ? _pausePreview
                                : _playPreview,
                          ),
                          IconButton(
                            icon: const Icon(Iconsax.stop, size: 20),
                            onPressed: _stopPreview,
                            tooltip: 'Stop',
                          ),
                        ],
                      ),
                      Text(_fmtDuration(_total),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                ],
              ),
            ),

          // Status badge
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isRecording
                  ? Colors.red.withOpacity(0.1)
                  : _hasAudio
                      ? Colors.green.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _isRecording
                      ? Icons.circle
                      : _hasAudio
                          ? Icons.check_circle
                          : Icons.info_outline,
                  color: _isRecording
                      ? Colors.red
                      : _hasAudio
                          ? Colors.green
                          : Colors.blue,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isRecording
                        ? 'Recording in progress...'
                        : _hasAudio
                            ? 'Audio recording saved!'
                            : 'Record audio instructions for students',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isRecording
                          ? Colors.red[800]
                          : _hasAudio
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
    );
  }
}
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:dio/dio.dart';
import 'package:iconsax/iconsax.dart';
import '../../api/reading_materials_service.dart';
import '../../utils/file_validator.dart';

class EnhancedReadingMaterialPage extends StatefulWidget {
  final Map<String, dynamic> material;
  final String? classId; // Add optional classId parameter

  const EnhancedReadingMaterialPage({
    super.key,
    required this.material,
    this.classId,
  });

  @override
  State<EnhancedReadingMaterialPage> createState() =>
      _EnhancedReadingMaterialPageState();
}

class _EnhancedReadingMaterialPageState
    extends State<EnhancedReadingMaterialPage> {
  final supabase = Supabase.instance.client;
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool isLoading = true;
  bool isRecording = false;
  bool hasRecording = false;
  String? recordingPath;
  String? fileUrl;
  String? localFilePath;
  bool isSubmitting = false;
  bool isSubmitted = false;

  // Prerequisite functionality
  bool _hasPrerequisite = false;
  String? _prerequisiteId;
  String? _prerequisiteTitle;
  bool _hasCompletedPrerequisite = true;
  bool _canAccessMaterial = true;

  // Retake functionality
  Map<String, dynamic>? _currentRecording;
  bool _hasExistingRecording = false;
  bool _isGraded = false;
  bool _canRecordAgain = true;
  String _teacherFeedback = '';
  int? _teacherScore;
  bool _isRetakeRequested = false; // Teacher requests retake
  bool _isRetakeApproved =
      false; // Teacher approves retake (for cases where approval is separate)

  // File type detection
  String? _fileType; // 'pdf', 'image', or null
  bool get _isPdf => _fileType == 'pdf';
  bool get _isImage => _fileType == 'image';

  // Audio preview
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingPreview = false;
  Duration _currentDuration = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _audioPositionSubscription;
  StreamSubscription? _audioDurationSubscription;
  StreamSubscription? _audioStateSubscription;

  // PDF viewer state
  bool _showFullView = false;
  final PdfViewerController _pdfViewerController = PdfViewerController();

  // Floating recording panel state
  bool _showRecordingPanel = false;
  bool _isRecordingPanelMinimized = false;
  Offset _recordingPanelOffset = Offset(20, 20);
  bool _isRecordingPanelDragging = false;

  // Recording timer
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Teacher audio recording state
  String? _teacherAudioUrl;
  bool _isLoadingTeacherAudio = false;
  bool _isPlayingTeacherAudio = false;
  Duration _teacherAudioCurrentDuration = Duration.zero;
  Duration _teacherAudioTotalDuration = Duration.zero;
  final AudioPlayer _teacherAudioPlayer = AudioPlayer();
  StreamSubscription? _teacherAudioPositionSubscription;
  StreamSubscription? _teacherAudioDurationSubscription;
  StreamSubscription? _teacherAudioStateSubscription;

  @override
  void initState() {
    super.initState();
    _loadMaterialData();
    _setupAudioPlayerListeners();
    _loadCurrentRecording();
    _checkPrerequisiteStatus();
    _loadTeacherAudio();
  }

  @override
  void dispose() {
    _cleanupAudioResources();
    _audioRecorder.dispose();
    _pdfViewerController.dispose();
    _recordingTimer?.cancel();
    _cleanupOldAudioFiles();
    super.dispose();
  }

  void _cleanupAudioResources() {
    // Clean up student audio player
    _audioPositionSubscription?.cancel();
    _audioDurationSubscription?.cancel();
    _audioStateSubscription?.cancel();
    _audioPlayer.dispose();

    // Clean up teacher audio player
    _teacherAudioPositionSubscription?.cancel();
    _teacherAudioDurationSubscription?.cancel();
    _teacherAudioStateSubscription?.cancel();
    _teacherAudioPlayer.dispose();
  }

  Future<void> _loadTeacherAudio() async {
    try {
      setState(() => _isLoadingTeacherAudio = true);

      // Get teacher audio URL from material data
      _teacherAudioUrl = widget.material['audio_url'] as String?;

      debugPrint('🎤 Teacher audio URL from material: $_teacherAudioUrl');

      if (_teacherAudioUrl != null && _teacherAudioUrl!.isNotEmpty) {
        debugPrint('🎤 Teacher audio found: $_teacherAudioUrl');

        // Setup teacher audio player listeners
        _teacherAudioPositionSubscription = _teacherAudioPlayer.positionStream
            .listen((position) {
              if (mounted) {
                setState(() {
                  _teacherAudioCurrentDuration = position;
                });
              }
            });

        _teacherAudioDurationSubscription = _teacherAudioPlayer.durationStream
            .listen((duration) {
              if (mounted) {
                setState(() {
                  _teacherAudioTotalDuration = duration ?? Duration.zero;
                });
              }
            });

        _teacherAudioStateSubscription = _teacherAudioPlayer.playerStateStream
            .listen((state) {
              if (mounted) {
                if (state.processingState == ProcessingState.completed) {
                  setState(() {
                    _isPlayingTeacherAudio = false;
                    _teacherAudioCurrentDuration = Duration.zero;
                  });
                }
              }
            });
      }
    } catch (e) {
      debugPrint('Error loading teacher audio: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingTeacherAudio = false);
      }
    }
  }

  Future<void> _playTeacherAudio() async {
    if (_teacherAudioUrl == null || _teacherAudioUrl!.isEmpty) return;

    try {
      // Reset state before playing
      setState(() {
        _isPlayingTeacherAudio = true;
        _teacherAudioCurrentDuration = Duration.zero;
      });

      // Stop any current playback
      await _teacherAudioPlayer.stop();

      // Set the audio source and play
      await _teacherAudioPlayer.setUrl(_teacherAudioUrl!);
      await _teacherAudioPlayer.play();
    } catch (e) {
      debugPrint('Error playing teacher audio: $e');
      if (mounted) {
        setState(() => _isPlayingTeacherAudio = false);
      }
    }
  }

  Future<void> _pauseTeacherAudio() async {
    try {
      await _teacherAudioPlayer.pause();
      if (mounted) {
        setState(() => _isPlayingTeacherAudio = false);
      }
    } catch (e) {
      debugPrint('Error pausing teacher audio: $e');
    }
  }

  Future<void> _stopTeacherAudio() async {
    try {
      await _teacherAudioPlayer.stop();
      if (mounted) {
        setState(() {
          _isPlayingTeacherAudio = false;
          _teacherAudioCurrentDuration = Duration.zero;
        });
      }
    } catch (e) {
      debugPrint('Error stopping teacher audio: $e');
    }
  }

  void _seekTeacherAudio(Duration position) async {
    try {
      await _teacherAudioPlayer.seek(position);
    } catch (e) {
      debugPrint('Error seeking teacher audio: $e');
    }
  }

  Future<void> _checkPrerequisiteStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final materialId = widget.material['id'] as String?;
      if (materialId == null) return;

      // Check if material has prerequisite
      _hasPrerequisite = widget.material['has_prerequisite'] as bool? ?? false;
      _prerequisiteId = widget.material['prerequisite_id'] as String?;
      _prerequisiteTitle = widget.material['prerequisite_title'] as String?;

      if (_hasPrerequisite && _prerequisiteId != null) {
        // Check if student has completed the prerequisite
        _hasCompletedPrerequisite =
            await ReadingMaterialsService.hasStudentCompletedPrerequisite(
              studentId: user.id,
              prerequisiteId: _prerequisiteId!,
              classId: widget.classId,
            );

        // FIX: Also check if retake is requested for the prerequisite
        final prerequisiteRecordingRes =
            await supabase
                .from('student_recordings')
                .select('is_retake_requested')
                .eq('student_id', user.id)
                .eq('material_id', _prerequisiteId!)
                .eq('class_id', widget.classId ?? '')
                .maybeSingle();

        if (prerequisiteRecordingRes != null) {
          final isRetakeRequestedOnPrerequisite =
              prerequisiteRecordingRes['is_retake_requested'] == true;
          // If retake is requested on prerequisite, student cannot access this material
          if (isRetakeRequestedOnPrerequisite) {
            _hasCompletedPrerequisite = false;
          }
        }

        // Update access status
        _canAccessMaterial = _hasCompletedPrerequisite;

        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('Error checking prerequisite status: $e');
    }
  }

  Future<void> _loadMaterialData() async {
    try {
      // Get file URL from material
      fileUrl = widget.material['file_url'] as String?;

      // Determine file type
      _detectFileType();

      if (fileUrl != null && fileUrl!.isNotEmpty) {
        await _downloadFile();
      }
    } catch (e) {
      debugPrint('Error loading material data: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadCurrentRecording() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null || widget.material == null) return;

      final materialId = widget.material['id'] as String?;
      if (materialId == null) return;

      // Check if there's a recording for this material
      final recordingRes = await supabase
          .from('student_recordings')
          .select('*')
          .eq('student_id', user.id)
          .eq('material_id', materialId)
          .eq('class_id', widget.classId ?? '')
          .order('recorded_at', ascending: true)
          .limit(1);

      if (recordingRes.isNotEmpty) {
        final recording = recordingRes.first;

        if (mounted) {
          setState(() {
            _currentRecording = recording;
            _hasExistingRecording = true;
            isSubmitted = true;
            _isGraded = recording['needs_grading'] == false;
            _isRetakeRequested = recording['is_retake_requested'] == true;
            _isRetakeApproved = recording['is_retake_approved'] == true;

            // FIXED: Updated logic - student can record again if:
            // 1. No existing recording (first time), OR
            // 2. Teacher has requested a retake (is_retake_requested = true), OR
            // 3. Teacher has approved a retake (is_retake_approved = true)
            _canRecordAgain =
                !_hasExistingRecording ||
                _isRetakeRequested ||
                _isRetakeApproved;

            // Load teacher feedback if available
            if (recording['teacher_comments'] != null) {
              _teacherFeedback = recording['teacher_comments'] as String;
            }

            // Load score if available
            if (recording['score'] != null) {
              _teacherScore = recording['score'] as int;
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasExistingRecording = false;
            _isGraded = false;
            _isRetakeRequested = false;
            _isRetakeApproved = false;
            _canRecordAgain = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recording: $e');
    }
  }

  void _detectFileType() {
    if (fileUrl == null) return;

    final url = fileUrl!.toLowerCase();
    if (url.endsWith('.pdf')) {
      _fileType = 'pdf';
    } else if (url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.png')) {
      _fileType = 'image';
    }
  }

  Future<void> _downloadFile() async {
    if (fileUrl == null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final materialId = widget.material['id'] as String? ?? 'material';
      final fileExtension = _isPdf ? 'pdf' : (_isImage ? 'jpg' : 'file');
      final filePath = '${dir.path}/material_$materialId.$fileExtension';

      await Dio().download(fileUrl!, filePath);
      setState(() {
        localFilePath = filePath;
      });
    } catch (e) {
      debugPrint('Error downloading file: $e');
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingSeconds = 0;
    _recordingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingSeconds = timer.tick;
        });
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  Future<void> _startRecording() async {
    // Check if material can be accessed
    if (!_canAccessMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete the prerequisite "$_prerequisiteTitle" first',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Microphone permission required'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // FIX: Use application documents directory instead of temporary directory
      final dir = await getApplicationDocumentsDirectory();
      final materialId = widget.material['id'] as String? ?? 'material';
      final classIdSuffix =
          widget.classId != null ? '_class${widget.classId}' : '';
      final filePath =
          '${dir.path}/reading_${user.id}_${materialId}${classIdSuffix}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(const RecordConfig(), path: filePath);

      setState(() {
        isRecording = true;
        recordingPath = filePath;
        _showRecordingPanel = true;
      });

      _startRecordingTimer();

      final colorScheme = Theme.of(context).colorScheme;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.mic, color: Colors.white),
                SizedBox(width: 8),
                Text('Recording started... Speak clearly!'),
              ],
            ),
            backgroundColor: colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      // Use the path returned by stop() as the definitive source
      final path = await _audioRecorder.stop();
      _stopRecordingTimer();

      if (path == null || path.isEmpty) {
        throw Exception('Recorder returned an empty or null path');
      }

      // Verify the recorded file exists and has size
      final recordedFile = File(path);
      final bool fileExists = await recordedFile.exists();
      final fileSize = fileExists ? await recordedFile.length() : 0;

      debugPrint(
        '✅ [RECORDING] Stopped. Path: $path, Exists: $fileExists, Size: $fileSize bytes',
      );

      setState(() {
        isRecording = false;
        hasRecording = fileExists && fileSize > 0;
        recordingPath = hasRecording ? path : null;
      });

      // ... rest of your snackbar code ...
    } catch (e) {
      debugPrint('❌ [RECORDING] Error stopping: $e');
      // ... error handling ...
    }
  }

  void _clearRecording() async {
    if (isRecording) {
      await _stopRecording();
    }

    _stopRecordingTimer();

    // Clean up audio player before clearing
    await _stopPreview();

    // FIX: Actually delete the file from disk
    if (recordingPath != null) {
      try {
        final file = File(recordingPath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('🗑️ [AUDIO_FILE] Deleted file: $recordingPath');
        }
      } catch (e) {
        debugPrint('❌ [AUDIO_FILE] Error deleting file: $e');
      }
    }

    setState(() {
      hasRecording = false;
      recordingPath = null;
      _isPlayingPreview = false;
      _currentDuration = Duration.zero;
      _totalDuration = Duration.zero;
      _recordingSeconds = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Recording cleared'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cleanupOldAudioFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = Directory(dir.path).listSync();

      // Delete files older than 24 hours
      final cutoffTime = DateTime.now().subtract(Duration(hours: 24));

      for (var file in files) {
        if (file is File && file.path.endsWith('.m4a')) {
          final stat = await file.stat();
          if (stat.modified.isBefore(cutoffTime)) {
            await file.delete();
            debugPrint('🗑️ [CLEANUP] Deleted old audio file: ${file.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [CLEANUP] Error cleaning up audio files: $e');
    }
  }

  Future<void> _playRecordingPreview() async {
    if (recordingPath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No recording available')));
      return;
    }

    // CRITICAL FIX: Verify the file exists and is readable
    final recordingFile = File(recordingPath!);
    bool fileExists = await recordingFile.exists();

    // FIX: Also check if file is actually readable and has size
    int fileSize = 0;
    if (fileExists) {
      try {
        fileSize = await recordingFile.length();
        debugPrint('📁 [AUDIO_FILE] File exists, size: $fileSize bytes');
      } catch (e) {
        debugPrint('❌ [AUDIO_FILE] Error checking file size: $e');
        fileExists = false;
      }
    }

    if (!fileExists || fileSize == 0) {
      debugPrint(
        '❌ [AUDIO_PLAYBACK] File does not exist or is empty: $recordingPath',
      );
      setState(() {
        hasRecording = false;
        recordingPath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recording file not found or corrupted. Please record again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // FIX: Check if audio player is already playing
      if (_isPlayingPreview) {
        await _audioPlayer.pause();
        setState(() => _isPlayingPreview = false);
      }

      // FIX: Stop current playback completely
      await _audioPlayer.stop();

      // FIX: Clear the current source and set it again
      await _audioPlayer.setFilePath(recordingPath!);

      // FIX: Set position to start and play
      await _audioPlayer.seek(Duration.zero);

      setState(() {
        _isPlayingPreview = true;
        _currentDuration = Duration.zero;
      });

      await _audioPlayer.play();

      debugPrint('▶️ [AUDIO_PLAYBACK] Playing audio from: $recordingPath');
    } on PlayerException catch (e) {
      debugPrint(
        '❌ [AUDIO_PLAYBACK] PlayerException: ${e.code} - ${e.message}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audio: ${e.message}')),
      );
      setState(() => _isPlayingPreview = false);
    } catch (e) {
      debugPrint('❌ [AUDIO_PLAYBACK] General error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      setState(() => _isPlayingPreview = false);
    }
  }

  Future<void> _pausePreview() async {
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      }
      if (mounted) {
        setState(() => _isPlayingPreview = false);
      }
    } catch (e) {
      debugPrint('Error pausing preview: $e');
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _audioPlayer.stop();
      // FIX: Reset the player state
      await _audioPlayer.seek(Duration.zero);

      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
          _currentDuration = Duration.zero;
        });
      }
    } catch (e) {
      debugPrint('Error stopping preview: $e');
    }
  }

  void _seekAudio(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      debugPrint('Error seeking audio: $e');
    }
  }

  void _setupAudioPlayerListeners() {
    _audioPositionSubscription = _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentDuration = position;
        });
      }
    });

    _audioDurationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration ?? Duration.zero;
        });
      }
    });

    _audioStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlayingPreview = false;
            _currentDuration = Duration.zero;
          });
        }
      }
    });
  }

  Future<void> _submitRecording() async {
    // Check prerequisite first
    if (!_canAccessMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete the prerequisite "$_prerequisiteTitle" first',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!hasRecording || recordingPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please record your reading first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You must be logged in to submit recordings'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final materialId = widget.material['id'] as String?;
    if (materialId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid material ID'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Verify file exists
    final recordingFile = File(recordingPath!);
    if (!await recordingFile.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording file not found. Please record again.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      setState(() {
        hasRecording = false;
        recordingPath = null;
      });
      return;
    }

    try {
      setState(() => isSubmitting = true);

      // Backend validation: Check file size
      final sizeValidation = await validateFileSize(recordingFile);
      if (!sizeValidation.isValid) {
        debugPrint(
          '❌ [UPLOAD_RECORDING] File size validation failed: ${sizeValidation.getDetailedInfo()}',
        );
        setState(() => isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(sizeValidation.getUserMessage()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Check if this is a retake or first submission
      final isRetakeSubmission =
          (_isRetakeRequested || _isRetakeApproved) && _hasExistingRecording;

      // Create filename with path for folder structure
      final fileName =
          'reading_${user.id}_${materialId}_${widget.classId ?? "general"}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final storagePath = 'student_recordings/$fileName';

      // Upload to Supabase Storage to the student_voice bucket
      await supabase.storage
          .from('student_voice') // Specify the bucket name
          .upload(storagePath, recordingFile);

      // Get public URL
      final publicUrl = supabase.storage
          .from('student_voice')
          .getPublicUrl(storagePath);

      if (isRetakeSubmission && _currentRecording != null) {
        // Update existing recording for retake
        await supabase
            .from('student_recordings')
            .update({
              'recording_url': publicUrl,
              'file_url': publicUrl,
              'recorded_at': DateTime.now().toIso8601String(),
              'is_retake_requested': false, // Reset retake request flag
              'is_retake_approved': false, // Reset retake approval flag
              'needs_grading': true, // Reset grading status for new submission
              'teacher_comments': null, // Clear previous feedback
              'score': null, // Clear previous score
            })
            .eq('id', _currentRecording!['id']);
      } else {
        // Create new recording entry
        await supabase.from('student_recordings').insert({
          'student_id': user.id,
          'material_id': materialId,
          'class_id': widget.classId,
          'recording_url': publicUrl,
          'file_url': publicUrl,
          'recorded_at': DateTime.now().toIso8601String(),
          'needs_grading': true,
          'is_retake_requested': false,
          'is_retake_approved': false,
        });
      }

      setState(() {
        isSubmitting = false;
        hasRecording = false;
        recordingPath = null;
        isSubmitted = true;
        _showRecordingPanel = false;
        _isRetakeRequested = false;
        _isRetakeApproved = false;
        // Immediately disable recording after submission
        _canRecordAgain = false;
        // Reload current recording to update UI
        _loadCurrentRecording();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  widget.classId != null
                      ? isRetakeSubmission
                          ? 'Retake submitted to class!'
                          : 'Class recording submitted!'
                      : isRetakeSubmission
                      ? 'Retake submitted successfully!'
                      : 'Recording submitted successfully!',
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error submitting recording: $e');
      setState(() => isSubmitting = false);
      if (mounted) {
        String errorMessage = 'Error submitting: ${e.toString()}';
        if (e is FileSizeLimitException) {
          errorMessage = e.message;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _toggleFullView() {
    setState(() {
      _showFullView = !_showFullView;
    });
  }

  void _toggleRecordingPanel() {
    // Check if material can be accessed
    if (!_canAccessMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete the prerequisite "$_prerequisiteTitle" first',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _showRecordingPanel = !_showRecordingPanel;
      _isRecordingPanelMinimized = false;
      // Reset position when opening
      if (_showRecordingPanel) {
        _recordingPanelOffset = Offset(20, 20);
      }
    });
  }

  void _toggleRecordingPanelMinimize() {
    setState(() {
      _isRecordingPanelMinimized = !_isRecordingPanelMinimized;
    });
  }

  Widget _buildPdfViewer() {
    if (localFilePath != null && File(localFilePath!).existsSync()) {
      return SfPdfViewer.file(
        File(localFilePath!),
        controller: _pdfViewerController,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        pageLayoutMode: PdfPageLayoutMode.single,
        interactionMode: PdfInteractionMode.pan,
      );
    } else if (fileUrl != null && fileUrl!.isNotEmpty) {
      return SfPdfViewer.network(
        fileUrl!,
        controller: _pdfViewerController,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        pageLayoutMode: PdfPageLayoutMode.single,
        interactionMode: PdfInteractionMode.pan,
      );
    } else {
      return Container(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey[400]),
              SizedBox(height: 16),
              Text(
                'No PDF available',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      panEnabled: true,
      minScale: 0.5,
      maxScale: 3.0,
      child: Container(
        width: double.infinity,
        child:
            localFilePath != null && File(localFilePath!).existsSync()
                ? Image.file(
                  File(localFilePath!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildImageErrorFallback();
                  },
                )
                : fileUrl != null
                ? Image.network(
                  fileUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value:
                            loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _buildImageErrorFallback();
                  },
                )
                : _buildImageErrorFallback(),
      ),
    );
  }

  Widget _buildImageErrorFallback() {
    return Container(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'Image not available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileViewer() {
    if (_isPdf) {
      return _buildPdfViewer();
    } else if (_isImage) {
      return _buildImageViewer();
    } else {
      return Container(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file, size: 64, color: Colors.grey[400]),
              SizedBox(height: 16),
              Text(
                'Unsupported file type',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              if (fileUrl != null) ...[
                SizedBox(height: 8),
                Text(
                  'URL: $fileUrl',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }
  }

  Widget _buildFloatingRecordingPanel() {
    if (!_showRecordingPanel) return SizedBox.shrink();

    return Positioned(
      left: _recordingPanelOffset.dx,
      top: _recordingPanelOffset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) {
          setState(() {
            _isRecordingPanelDragging = true;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _recordingPanelOffset = Offset(
              _recordingPanelOffset.dx + details.delta.dx,
              _recordingPanelOffset.dy + details.delta.dy,
            );
          });
        },
        onPanEnd: (details) {
          setState(() {
            _isRecordingPanelDragging = false;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 300),
            child:
                _isRecordingPanelMinimized
                    ? _buildMinimizedRecordingPanel()
                    : _buildExpandedRecordingPanel(),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedRecordingPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetakeInProgress =
        (_isRetakeRequested || _isRetakeApproved) && _hasExistingRecording;

    return Container(
      key: ValueKey('expanded-panel'),
      width: MediaQuery.of(context).size.width - 40,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              _isRecordingPanelDragging ? 0.3 : 0.15,
            ),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: colorScheme.outline.withOpacity(
            _isRecordingPanelDragging ? 0.4 : 0.2,
          ),
          width: _isRecordingPanelDragging ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Panel Header with Drag Handle
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    isRetakeInProgress
                        ? Colors.orange.withOpacity(0.1)
                        : colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  // Drag Handle
                  Icon(
                    Icons.drag_handle,
                    color:
                        isRetakeInProgress
                            ? Colors.orange
                            : colorScheme.primary.withOpacity(0.7),
                    size: 20,
                  ),
                  SizedBox(width: 8),

                  Icon(
                    isRetakeInProgress ? Icons.refresh : Iconsax.microphone_2,
                    color:
                        isRetakeInProgress
                            ? Colors.orange
                            : colorScheme.primary,
                    size: 20,
                  ),
                  SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      isRetakeInProgress
                          ? 'Record Retake'
                          : widget.classId != null
                          ? 'Record Reading'
                          : 'Record Your Reading',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            isRetakeInProgress
                                ? Colors.orange
                                : colorScheme.primary,
                      ),
                    ),
                  ),

                  // Timer display when recording
                  if (isRecording)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${_recordingSeconds ~/ 60}:${(_recordingSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),

                  SizedBox(width: 8),

                  // Minimize Button
                  Tooltip(
                    message: 'Minimize',
                    child: IconButton(
                      icon: Icon(Iconsax.minus, size: 20),
                      onPressed: _toggleRecordingPanelMinimize,
                    ),
                  ),

                  // Close Button
                  Tooltip(
                    message: 'Close',
                    child: IconButton(
                      icon: Icon(Icons.close, size: 20),
                      onPressed: () {
                        setState(() {
                          _showRecordingPanel = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Panel Content
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                // Recording Status
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        isRecording
                            ? Colors.red.withOpacity(0.1)
                            : hasRecording
                            ? Colors.green.withOpacity(0.1)
                            : colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          isRecording
                              ? Colors.red.withOpacity(0.3)
                              : hasRecording
                              ? Colors.green.withOpacity(0.3)
                              : colorScheme.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color:
                              isRecording
                                  ? Colors.red
                                  : hasRecording
                                  ? Colors.green
                                  : colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isRecording
                              ? Iconsax.record_circle
                              : hasRecording
                              ? Iconsax.tick_circle
                              : Iconsax.microphone,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isRecording
                                  ? 'Recording in progress...'
                                  : hasRecording
                                  ? 'Recording ready!'
                                  : 'Ready to record',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    isRecording
                                        ? Colors.red[800]
                                        : hasRecording
                                        ? Colors.green[800]
                                        : colorScheme.primary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              isRetakeInProgress
                                  ? _isRetakeRequested
                                      ? 'Your teacher wants you to retake this reading. Record your new reading.'
                                      : 'Your teacher has approved a retake. Record your new reading.'
                                  : widget.classId != null
                                  ? isRecording
                                      ? 'Recording for class assignment'
                                      : hasRecording
                                      ? 'Class recording is saved'
                                      : 'Record your reading'
                                  : isRecording
                                  ? 'Speak clearly into the microphone'
                                  : hasRecording
                                  ? 'Your recording is saved and ready'
                                  : 'Record while reading the material',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isRecording)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedOpacity(
                            opacity: isRecording ? 1.0 : 0.0,
                            duration: Duration(milliseconds: 500),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 16),

                // Audio Player (when recording exists)
                if (hasRecording && recordingPath != null) _buildAudioPlayer(),

                SizedBox(height: 16),

                // Action Buttons
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    // Record/Stop Button
                    ElevatedButton.icon(
                      onPressed: isRecording ? _stopRecording : _startRecording,
                      icon: Icon(
                        isRecording ? Iconsax.stop : Iconsax.microphone,
                        size: 18,
                      ),
                      label: Text(
                        isRecording ? 'Stop Recording' : 'Start Recording',
                        style: TextStyle(fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isRecording ? Colors.red : colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    // Clear Button
                    if (hasRecording)
                      OutlinedButton.icon(
                        onPressed: _clearRecording,
                        icon: Icon(Iconsax.trash, size: 18),
                        label: Text('Clear', style: TextStyle(fontSize: 14)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red),
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                    // Submit Button
                    if (hasRecording && !isSubmitting)
                      ElevatedButton.icon(
                        onPressed: _submitRecording,
                        icon: Icon(
                          isRetakeInProgress ? Icons.refresh : Iconsax.send_2,
                          size: 18,
                        ),
                        label: Text(
                          isRetakeInProgress
                              ? 'Submit Retake'
                              : widget.classId != null
                              ? 'Submit'
                              : 'Submit',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isRetakeInProgress
                                  ? Colors.orange
                                  : Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                    // Cancel Button during submission
                    if (isSubmitting)
                      ElevatedButton.icon(
                        onPressed: null,
                        icon: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        label: Text(
                          'Submitting...',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimizedRecordingPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final isRetakeInProgress =
        (_isRetakeRequested || _isRetakeApproved) && _hasExistingRecording;

    return Material(
      color: Colors.transparent,
      child: Container(
        key: ValueKey('minimized-panel'),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                _isRecordingPanelDragging ? 0.3 : 0.15,
              ),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
          border: Border.all(
            color: colorScheme.outline.withOpacity(
              _isRecordingPanelDragging ? 0.4 : 0.2,
            ),
            width: _isRecordingPanelDragging ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle (Minimized)
            Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.drag_handle,
                color: colorScheme.primary.withOpacity(0.5),
                size: 16,
              ),
            ),
            SizedBox(width: 4),

            // Recording Status Indicator
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isRecording
                        ? Colors.red.withOpacity(0.1)
                        : hasRecording
                        ? Colors.green.withOpacity(0.1)
                        : isRetakeInProgress
                        ? Colors.orange.withOpacity(0.1)
                        : colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRecording
                    ? Iconsax.record_circle
                    : hasRecording
                    ? Iconsax.microphone_2
                    : isRetakeInProgress
                    ? Icons.refresh
                    : Iconsax.microphone,
                color:
                    isRecording
                        ? Colors.red
                        : hasRecording
                        ? Colors.green
                        : isRetakeInProgress
                        ? Colors.orange
                        : colorScheme.primary,
                size: 20,
              ),
            ),

            SizedBox(width: 8),

            // Status Text
            Text(
              isRetakeInProgress
                  ? 'Retake'
                  : widget.classId != null
                  ? (isRecording
                      ? 'Class Rec...'
                      : hasRecording
                      ? 'Class Ready'
                      : 'Class Rec')
                  : (isRecording
                      ? 'Recording...'
                      : hasRecording
                      ? 'Recording Ready'
                      : 'Ready to Record'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),

            SizedBox(width: 8),

            // Timer when recording
            if (isRecording)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_recordingSeconds ~/ 60}:${(_recordingSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),

            SizedBox(width: 8),

            // Start Recording Button (when not recording and no recording exists)
            if (!isRecording && !hasRecording)
              Tooltip(
                message: 'Start Recording',
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isRetakeInProgress
                            ? Colors.orange
                            : colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      isRetakeInProgress ? Icons.refresh : Iconsax.microphone,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _startRecording,
                  ),
                ),
              ),

            // Stop Recording Button (when recording)
            if (isRecording)
              Tooltip(
                message: 'Stop Recording',
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Iconsax.stop, color: Colors.white, size: 20),
                    onPressed: _stopRecording,
                  ),
                ),
              ),

            // Play/Pause Button (when has recording but not recording)
            if (!isRecording && hasRecording)
              Tooltip(
                message: _isPlayingPreview ? 'Pause' : 'Play',
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isPlayingPreview ? Iconsax.pause : Iconsax.play,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed:
                        _isPlayingPreview
                            ? _pausePreview
                            : _playRecordingPreview,
                  ),
                ),
              ),

            // Clear Button (when has recording)
            if (hasRecording && !isRecording)
              Tooltip(
                message: 'Clear Recording',
                child: IconButton(
                  icon: Icon(Iconsax.trash, size: 20, color: Colors.red),
                  onPressed: _clearRecording,
                ),
              ),

            // Submit Button (when has recording and not submitted)
            if (hasRecording && !isSubmitting)
              Tooltip(
                message:
                    isRetakeInProgress ? 'Submit Retake' : 'Submit Recording',
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isRetakeInProgress ? Colors.orange : Colors.green[700],
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      isRetakeInProgress ? Icons.refresh : Iconsax.send_2,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _submitRecording,
                  ),
                ),
              ),

            // Loading indicator during submission
            if (isSubmitting)
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),

            // Expand Button
            Tooltip(
              message: 'Expand',
              child: IconButton(
                icon: Icon(Iconsax.arrow_up_2, size: 20),
                onPressed: _toggleRecordingPanelMinimize,
              ),
            ),

            // Close Button
            Tooltip(
              message: 'Close',
              child: IconButton(
                icon: Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _showRecordingPanel = false;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlayer() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // Progress Bar
          Slider(
            value: _currentDuration.inSeconds.toDouble(),
            min: 0,
            max: _totalDuration.inSeconds.toDouble(),
            onChanged: (value) {
              _seekAudio(Duration(seconds: value.toInt()));
            },
            activeColor: colorScheme.primary,
            inactiveColor: colorScheme.primary.withOpacity(0.3),
          ),

          // Time and Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_currentDuration),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),

              Row(
                children: [
                  Tooltip(
                    message: 'Restart',
                    child: IconButton(
                      icon: Icon(Iconsax.previous, size: 20),
                      onPressed: () {
                        _seekAudio(Duration.zero);
                      },
                    ),
                  ),

                  Tooltip(
                    message: _isPlayingPreview ? 'Pause' : 'Play',
                    child: IconButton(
                      icon: Icon(
                        _isPlayingPreview ? Iconsax.pause : Iconsax.play,
                        size: 24,
                        color: colorScheme.primary,
                      ),
                      onPressed:
                          _isPlayingPreview
                              ? _pausePreview
                              : _playRecordingPreview,
                    ),
                  ),

                  Tooltip(
                    message: 'Stop',
                    child: IconButton(
                      icon: Icon(Iconsax.stop, size: 20),
                      onPressed: _stopPreview,
                    ),
                  ),
                ],
              ),

              Text(
                _formatDuration(_totalDuration),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Widget _buildPrerequisiteWarningCard() {
    if (_canAccessMaterial || !_hasPrerequisite) return SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final isClassContext = widget.classId != null && widget.classId!.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline,
                  color: Colors.amber[800],
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isClassContext
                          ? 'Class Material Locked'
                          : 'Material Locked',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber[800],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'You must complete the prerequisite reading first.',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.school, color: Colors.amber, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prerequisite Required',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber[800],
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _prerequisiteTitle ?? 'Previous Reading Material',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          Text(
            'Complete the prerequisite reading material before you can access this one. '
            'Your teacher has set up this learning path to help you progress effectively.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionStatusCard() {
    if (!_hasExistingRecording) return SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final isClassContext = widget.classId != null && widget.classId!.isNotEmpty;

    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusMessage;

    if (_isRetakeRequested) {
      statusColor = Colors.orange;
      statusIcon = Icons.refresh;
      statusText =
          isClassContext ? 'Retake Requested' : 'Retake Requested';
      statusMessage =
          'Your teacher wants you to retake this reading. Record your new reading.';
    } else if (_isRetakeApproved) {
      statusColor = Colors.blue;
      statusIcon = Icons.refresh;
      statusText = isClassContext ? 'Class Retake Approved' : 'Retake Approved';
      statusMessage =
          'Your teacher has approved a retake. You can record a new reading now.';
    } else if (_isGraded) {
      statusColor = Colors.green;
      statusIcon = Icons.grading;
      statusText = isClassContext ? 'Reading Graded' : 'Reading Graded';
      statusMessage = 'Your reading has been evaluated by your teacher.';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.access_time;
      statusText = isClassContext ? 'Class Reading Pending' : 'Reading Pending';
      statusMessage = 'Your reading is being reviewed by your teacher.';
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      statusMessage,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_teacherScore != null && _isGraded && !_isRetakeRequested) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Score',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '$_teacherScore/5',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color:
                              _teacherScore! >= 4
                                  ? Colors.green
                                  : _teacherScore! >= 3
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  if (_teacherScore! >= 4)
                    Icon(Icons.emoji_events, color: Colors.amber, size: 32)
                  else if (_teacherScore! >= 3)
                    Icon(Icons.thumb_up, color: Colors.orange, size: 32)
                  else
                    Icon(Icons.thumb_down, color: Colors.red, size: 32),
                ],
              ),
            ),
          ],

          if (_teacherFeedback.isNotEmpty &&
              _isGraded &&
              !_isRetakeRequested) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[100]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.feedback, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Teacher Feedback',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    _teacherFeedback,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Show retake recording button when retake is requested or approved
          if (_isRetakeRequested || _isRetakeApproved)
            Padding(
              padding: EdgeInsets.only(top: 16),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showRecordingPanel = true;
                  });
                },
                icon: Icon(Icons.mic, size: 18),
                label: Text('Record Retake Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isClassContext = widget.classId != null && widget.classId!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class Context Badge
          if (isClassContext)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.class_, size: 18, color: colorScheme.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reading Assignment',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  // Add audio indicator if teacher audio exists (moved here)
                  if (_teacherAudioUrl != null && _teacherAudioUrl!.isNotEmpty)
                    Tooltip(
                      message: 'Has teacher audio instructions',
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.purple[100],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.volume_up,
                          size: 16,
                          color: Colors.purple[700],
                        ),
                      ),
                    ),
                  SizedBox(width: 8),
                  Text(
                    'Required',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: isClassContext ? 16 : 0),

          // Prerequisite Warning Card
          _buildPrerequisiteWarningCard(),

          // Teacher Audio Player - This will display if teacher audio exists
          _buildTeacherAudioPlayer(),

          // Submission Status Card
          _buildSubmissionStatusCard(),
          // Material Description
          if (widget.material['description'] != null &&
              widget.material['description'].toString().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withOpacity(0.05),
                    colorScheme.secondary.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description, color: colorScheme.primary),
                      SizedBox(width: 8),
                      Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    widget.material['description'],
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: 24),

          // Reading Material Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
              border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row with Flexible Layout
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxWidth < 400;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              Icon(
                                _isPdf
                                    ? Iconsax.book_1
                                    : _isImage
                                    ? Iconsax.gallery
                                    : Iconsax.document,
                                color: colorScheme.primary,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  isClassContext
                                      ? (_isPdf
                                          ? 'Reading Material (PDF)'
                                          : _isImage
                                          ? 'Reading Material (Image)'
                                          : 'Reading Material')
                                      : (_isPdf
                                          ? 'Reading Material (PDF)'
                                          : _isImage
                                          ? 'Reading Material (Image)'
                                          : 'Reading Material'),
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 18 : 22,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        if ((localFilePath != null &&
                                File(localFilePath!).existsSync()) ||
                            (fileUrl != null && fileUrl!.isNotEmpty))
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: isSmallScreen ? 120 : 140,
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _toggleFullView,
                              icon: Icon(
                                Icons.fullscreen,
                                size: isSmallScreen ? 16 : 18,
                              ),
                              label:
                                  isSmallScreen
                                      ? SizedBox() // Hide text on small screens
                                      : Text(
                                        'Full Screen',
                                        style: TextStyle(fontSize: 14),
                                      ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isSmallScreen ? 12 : 16,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 2,
                                minimumSize: Size(isSmallScreen ? 48 : 0, 40),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 16),

                // File Preview with Controls
                Container(
                  height: 500,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.3),
                    ),
                    color: colorScheme.surfaceVariant,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        _buildFileViewer(),

                        // PDF Controls Overlay (only for PDFs)
                        if (_isPdf)
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.zoom_in,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      _pdfViewerController.zoomLevel =
                                          (_pdfViewerController.zoomLevel ??
                                              1.0) +
                                          0.2;
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.zoom_out,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      final currentZoom =
                                          _pdfViewerController.zoomLevel ?? 1.0;
                                      if (currentZoom > 0.5) {
                                        _pdfViewerController.zoomLevel =
                                            currentZoom - 0.2;
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.fit_screen,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      _pdfViewerController.zoomLevel = 1.0;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 12),
                Text(
                  isClassContext
                      ? (_isPdf
                          ? 'Class assignment: Read this material and record your reading for evaluation.'
                          : _isImage
                          ? 'Class assignment: Study this image and record your reading for evaluation.'
                          : 'Class reading assignment. Record your reading for evaluation.')
                      : (_isPdf
                          ? 'Tip: Use pinch to zoom, pan to navigate, or tap the full screen button for better reading experience.'
                          : _isImage
                          ? 'Tip: Pinch to zoom and pan to navigate the image. Use full screen for better viewing.'
                          : 'File preview'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          // // Recording Tools Button (when not showing floating panel and can record)
          // if (_canAccessMaterial && _canRecordAgain && !_showRecordingPanel)
          //   Container(
          //     width: double.infinity,
          //     padding: const EdgeInsets.only(top: 32),
          //     child: Column(
          //       crossAxisAlignment: CrossAxisAlignment.start,
          //       children: [
          //         Text(
          //           _isRetakeRequested || _isRetakeApproved
          //               ? (isClassContext
          //                   ? 'Class Retake Required'
          //                   : 'Retake Required')
          //               : isClassContext
          //               ? 'Class Recording Required'
          //               : 'Reading Recording',
          //           style: TextStyle(
          //             fontSize: 16,
          //             fontWeight: FontWeight.w600,
          //             color: colorScheme.onSurface,
          //           ),
          //         ),
          //         SizedBox(height: 8),
          //         ElevatedButton.icon(
          //           onPressed: _toggleRecordingPanel,
          //           icon: Icon(
          //             (_isRetakeRequested || _isRetakeApproved)
          //                 ? Icons.refresh
          //                 : Iconsax.microphone_2,
          //           ),
          //           label: Text(
          //             (_isRetakeRequested || _isRetakeApproved)
          //                 ? (isClassContext
          //                     ? 'Record Class Retake'
          //                     : 'Record Retake')
          //                 : isClassContext
          //                 ? 'Record Class Reading'
          //                 : 'Open Recording Tools',
          //           ),
          //           style: ElevatedButton.styleFrom(
          //             backgroundColor:
          //                 (_isRetakeRequested || _isRetakeApproved)
          //                     ? Colors.orange
          //                     : colorScheme.primary,
          //             foregroundColor: Colors.white,
          //             padding: EdgeInsets.symmetric(vertical: 16),
          //             shape: RoundedRectangleBorder(
          //               borderRadius: BorderRadius.circular(12),
          //             ),
          //           ),
          //         ),
          //       ],
          //     ),
          //   ),

          // Locked Message (when cannot access)
          if (!_canAccessMaterial)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Material Locked',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.amber[800]),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Complete "$_prerequisiteTitle" to unlock this material',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.amber[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isClassContext = widget.classId != null && widget.classId!.isNotEmpty;
    final isRetakeRequired = _isRetakeRequested || _isRetakeApproved;

    if (isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              SizedBox(height: 16),
              Text(
                isClassContext
                    ? 'Loading Class Reading Material...'
                    : 'Loading Reading Material...',
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_showFullView) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            isClassContext
                ? '${widget.material['title'] ?? 'Reading Material'}'
                : widget.material['title'] ?? 'Reading Material',
            style: TextStyle(color: colorScheme.onPrimary),
          ),
          backgroundColor: colorScheme.primary,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colorScheme.onPrimary),
            onPressed: _toggleFullView,
          ),
          actions: [
            // PDF-specific controls
            if (_isPdf) ...[
              IconButton(
                icon: Icon(Icons.zoom_in, color: colorScheme.onPrimary),
                onPressed: () {
                  _pdfViewerController.zoomLevel = 1.5;
                },
              ),
              IconButton(
                icon: Icon(Icons.zoom_out, color: colorScheme.onPrimary),
                onPressed: () {
                  _pdfViewerController.zoomLevel = 1.0;
                },
              ),
              IconButton(
                icon: Icon(Icons.fit_screen, color: colorScheme.onPrimary),
                onPressed: () {
                  _pdfViewerController.zoomLevel = 1.0;
                },
              ),
            ],
            // Recording tools button for all file types when user can record
            if (_canAccessMaterial && _canRecordAgain && !isSubmitting)
              IconButton(
                icon: Icon(
                  _showRecordingPanel ? Icons.close : Iconsax.microphone_2,
                  color: colorScheme.onPrimary,
                ),
                onPressed: () {
                  if (_canAccessMaterial) {
                    setState(() {
                      _showRecordingPanel = !_showRecordingPanel;
                      _isRecordingPanelMinimized = false;
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Complete the prerequisite "$_prerequisiteTitle" first',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
              ),
          ],
        ),
        body: Stack(
          children: [
            _buildFileViewer(),
            // Ensure recording panel is on top
            _buildFloatingRecordingPanel(),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isClassContext
              ? '${widget.material['title'] ?? 'Class Reading Material'}'
              : widget.material['title'] ?? 'Reading Material',
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: colorScheme.primary,
        elevation: 0,
        foregroundColor: colorScheme.onPrimary,
      ),
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          _buildMainContent(context),
          // Ensure recording panel is on top
          _buildFloatingRecordingPanel(),
        ],
      ),
      // FIXED: Floating Action Button logic
      floatingActionButton:
          // Show recording tools button when user can record and not currently showing panel
          !_showRecordingPanel &&
                  _canAccessMaterial &&
                  _canRecordAgain &&
                  !isSubmitting
              ? FloatingActionButton.extended(
                onPressed: _toggleRecordingPanel,
                icon: Icon(
                  isRetakeRequired ? Icons.refresh : Iconsax.microphone_2,
                ),
                label: Text(
                  isRetakeRequired
                      ? (isClassContext ? 'Retake' : 'Retake')
                      : isClassContext
                      ? 'Record'
                      : 'Recording Tools',
                ),
                backgroundColor:
                    isRetakeRequired ? Colors.orange : colorScheme.primary,
                foregroundColor: Colors.white,
              )
              // Show submitting indicator during submission
              : isSubmitting
              ? FloatingActionButton.extended(
                onPressed: null,
                icon: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                label: Text('Submitting...'),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              )
              // Show "Submitted" button when there's an existing recording and user cannot record again
              // BUT NOT when retake is required or material is locked
              : _hasExistingRecording &&
                  !_canRecordAgain &&
                  !isRetakeRequired &&
                  _canAccessMaterial
              ? FloatingActionButton.extended(
                onPressed: null,
                icon: Icon(Icons.check_circle, color: Colors.white),
                label: Text('Submitted'),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              )
              // Show "Locked" button when material cannot be accessed
              : !_canAccessMaterial
              ? FloatingActionButton.extended(
                onPressed: null,
                icon: Icon(Icons.lock, color: Colors.white),
                label: Text('Locked'),
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
              )
              : null,
    );
  }

  Widget _buildTeacherAudioPlayer() {
    if (_teacherAudioUrl == null || _teacherAudioUrl!.isEmpty)
      return SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.volume_up,
                  color: Colors.purple[700],
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Teacher\'s Instructions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple[800],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Listen to your teacher\'s reading instructions',
                      style: TextStyle(fontSize: 14, color: Colors.purple[600]),
                    ),
                  ],
                ),
              ),
              if (_isLoadingTeacherAudio)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.purple,
                  ),
                ),
            ],
          ),

          SizedBox(height: 16),

          // Audio Player
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple[100]!),
            ),
            child: Column(
              children: [
                // Progress Bar
                Slider(
                  value: _teacherAudioCurrentDuration.inSeconds.toDouble(),
                  min: 0,
                  max: _teacherAudioTotalDuration.inSeconds.toDouble(),
                  onChanged: (value) {
                    _seekTeacherAudio(Duration(seconds: value.toInt()));
                  },
                  activeColor: Colors.purple,
                  inactiveColor: Colors.purple.withOpacity(0.3),
                ),

                // Time and Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_teacherAudioCurrentDuration),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),

                    Row(
                      children: [
                        Tooltip(
                          message: 'Restart',
                          child: IconButton(
                            icon: Icon(Iconsax.previous, size: 20),
                            onPressed: () {
                              _seekTeacherAudio(Duration.zero);
                            },
                          ),
                        ),

                        Tooltip(
                          message: _isPlayingTeacherAudio ? 'Pause' : 'Play',
                          child: IconButton(
                            icon: Icon(
                              _isPlayingTeacherAudio
                                  ? Iconsax.pause
                                  : Iconsax.play,
                              size: 24,
                              color: Colors.purple,
                            ),
                            onPressed:
                                _isPlayingTeacherAudio
                                    ? _pauseTeacherAudio
                                    : _playTeacherAudio,
                          ),
                        ),

                        Tooltip(
                          message: 'Stop',
                          child: IconButton(
                            icon: Icon(Iconsax.stop, size: 20),
                            onPressed: _stopTeacherAudio,
                          ),
                        ),
                      ],
                    ),

                    Text(
                      _formatDuration(_teacherAudioTotalDuration),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 12),

          Text(
            'Tip: Listen carefully to your teacher\'s pronunciation and reading pace before recording your own.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
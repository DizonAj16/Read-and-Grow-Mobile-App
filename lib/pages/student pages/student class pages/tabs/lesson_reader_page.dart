import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:photo_view/photo_view.dart';
import 'package:deped_reading_app_laravel/api/comprehension_quiz_service.dart';
import 'package:deped_reading_app_laravel/pages/student%20pages/student%20class%20pages/tabs/student_quiz_pages.dart';

class LessonReaderPage extends StatefulWidget {
  final String taskId;
  final String assignmentId;
  final String classRoomId;
  final String quizId;
  final String studentId;
  final String lessonTitle;
  final bool viewOnly;
  final bool fromQuizReview; // NEW: Flag to identify if coming from quiz review

  const LessonReaderPage({
    super.key,
    required this.taskId,
    required this.assignmentId,
    required this.classRoomId,
    required this.quizId,
    required this.studentId,
    required this.lessonTitle,
    this.viewOnly = false,
    this.fromQuizReview = false, // NEW: Default to false
  });

  @override
  State<LessonReaderPage> createState() => _LessonReaderPageState();
}

class _LessonReaderPageState extends State<LessonReaderPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ComprehensionQuizService _quizService = ComprehensionQuizService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isLoading = true;
  bool _isCompleting = false;
  String? _fileUrl;
  String? _fileType; // 'pdf', 'image', 'video', 'audio'
  int? _materialId;
  String? _materialDescription;

  // Video player controller
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  // Full-screen state
  bool _isFullScreen = false;

  // Audio state
  bool _isAudioPlaying = false;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadMaterial();
    _setupAudioListeners();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _setupAudioListeners() {
    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((Duration duration) {
      if (mounted) {
        setState(() {
          _audioDuration = duration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((Duration position) {
      if (mounted) {
        setState(() {
          _audioPosition = position;
        });
      }
    });
  }

  Future<void> _loadMaterial() async {
    debugPrint('--- START _loadMaterial ---');
    debugPrint('taskId: ${widget.taskId}');
    debugPrint('classRoomId: ${widget.classRoomId}');
    debugPrint(
      'fromQuizReview: ${widget.fromQuizReview}',
    ); // NEW: Log the source

    try {
      // Fetch material from task_materials
      final materialRes =
          await _supabase
              .from('task_materials')
              .select(
                'material_title, description, material_file_path, material_type',
              )
              .eq('task_id', widget.taskId)
              .maybeSingle();

      debugPrint('materialRes: $materialRes');

      if (materialRes != null) {
        _materialDescription = materialRes['description'] as String?;
        final filePath = materialRes['material_file_path'] as String?;
        _fileType = materialRes['material_type'] as String?;

        debugPrint('material description: $_materialDescription');
        debugPrint('filePath: $filePath');
        debugPrint('fileType: $_fileType');

        if (filePath != null && filePath.isNotEmpty) {
          final publicUrl = _supabase.storage
              .from('materials')
              .getPublicUrl(filePath);

          debugPrint('publicUrl: $publicUrl');

          if (publicUrl.isNotEmpty) {
            // Fetch material row from materials table
            final materialRow =
                await _supabase
                    .from('materials')
                    .select('id')
                    .eq('material_file_url', publicUrl)
                    .eq('class_room_id', widget.classRoomId)
                    .order('created_at', ascending: false)
                    .maybeSingle();

            debugPrint('materialRow: $materialRow');

            if (materialRow != null) {
              final dynamic idValue = materialRow['id'];
              debugPrint('materialRow id raw: $idValue');

              if (idValue is int) {
                _materialId = idValue;
              } else if (idValue is num) {
                _materialId = idValue.toInt();
              }

              debugPrint('parsed materialId: $_materialId');
            }

            setState(() {
              _fileUrl = publicUrl;
            });

            debugPrint('fileUrl set: $_fileUrl');

            // Initialize video player if it's a video
            if (_fileType == 'video' && _fileUrl != null) {
              debugPrint('Initializing video player...');
              _initializeVideoPlayer();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading lesson material: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('_isLoading set to false');
      }
    }

    debugPrint('--- END _loadMaterial ---');
  }

  Future<void> _initializeVideoPlayer() async {
    if (_fileUrl == null) return;

    _videoController = VideoPlayerController.networkUrl(Uri.parse(_fileUrl!));
    await _videoController!.initialize();

    if (mounted) {
      setState(() {
        _isVideoInitialized = true;
      });
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
  }

  Future<void> _handleDoneReading() async {
    if (_isCompleting) return;

    setState(() => _isCompleting = true);

    try {
      if (_materialId != null) {
        await _quizService.completeLessonReading(
          studentId: widget.studentId,
          materialId: _materialId!,
          readingDurationSeconds: 0,
          pagesViewed: 0,
          lastPageViewed: 0,
        );
      }
    } catch (e) {
      debugPrint('Error completing lesson reading: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark lesson as read: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }

    await _openQuiz();
  }

  Future<void> _openQuiz() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => StudentQuizPage(
              quizId: widget.quizId,
              assignmentId: widget.assignmentId,
              studentId: widget.studentId,
              lessonTitle: widget.lessonTitle,
              taskId: widget.taskId,
              classRoomId: widget.classRoomId,
            ),
      ),
    );

    if (!mounted) return;
    Navigator.pop(context, result);
  }

  Widget _buildMaterialContent() {
    if (_fileUrl == null) {
      return _buildNoMaterialView();
    }

    switch (_fileType) {
      case 'pdf':
        return _buildPdfViewer();

      case 'image':
        return _buildImageViewer();

      case 'video':
        return _buildVideoPlayer();

      case 'audio':
        return _buildAudioPlayer();

      default:
        return _buildUnsupportedFileView();
    }
  }

  Widget _buildPdfViewer() {
    return Stack(
      children: [
        SfPdfViewer.network(
          _fileUrl!,
          canShowScrollHead: true,
          canShowScrollStatus: true,
          scrollDirection: PdfScrollDirection.vertical,
          interactionMode: PdfInteractionMode.pan,
          enableDoubleTapZooming: true,
          pageLayoutMode: PdfPageLayoutMode.single,
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: _toggleFullScreen,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(
              _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageViewer() {
    return GestureDetector(
      onTap: _toggleFullScreen,
      child: Stack(
        children: [
          PhotoView(
            imageProvider: NetworkImage(_fileUrl!),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 3.0,
            initialScale: PhotoViewComputedScale.contained,
            backgroundDecoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            loadingBuilder:
                (context, event) => Center(
                  child: CircularProgressIndicator(
                    value:
                        event == null
                            ? 0
                            : event.cumulativeBytesLoaded /
                                event.expectedTotalBytes!,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            errorBuilder:
                (context, error, stackTrace) => Container(
                  height: 300,
                  color: Colors.grey[200],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _toggleFullScreen,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(
                _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
          if (!_isFullScreen)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in, size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Pinch to zoom',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (!_isVideoInitialized || _videoController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _toggleFullScreen,
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
            if (!_isFullScreen) _buildVideoControls(),
          ],
        ),
        Positioned(
          bottom: _isFullScreen ? 16 : 80,
          right: 16,
          child: FloatingActionButton(
            onPressed: _toggleFullScreen,
            backgroundColor: Theme.of(context).colorScheme.primary,
            mini: true,
            child: Icon(
              _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoControls() {
      final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: colorScheme.surface,
      child: Column(
        children: [
          VideoProgressIndicator(
            _videoController!,
            allowScrubbing: true,
            colors: VideoProgressColors(
              playedColor: Theme.of(context).colorScheme.primary,
              bufferedColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.3),
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _videoController!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_videoController!.value.isPlaying) {
                          _videoController!.pause();
                        } else {
                          _videoController!.play();
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.replay_10,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () {
                      final newPosition =
                          _videoController!.value.position -
                          Duration(seconds: 10);
                      _videoController!.seekTo(newPosition);
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.forward_10,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () {
                      final newPosition =
                          _videoController!.value.position +
                          Duration(seconds: 10);
                      _videoController!.seekTo(newPosition);
                    },
                  ),
                ],
              ),
              Text(
                '${_formatDuration(_videoController!.value.position)} / ${_formatDuration(_videoController!.value.duration)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayer() {
      final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                colorScheme.primary,
                colorScheme.primaryContainer,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              _isAudioPlaying ? Icons.music_note : Icons.music_off,
              size: 48,
              color: colorScheme.onPrimary,
            ),
          ),
          SizedBox(height: 32),
          Text(
            'Audio Lesson',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Listen to the audio material carefully',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 32),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor:
                        Theme.of(context).colorScheme.surfaceVariant,
                    thumbColor: Theme.of(context).colorScheme.primary,
                    overlayColor: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.2),
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 20),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _audioPosition.inSeconds.toDouble(),
                    min: 0,
                    max: _audioDuration.inSeconds.toDouble(),
                    onChanged: (value) {
                      _audioPlayer.seek(Duration(seconds: value.toInt()));
                    },
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_audioPosition),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDuration(_audioDuration),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.replay_10),
                      iconSize: 30,
                      color: Theme.of(context).colorScheme.onSurface,
                      onPressed: () {
                        final newPosition =
                            _audioPosition - Duration(seconds: 10);
                        _audioPlayer.seek(newPosition);
                      },
                    ),
                    SizedBox(width: 20),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primaryContainer,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isAudioPlaying ? Icons.pause : Icons.play_arrow,
                          size: 36,
                        ),
                        color: Theme.of(context).colorScheme.onPrimary,
                        onPressed: () async {
                          if (_isAudioPlaying) {
                            await _audioPlayer.pause();
                          } else {
                            await _audioPlayer.play(UrlSource(_fileUrl!));
                          }
                        },
                      ),
                    ),
                    SizedBox(width: 20),
                    IconButton(
                      icon: Icon(Icons.forward_10),
                      iconSize: 30,
                      color: Theme.of(context).colorScheme.onSurface,
                      onPressed: () {
                        final newPosition =
                            _audioPosition + Duration(seconds: 10);
                        _audioPlayer.seek(newPosition);
                      },
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  // NEW: Handle navigation back based on source
  // Updated back navigation logic
  // Updated back navigation logic
  void _handleBackNavigation() {
    debugPrint('🎯 [BACK] Handling back navigation');
    debugPrint('🎯 [BACK] fromQuizReview: ${widget.fromQuizReview}');
    debugPrint('🎯 [BACK] viewOnly: ${widget.viewOnly}');

    if (widget.fromQuizReview) {
      // Coming from quiz review - go back to ClassContentScreen
      // We need to return a special result and let ClassContentScreen handle the navigation
      Navigator.of(context).pop('back_to_class_content');
    } else if (widget.viewOnly) {
      // Regular viewOnly mode - just close the material
      Navigator.of(context).pop();
    } else {
      // Regular lesson flow - just go back
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _isFullScreen
              ? null
              : AppBar(
                title: Text(
                  widget.lessonTitle,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
                centerTitle: true,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: _handleBackNavigation, // Updated
                ),
              ),
      // In the build() method, update the bottomNavigationBar for viewOnly mode:
      bottomNavigationBar:
          _isFullScreen
              ? null
              : SafeArea(
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.1),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child:
                      widget.viewOnly
                          ? // When in viewOnly mode
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _handleBackNavigation, // Updated
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    elevation: 3,
                                    shadowColor: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.3),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.arrow_back,
                                        size: 20,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        widget.fromQuizReview
                                            ? 'Back to Lessons' // Updated text
                                            : 'Close Material',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                          : // Normal mode - single button for regular lesson flow
                          ElevatedButton.icon(
                            onPressed:
                                _isCompleting ? null : _handleDoneReading,
                            icon:
                                _isCompleting
                                    ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                      ),
                                    )
                                    : Icon(Icons.quiz, size: 22),
                            label: Text(
                              _fileUrl == null
                                  ? 'Proceed to Quiz'
                                  : 'Done Reading • Take Quiz',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              elevation: 4,
                              shadowColor: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.3),
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
                      strokeWidth: 2,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading lesson material...',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
              : Container(
                color:
                    _isFullScreen
                        ? Colors.black
                        : Theme.of(context).scaffoldBackgroundColor,
                child: Column(
                  children: [
                    Expanded(child: _buildMaterialContent()),
                    if (_materialDescription != null &&
                        _materialDescription!.isNotEmpty &&
                        !_isFullScreen)
                      Container(
                        margin: EdgeInsets.all(16),
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _materialDescription!,
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_isFullScreen) SizedBox(height: 8),
                  ],
                ),
              ),
    );
  }

  Widget _buildNoMaterialView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surfaceVariant,
              ),
              child: Icon(
                Icons.menu_book,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No reading material was attached to this lesson.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'You can still proceed to the quiz.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedFileView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.errorContainer,
              ),
              child: Icon(
                Icons.error_outline,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Unsupported file type',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'File type: ${_fileType ?? 'unknown'}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back),
              label: Text('Go Back'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

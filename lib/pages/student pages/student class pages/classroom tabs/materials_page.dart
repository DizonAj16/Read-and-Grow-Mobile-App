import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:deped_reading_app_laravel/api/material_service.dart';
import 'package:deped_reading_app_laravel/constants.dart';
import 'package:deped_reading_app_laravel/models/material_model.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/pdf%20helper/pdf_viewer.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:photo_view/photo_view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MaterialsPage extends StatefulWidget {
  final String classId;
  const MaterialsPage({super.key, required this.classId});

  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends State<MaterialsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late List<MaterialModel> _materials;
  late bool _isLoading;
  late bool _hasError;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeState();
    _loadMaterials();
  }

  void _initializeState() {
    _materials = [];
    _isLoading = true;
    _hasError = false;
  }

  Future<void> _loadMaterials() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final data = await MaterialService.getClassroomMaterials(widget.classId);

      if (!mounted) return; // ✅ guard after await
      setState(() {
        _materials = data;
      });

      debugPrint("✅ Materials loaded: ${data.length}");
    } catch (e) {
      debugPrint("❌ Error loading materials: $e");
      if (!mounted) return; // ✅ guard after await
      setState(() {
        _hasError = true;
      });
    } finally {
      if (mounted) {
        // ✅ guard in finally — this was the crash
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Get full file URL
  Future<String> _getFullFileUrl(String filePath) async {
    try {
      print('🟡 DEBUG: Getting full URL for path: $filePath');

      // Check if the URL is already a complete URL (starts with http)
      if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
        print('🟢 DEBUG: URL is already complete, returning as is');
        return filePath;
      }

      // If it's not a complete URL, then we need to construct it
      print('🟡 DEBUG: URL is not complete, constructing from base URL');
      final prefs = await SharedPreferences.getInstance();
      final baseUrlWithApi = prefs.getString('base_url') ?? '';

      print('🟡 DEBUG: Base URL from shared prefs: $baseUrlWithApi');

      if (baseUrlWithApi.isEmpty) {
        print('🔴 DEBUG: Base URL is empty in shared preferences');
        throw Exception('Base URL not found in shared preferences');
      }

      // Remove '/api' from the end if it exists
      String baseUrl = baseUrlWithApi;
      if (baseUrl.endsWith('/api')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 4);
        print('🟡 DEBUG: Removed /api from base URL: $baseUrl');
      } else if (baseUrl.endsWith('api')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 3);
        print('🟡 DEBUG: Removed api from base URL: $baseUrl');
      }

      // Ensure baseUrl doesn't end with slash and filePath doesn't start with slash
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        print('🟡 DEBUG: Removed trailing slash from base URL: $baseUrl');
      }

      String cleanFilePath = filePath;
      if (cleanFilePath.startsWith('/')) {
        cleanFilePath = cleanFilePath.substring(1);
        print('🟡 DEBUG: Removed leading slash from file path: $cleanFilePath');
      }

      final fullUrl = '$baseUrl/storage/$cleanFilePath';
      print('🟢 DEBUG: Final constructed URL: $fullUrl');

      return fullUrl;
    } catch (e) {
      print('🔴 DEBUG: Error getting full URL: $e');
      print('🔴 DEBUG: Returning original file path: $filePath');
      return filePath; // Return original if error
    }
  }

  // Download and open file with external app
  Future<void> _downloadAndOpenFile(
    MaterialModel material,
    String fullUrl,
  ) async {
    try {
      print('🟡 DEBUG: Starting download for: ${material.materialTitle}');
      print('🟡 DEBUG: Download URL: $fullUrl');

      _showLoadingSnackbar('Downloading ${material.materialTitle}...');

      final response = await http.get(Uri.parse(fullUrl));
      print('🟡 DEBUG: HTTP response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download file. Status: ${response.statusCode}',
        );
      }

      final bytes = response.bodyBytes;
      print('🟡 DEBUG: Downloaded ${bytes.length} bytes');

      final directory = await getTemporaryDirectory();

      // Get file extension from the URL
      final fileExtension = fullUrl.split('.').last;
      final file = File(
        '${directory.path}/${material.materialTitle}.$fileExtension',
      );

      print('🟡 DEBUG: Saving file to: ${file.path}');
      await file.writeAsBytes(bytes);

      print('🟡 DEBUG: Opening file with external app');
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      print('🟢 DEBUG: File opened successfully');
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      print('🔴 DEBUG: Error in _downloadAndOpenFile: $e');
      print('🔴 DEBUG: Error type: ${e.runtimeType}');
      _showErrorSnackbar("Error opening file: ${e.toString()}");
    }
  }

  void _showLoadingSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.blue,
        content: Row(
          children: [
            const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
            const SizedBox(width: 12),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
        duration: const Duration(minutes: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue[50],
      body: Column(
        children: [
          const _MaterialsHeader(),
          Expanded(
            child: RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: _loadMaterials,
              color: Colors.blue,
              backgroundColor: Colors.white,
              child: _ContentBuilder(
                isLoading: _isLoading,
                hasError: _hasError,
                materials: _materials,
                onRetry: _loadMaterials,
                onMaterialTap: _handleMaterialTap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.orange[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMaterialTap(MaterialModel material) async {
    if (!mounted) return;

    try {
      // DEBUG PRINT: Show material details
      print('🟡 DEBUG: Material tapped: ${material.materialTitle}');
      print('🟡 DEBUG: Material type: ${material.materialType}');
      print('🟡 DEBUG: Material file path: ${material.materialFileUrl}');
      print('🟡 DEBUG: Material ID: ${material.id}');
      print('🟡 DEBUG: Classroom ID: ${material.classRoomId}');
      print('🟡 DEBUG: Teacher: ${material.teacherName}');
      print('🟡 DEBUG: File size: ${material.fileSize}');
      if (material.description != null) {
        print('🟡 DEBUG: Description: ${material.description}');
      }

      // Get the complete URL
      final fullUrl = await _getFullFileUrl(material.materialFileUrl);
      print('🟡 DEBUG: Full URL constructed: $fullUrl');

      // Handle different material types
      if (material.materialType == 'pdf') {
        print('🟡 DEBUG: Opening PDF viewer');
        _navigateToPdfViewer(fullUrl);
      } else if (material.materialType == 'image') {
        print('🟡 DEBUG: Opening Image viewer');
        _navigateToImageViewer(fullUrl);
      } else if (material.materialType == 'video') {
        print('🟡 DEBUG: Opening Video viewer');
        _navigateToVideoViewer(fullUrl);
      } else if (material.materialType == 'audio') {
        print('🟡 DEBUG: Opening Audio viewer');
        _navigateToAudioViewer(fullUrl, material.materialTitle);
      } else {
        print(
          '🟡 DEBUG: Downloading document/archive: ${material.materialType}',
        );
        _downloadAndOpenFile(material, fullUrl);
      }
    } catch (e) {
      print('🔴 DEBUG: Error in _handleMaterialTap: $e');
      print('🔴 DEBUG: Error type: ${e.runtimeType}');
      _showErrorSnackbar("Error opening file: ${e.toString()}");
    }
  }

  void _navigateToPdfViewer(String url) {
    print('🟡 DEBUG: Navigating to PDF viewer with URL: $url');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PdfViewerPage(pdfUrl: url)),
    );
  }

  void _navigateToImageViewer(String imageUrl) {
    print('🟡 DEBUG: Navigating to Image viewer with URL: $imageUrl');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImageViewerPage(imageUrl: imageUrl)),
    );
  }

  void _navigateToVideoViewer(String videoUrl) {
    print('🟡 DEBUG: Navigating to Video viewer with URL: $videoUrl');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoViewerPage(videoUrl: videoUrl)),
    );
  }

  void _navigateToAudioViewer(String audioUrl, String title) {
    print('🟡 DEBUG: Navigating to Audio viewer with URL: $audioUrl');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioViewerPage(audioUrl: audioUrl, title: title),
      ),
    );
  }
}

// Image Viewer Page
class ImageViewerPage extends StatelessWidget {
  final String imageUrl;

  const ImageViewerPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Viewer'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: PhotoView(
          imageProvider: NetworkImage(imageUrl),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 2,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
        ),
      ),
    );
  }
}

// Video Viewer Page
class VideoViewerPage extends StatefulWidget {
  final String videoUrl;

  const VideoViewerPage({super.key, required this.videoUrl});

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      print('🟡 DEBUG: Initializing video player with URL: ${widget.videoUrl}');

      _videoPlayerController = VideoPlayerController.network(widget.videoUrl);

      await _videoPlayerController.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('🔴 DEBUG: Video initialization timeout');
          throw TimeoutException('Video took too long to load');
        },
      );

      print('🟢 DEBUG: Video controller initialized successfully');
      print(
        '🟢 DEBUG: Video duration: ${_videoPlayerController.value.duration}',
      );

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        errorBuilder: (context, errorMessage) {
          print('🔴 DEBUG: Chewie error builder: $errorMessage');
          return Center(
            child: Text(
              'Error playing video: $errorMessage',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );

      setState(() {
        _isLoading = false;
      });

      print('🟢 DEBUG: Video player setup completed');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      print('🔴 DEBUG: Video initialization error: $e');
      print('🔴 DEBUG: Error type: ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Player'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load video',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
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
}

// Audio Viewer Page
class AudioViewerPage extends StatefulWidget {
  final String audioUrl;
  final String title;

  const AudioViewerPage({
    super.key,
    required this.audioUrl,
    required this.title,
  });

  @override
  State<AudioViewerPage> createState() => _AudioViewerPageState();
}

class _AudioViewerPageState extends State<AudioViewerPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      print('🟡 DEBUG: Initializing audio player with URL: ${widget.audioUrl}');

      await _audioPlayer.setSource(UrlSource(widget.audioUrl));
      print('🟢 DEBUG: Audio source set successfully');

      _audioPlayer.onDurationChanged.listen((duration) {
        print('🟡 DEBUG: Audio duration: $duration');
        setState(() => _duration = duration);
      });

      _audioPlayer.onPositionChanged.listen((position) {
        setState(() => _position = position);
      });

      _audioPlayer.onPlayerComplete.listen((_) {
        print('🟡 DEBUG: Audio playback completed');
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      });
    } catch (e) {
      print('🔴 DEBUG: Audio initialization error: $e');
      print('🔴 DEBUG: Error type: ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.audiotrack, size: 80, color: Colors.white),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Slider(
              value: _position.inSeconds.toDouble(),
              min: 0,
              max: _duration.inSeconds.toDouble(),
              onChanged: (value) async {
                await _audioPlayer.seek(Duration(seconds: value.toInt()));
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.skip_previous,
                    size: 40,
                    color: Colors.white,
                  ),
                  onPressed: () {},
                ),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 60,
                    color: Colors.white,
                  ),
                  onPressed: () async {
                    if (_isPlaying) {
                      await _audioPlayer.pause();
                    } else {
                      await _audioPlayer.resume();
                    }
                    setState(() => _isPlaying = !_isPlaying);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.skip_next, size: 40, color: Colors.white),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return duration.inHours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}

class _MaterialsHeader extends StatelessWidget {
  const _MaterialsHeader();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: 140,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryColor, Color(0xFFB71C1C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Text(
            "Class Materials",
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentBuilder extends StatelessWidget {
  final bool isLoading;
  final bool hasError;
  final List<MaterialModel> materials;
  final VoidCallback onRetry;
  final Function(MaterialModel) onMaterialTap;

  const _ContentBuilder({
    required this.isLoading,
    required this.hasError,
    required this.materials,
    required this.onRetry,
    required this.onMaterialTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const _LoadingView();
    if (hasError) return _ErrorView(onRetry: onRetry);
    if (materials.isEmpty) return const _EmptyView();
    return _MaterialListView(
      materials: materials,
      onMaterialTap: onMaterialTap,
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/animation/loading_rainbow.json',
            width: 90,
            height: 90,
          ),
          const SizedBox(height: 20),
          const Text(
            "Loading materials...",
            style: TextStyle(fontSize: 16, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/animation/error.json', width: 150, height: 150),
          const SizedBox(height: 20),
          const Text(
            "Failed to load materials",
            style: TextStyle(
              fontSize: 18,
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: onRetry, child: const Text("Retry")),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/animation/empty_box.json',
                width: 220,
                height: 220,
              ),
              const SizedBox(height: 20),
              Text(
                "No Materials Yet!",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.blue[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  "Your teacher will add materials soon",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.blue[600]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MaterialListView extends StatelessWidget {
  final List<MaterialModel> materials;
  final Function(MaterialModel) onMaterialTap;

  const _MaterialListView({
    required this.materials,
    required this.onMaterialTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: materials.length,
      itemBuilder: (context, index) {
        return _MaterialCard(
          material: materials[index],
          onTap: () => onMaterialTap(materials[index]),
        );
      },
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final MaterialModel material;
  final VoidCallback onTap;

  const _MaterialCard({required this.material, required this.onTap});

  IconData _getMaterialIcon() {
    switch (material.materialType) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      case 'document':
        return Icons.article;
      case 'archive':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getMaterialColor() {
    switch (material.materialType) {
      case 'pdf':
        return Colors.red.shade500;
      case 'image':
        return Colors.green.shade500;
      case 'video':
        return Colors.purple.shade500;
      case 'audio':
        return Colors.orange.shade500;
      case 'document':
        return Colors.blue.shade500;
      case 'archive':
        return Colors.brown.shade500;
      default:
        return Colors.blueGrey.shade500;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final materialColor = _getMaterialColor();
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          splashColor: materialColor.withOpacity(0.2),
          highlightColor: materialColor.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: materialColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: materialColor.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    _getMaterialIcon(),
                    size: 28,
                    color: materialColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        material.materialTitle,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (material.description != null &&
                          material.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            material.description!,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.blueGrey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (material.fileSize != null)
                            Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  size: 14,
                                  color: Colors.blueGrey.shade400,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  material.fileSize!,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: Colors.blueGrey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          if (material.fileSize != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade300,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.blueGrey.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(material.createdAt),
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.blueGrey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: materialColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: onTap,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 20);

    final firstControlPoint = Offset(size.width / 4, size.height);
    final firstEndPoint = Offset(size.width / 2, size.height - 30);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    final secondControlPoint = Offset(
      size.width - (size.width / 4),
      size.height - 60,
    );
    final secondEndPoint = Offset(size.width, size.height - 20);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

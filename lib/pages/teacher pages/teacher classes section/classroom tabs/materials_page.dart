import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:deped_reading_app_laravel/api/material_service.dart';
import 'package:deped_reading_app_laravel/models/material_model.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:deped_reading_app_laravel/utils/file_validator.dart';
import 'package:shimmer/shimmer.dart';
import '../pdf helper/pdf_viewer.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:photo_view/photo_view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:http/http.dart' as http;
import 'package:deped_reading_app_laravel/utils/html_stub.dart'
    if (dart.library.html) 'package:deped_reading_app_laravel/utils/html_real.dart';

enum ActionType { view, edit, delete, add, archive }

class MaterialsPage extends StatefulWidget {
  final String classId;

  const MaterialsPage({super.key, required this.classId});

  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends State<MaterialsPage> {
  List<MaterialModel> _materials = [];
  bool _isLoading = true;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  bool _isDisposed = false;
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  static const double _maxUploadSizeMB = FileValidator.defaultMaxSizeMB;

  @override
  void initState() {
    super.initState();
    // Add minimum delay of 1.5 seconds for shimmer effect
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!_isDisposed) {
        _loadMaterials().then((_) {
          if (!_isDisposed) {}
        });
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    if (!mounted && !_isDisposed) return;

    setState(() => _isLoading = true);

    try {
      final materials = await MaterialService.getClassroomMaterials(
        widget.classId,
      );

      if (!mounted && !_isDisposed) return;

      setState(() {
        _materials = materials;
      });
    } catch (e) {
      print('❌ Error loading materials: $e');
      if (mounted) {
        _showErrorSnackbar("Error loading materials: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showUploadDialog() async {
    // Reset form fields
    _titleController.clear();
    _descriptionController.clear();
    _selectedFileBytes = null;
    _selectedFileName = null;

    await showDialog(
      context: context,
      builder: (context) => _buildUploadDialog(),
    );
  }

  Future<String?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true, // ← essential: gives us bytes on web AND native
    );

    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final bytes = picked.bytes; // Uint8List — works on web
    final name = picked.name; // filename with extension

    if (bytes == null) return 'Could not read file bytes.';

    final validation = FileValidator.validateBytes(
      bytes,
      limitMB: _maxUploadSizeMB,
    );
    if (!validation.isValid) {
      setState(() {
        _selectedFileBytes = null;
        _selectedFileName = null;
      });
      return validation.errorMessage;
    }

    setState(() {
      _selectedFileBytes = bytes;
      _selectedFileName = name;
    });
    return null; // no error
  }

  Future<void> _uploadMaterial() async {
    if (_selectedFileBytes == null || _selectedFileName == null) return;

    final validation = FileValidator.validateBytes(
      _selectedFileBytes!,
      limitMB: _maxUploadSizeMB,
    );
    if (!validation.isValid) {
      _showErrorSnackbar(validation.errorMessage ?? 'File too large');
      return;
    }

    final ext = _selectedFileName!.split('.').last.toLowerCase();
    final materialType = _determineMaterialType(ext);
    final sizeText = _formatFileSize(_selectedFileBytes!.lengthInBytes);

    Navigator.pop(context); // close upload dialog

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) =>
              _buildUploadingDialog(materialType, _selectedFileName!, sizeText),
    );

    try {
      final success = await MaterialService.uploadMaterialFile(
        fileBytes: _selectedFileBytes!,
        fileName: _selectedFileName!,
        materialTitle: _titleController.text,
        classroomId: widget.classId.toString(),
        materialType: materialType,
        description:
            _descriptionController.text.isNotEmpty
                ? _descriptionController.text
                : null,
      );

      if (!mounted) return;
      Navigator.pop(context); // close loading dialog

      if (success) {
        _showSuccessSnackbar("$materialType uploaded successfully!");
        await _loadMaterials();
      } else {
        _showErrorSnackbar("Failed to upload $materialType.");
      }
    } on FileSizeLimitException catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorSnackbar(e.message);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorSnackbar("Upload error: ${e.toString()}");
      }
    }
  }

  String _determineMaterialType(String extension) {
    switch (extension) {
      case 'pdf':
        return 'pdf';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
      case 'svg':
        return 'image';
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'mkv':
      case 'webm':
        return 'video';
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'm4a':
      case 'aac':
        return 'audio';
      case 'doc':
      case 'docx':
      case 'ppt':
      case 'pptx':
      case 'xls':
      case 'xlsx':
      case 'txt':
      case 'rtf':
        return 'document';
      case 'zip':
      case 'rar':
      case '7z':
        return 'archive';
      default:
        return 'document';
    }
  }

  Future<void> _confirmDelete(int id, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _buildDeleteConfirmationDialog(title),
    );

    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildDeletingDialog(),
    );

    try {
      final success = await MaterialService.deleteMaterial(id);

      if (!mounted) return;
      Navigator.pop(context);

      if (success) {
        _showSuccessSnackbar("Material deleted successfully!");
        await _loadMaterials();
      } else {
        _showErrorSnackbar("Failed to delete material.");
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorSnackbar("Delete error: ${e.toString()}");
      }
    }
  }

  // NEW: Function to view material in-app
  // NEW: Function to view material in-app
  Future<void> _viewMaterialInApp(MaterialModel material) async {
    try {
      // DEBUG PRINT: Show what URL is being used
      print('🟡 DEBUG: Attempting to view material: ${material.materialTitle}');
      print('🟡 DEBUG: Material type: ${material.materialType}');
      print('🟡 DEBUG: Material file URL: ${material.materialFileUrl}');

      switch (material.materialType) {
        case 'pdf':
          print('🟡 DEBUG: Opening PDF viewer');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PdfViewerPage(pdfUrl: material.materialFileUrl),
            ),
          );
          break;

        case 'image':
          print('🟡 DEBUG: Opening Image viewer');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ImageViewerPage(imageUrl: material.materialFileUrl),
            ),
          );
          break;

        case 'video':
          print('🟡 DEBUG: Opening Video viewer');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => VideoViewerPage(videoUrl: material.materialFileUrl),
            ),
          );
          break;

        case 'audio':
          print('🟡 DEBUG: Opening Audio viewer');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => AudioViewerPage(
                    audioUrl: material.materialFileUrl,
                    title: material.materialTitle,
                  ),
            ),
          );
          break;

        case 'document':
        case 'archive':
          print('🟡 DEBUG: Downloading document/archive');
          _downloadAndOpenFile(material);
          break;

        default:
          print('🟡 DEBUG: Downloading unknown file type');
          _downloadAndOpenFile(material);
      }
    } catch (e) {
      print('🔴 DEBUG: Error in _viewMaterialInApp: $e');
      _showErrorSnackbar("Error opening file: ${e.toString()}");
    }
  }

  // NEW: Download and open file with external app
  Future<void> _downloadAndOpenFile(MaterialModel material) async {
    if (kIsWeb) {
      final anchor =
          HtmlAnchorElement(href: material.materialFileUrl)
            ..setAttribute('download', material.materialTitle)
            ..target = '_blank';
      htmlDocument.body?.append(anchor);
      anchor.click();
      anchor.remove();
      return;
    }
    // Native fallback (unchanged)
    try {
      final response = await http.get(Uri.parse(material.materialFileUrl));
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${material.materialTitle}');
      await file.writeAsBytes(response.bodyBytes);
      await OpenFile.open(file.path);
    } catch (e) {
      _showErrorSnackbar("Error opening file: ${e.toString()}");
    }
  }

  Widget _buildUploadDialog() {
    String? errorMessage;

    return StatefulBuilder(
      builder: (context, setDialogState) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.25),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.upload_file,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Upload Material",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Text(
                    "Share learning materials with your class",
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Error message display
                  if (errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.orange[800]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                color: Colors.orange[800],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Title Field
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: "Material Title *",
                      labelStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.3),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Description Field
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: "Description (Optional)",
                      labelStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.3),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                    ),
                    maxLines: 3,
                  ),

                  const SizedBox(height: 20),

                  // File Picker Section label
                  Text(
                    "Select File *",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── File selection tap area ──────────────────────────────────
                  InkWell(
                    onTap: () async {
                      // _pickFile() now stores into _selectedFileBytes/_selectedFileName
                      final validationMessage = await _pickFile();
                      // Refresh dialog state so the selected-file card appears
                      setDialogState(() {
                        errorMessage = validationMessage;
                      });
                      if (validationMessage != null) {
                        _showErrorSnackbar(validationMessage);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_upload,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.7),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            // ✅ Check _selectedFileBytes instead of _selectedFile
                            _selectedFileBytes != null
                                ? "Change File"
                                : "Tap to select file",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Supported: PDF, Images, Videos, Audio, Documents",
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Selected file display card ───────────────────────────────
                  // ✅ Condition uses _selectedFileBytes + _selectedFileName
                  if (_selectedFileBytes != null &&
                      _selectedFileName != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          // ✅ Pass filename string instead of File.path
                          Icon(
                            _getFileIcon(_selectedFileName!),
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ✅ Use _selectedFileName directly (no .path.split('/').last)
                                Text(
                                  _selectedFileName!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // ✅ No FutureBuilder needed — size is already in bytes
                                Text(
                                  _formatFileSize(
                                    _selectedFileBytes!.lengthInBytes,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ✅ Clear button nulls out both new fields
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                            onPressed: () {
                              setDialogState(() {
                                _selectedFileBytes = null;
                                _selectedFileName = null;
                                errorMessage = null;
                              });
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          if (_titleController.text.trim().isEmpty) {
                            setDialogState(() {
                              errorMessage =
                                  "Please enter a title for the material";
                            });
                            return;
                          }
                          // ✅ Check _selectedFileBytes instead of _selectedFile
                          if (_selectedFileBytes == null) {
                            setDialogState(() {
                              errorMessage = "Please select a file to upload";
                            });
                            return;
                          }
                          _uploadMaterial();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text("Upload Material"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeleteConfirmationDialog(String title) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Delete Material',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.red,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
          const SizedBox(height: 16),
          Text(
            'Delete "$title"?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 16,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'This action cannot be undone',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Delete', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildUploadingDialog(
    String materialType,
    String fileName,
    String fileSize,
  ) {
    IconData icon;
    Color color;

    switch (materialType) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'image':
        icon = Icons.image;
        color = Colors.green;
        break;
      case 'video':
        icon = Icons.videocam;
        color = Colors.purple;
        break;
      case 'audio':
        icon = Icons.audiotrack;
        color = Colors.orange;
        break;
      case 'document':
        icon = Icons.article;
        color = Colors.blue;
        break;
      case 'archive':
        icon = Icons.folder;
        color = Colors.brown;
        break;
      default:
        icon = Icons.cloud_upload;
        color = Colors.blue;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated uploading icon
            Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  strokeWidth: 3,
                ),
                Icon(icon, size: 36, color: color),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              "Uploading ${materialType.toUpperCase()}",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              fileName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 4),

            Text(
              fileSize,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),

            const SizedBox(height: 16),

            Text(
              "Please wait...",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletingDialog() {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              "Deleting Material...",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.2),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _loadMaterials,
        color: colorScheme.primary,
        backgroundColor: colorScheme.surface,
        displacement: 40,
        edgeOffset: 20,
        child: _buildContent(),
      ),
      floatingActionButton:
          _isLoading
              ? null // Hide the real FAB when loading
              : FloatingActionButton(
                onPressed: _showUploadDialog,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.upload_file),
              ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }
    if (_materials.isEmpty) {
      return _buildEmptyState();
    }
    return _buildMaterialList();
  }

  Widget _buildLoadingState() {
    return Stack(
      children: [
        Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: 4, // Number of shimmer items to show
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              height: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 120,
                              height: 12,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                      Container(width: 24, height: 24, color: Colors.white),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Shimmer effect for Floating Action Button
        Positioned(
          bottom: 16,
          right: 16,
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 170, // Wider for "Upload Material"
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 24, height: 24, color: Colors.white),
                  const SizedBox(width: 8),
                  Container(width: 80, height: 16, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Lottie.asset(
                  'assets/animation/empty_box.json',
                  width: 200,
                  height: 200,
                ),
                const SizedBox(height: 24),
                Text(
                  "No Materials Available",
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    "Upload your first material by tapping the 'Upload Material' button below",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _materials.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final material = _materials[index];
        final materialColor = _getMaterialColor(material.materialType);

        return Material(
          borderRadius: BorderRadius.circular(16),
          elevation: 2,
          color: Theme.of(context).colorScheme.surface,
          shadowColor: Colors.black.withOpacity(0.1),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _viewMaterialInApp(material),
            splashColor: materialColor.withOpacity(0.1),
            highlightColor: materialColor.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File type icon with colored background
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: materialColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: materialColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      _getMaterialIcon(material.materialType),
                      color: materialColor,
                      size: 26,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Content area
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          material.materialTitle,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 6),

                        // Description
                        if (material.description != null &&
                            material.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              material.description!,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                                fontSize: 14,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        // File info row
                        Row(
                          children: [
                            // File type badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: materialColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                material.materialType.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: materialColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // File size
                            if (material.fileSize != null)
                              Text(
                                material.fileSize!,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Upload date and teacher info
                        Row(
                          children: [
                            // Upload date
                            if (material.createdAt != null)
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.4),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Uploaded: ${_formatDate(material.createdAt!)}",
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.5),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),

                            if (material.createdAt != null &&
                                material.teacherName.isNotEmpty)
                              const SizedBox(width: 12),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Options button
                  IconButton(
                    icon: Icon(
                      Icons.more_vert,
                      size: 22,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                    ),
                    onPressed:
                        () => _showMaterialOptionsModal(context, material),
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Helper method to format date nicely
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  IconData _getMaterialIcon(String materialType) {
    switch (materialType) {
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
        return Icons.folder;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getMaterialColor(String materialType) {
    switch (materialType) {
      case 'pdf':
        return Colors.red;
      case 'image':
        return Colors.green;
      case 'video':
        return Colors.purple;
      case 'audio':
        return Colors.orange;
      case 'document':
        return Colors.blue;
      case 'archive':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  void _showMaterialOptionsModal(BuildContext context, MaterialModel material) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Material info header
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _getMaterialColor(
                        material.materialType,
                      ).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getMaterialIcon(material.materialType),
                      color: _getMaterialColor(material.materialType),
                    ),
                  ),
                  title: Text(
                    material.materialTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${material.materialType.toUpperCase()} • ${material.fileSize ?? 'Unknown size'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),

                const Divider(height: 24),

                // View option for all supported types
                _buildActionTile(
                  context,
                  icon: Icons.visibility,
                  label: 'View ${material.materialType.toUpperCase()}',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    _viewMaterialInApp(material);
                  },
                ),

                // Download option for all types
                _buildActionTile(
                  context,
                  icon: Icons.download,
                  label: 'Download ${material.materialType.toUpperCase()}',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    _downloadAndOpenFile(material);
                  },
                ),

                // Delete option
                _buildActionTile(
                  context,
                  icon: Icons.delete,
                  label: 'Delete ${material.materialType.toUpperCase()}',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(material.id, material.materialTitle);
                  },
                ),

                const SizedBox(height: 8),

                // Cancel option
                _buildActionTile(
                  context,
                  icon: Icons.close,
                  label: 'Cancel',
                  color: Colors.grey,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB"];
  final i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
}

// Helper method to get file icon based on extension
IconData _getFileIcon(String filePath) {
  final extension = filePath.split('.').last.toLowerCase();
  switch (extension) {
    case 'pdf':
      return Icons.picture_as_pdf;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'bmp':
      return Icons.image;
    case 'mp4':
    case 'avi':
    case 'mov':
    case 'wmv':
      return Icons.videocam;
    case 'mp3':
    case 'wav':
    case 'ogg':
      return Icons.audiotrack;
    case 'doc':
    case 'docx':
      return Icons.article;
    case 'zip':
    case 'rar':
      return Icons.folder_zip;
    default:
      return Icons.insert_drive_file;
  }
}

// NEW: Image Viewer Page
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

// NEW: Video Viewer Page

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

      if (!_isValidUrl(widget.videoUrl)) {
        throw Exception('Invalid video URL');
      }

      // networkUrl works on both web and native (video_player >= 2.4)
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _videoPlayerController.initialize().timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException('Video took too long to load'),
      );

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Video playback error',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This may be due to HTTP restrictions on Android',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _openVideoExternally(widget.videoUrl),
                  child: const Text('Open in external player'),
                ),
              ],
            ),
          );
        },
      );

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            (e.toString().contains('Cleartext') ||
                    e.toString().contains('cleartext'))
                ? 'HTTP video playback blocked. '
                    'This is an Android security restriction. '
                    'Try using HTTPS or open in external player.'
                : e.toString();
      });
    }
  }

  // Web-safe external open
  Future<void> _openVideoExternally(String videoUrl) async {
    if (kIsWeb) {
      // Open in a new browser tab on web
      // ignore: avoid_web_libraries_in_flutter
      htmlWindow.open(videoUrl, '_blank');
      return;
    }
    // Native: download to temp dir and open with system player
    try {
      final response = await http.get(Uri.parse(videoUrl));
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/video_temp.mp4');
      await file.writeAsBytes(response.bodyBytes);
      await OpenFile.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open video: ${e.toString()}')),
        );
      }
    }
  }

  bool _isValidUrl(String url) {
    try {
      return Uri.parse(url).isAbsolute;
    } catch (_) {
      return false;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openVideoExternally(widget.videoUrl),
            tooltip: 'Open in external player',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Loading video...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Video playback failed',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _initializeVideo,
                child: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _openVideoExternally(widget.videoUrl),
                child: const Text('Open in external player'),
              ),
            ],
          ),
        ),
      );
    }

    return Chewie(controller: _chewieController!);
  }
}

// NEW: Audio Viewer Page
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
    await _audioPlayer.setSource(UrlSource(widget.audioUrl));

    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() => _duration = duration);
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() => _position = position);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
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

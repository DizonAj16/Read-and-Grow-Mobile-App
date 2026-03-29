import 'dart:async';
import 'package:deped_reading_app_laravel/models/quiz_questions.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuizPreviewScreen extends StatefulWidget {
  final String title;
  final List<QuizQuestion> questions;
  final String? taskId; // Add taskId to fetch lesson material
  final String? classRoomId; // Optional for class-specific materials

  const QuizPreviewScreen({
    super.key,
    required this.title,
    required this.questions,
    this.taskId,
    this.classRoomId,
  });

  @override
  State<QuizPreviewScreen> createState() => _QuizPreviewScreenState();
}

class _QuizPreviewScreenState extends State<QuizPreviewScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _lessonMaterials = [];
  bool _isLoadingMaterials = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLessonMaterials();
  }

Future<void> _loadLessonMaterials() async {
  if (widget.taskId == null) {
    setState(() {
      _isLoadingMaterials = false;
    });
    return;
  }

  try {
    List<Map<String, dynamic>> materials = [];

    // ONLY get materials from task_materials table (materials attached to this specific task)
    final taskMaterialsRes = await _supabase
        .from('task_materials')
        .select('*')
        .eq('task_id', widget.taskId!)
        .timeout(const Duration(seconds: 10));

    if (taskMaterialsRes != null && taskMaterialsRes.isNotEmpty) {
      for (var material in taskMaterialsRes) {
        String fileUrl = '';
        final filePath = material['material_file_path'] as String?;

        if (filePath != null && filePath.isNotEmpty) {
          try {
            // Get public URL from storage
            fileUrl = _supabase.storage
                .from('materials')
                .getPublicUrl(filePath);
          } catch (e) {
            debugPrint('Error getting file URL: $e');
          }
        }

        // Only add if we have a valid file URL
        if (fileUrl.isNotEmpty) {
          materials.add({
            'id': material['id'],
            'title': material['material_title'] ?? 'Lesson Material',
            'description': material['description'],
            'file_url': fileUrl,
            'file_path': filePath,
            'material_type': material['material_type'] ?? 'pdf',
          });
        }
      }
    }

    setState(() {
      _lessonMaterials = materials;
      _isLoadingMaterials = false;
    });
  } catch (e) {
    debugPrint('Error loading lesson materials: $e');
    setState(() {
      _isLoadingMaterials = false;
      _errorMessage = 'Failed to load lesson materials';
    });
  }
}

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    BuildContext context,
  ) {
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

  Widget _buildLessonMaterialsSection(BuildContext context) {
    if (_isLoadingMaterials) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_lessonMaterials.isEmpty) {
      return const SizedBox.shrink();
    }

    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Lesson Material', Icons.menu_book, context),
        const SizedBox(height: 8),
        ..._lessonMaterials.map((material) {
          return _buildMaterialCard(material, context);
        }).toList(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMaterialCard(
    Map<String, dynamic> material,
    BuildContext context,
  ) {
    final title = material['title'] ?? 'Untitled Material';
    final description = material['description'] as String?;
    final fileUrl = material['file_url'] as String? ?? '';
    final materialType =
        material['material_type']?.toString().toLowerCase() ?? 'pdf';
    final hasFile = fileUrl.isNotEmpty;
    final primaryColor = Theme.of(context).colorScheme.primary; // Add this line

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap:
            hasFile ? () => _viewMaterial(fileUrl, materialType, title) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getMaterialColor(materialType).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getMaterialIcon(materialType),
                  color: _getMaterialColor(materialType),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getMaterialColor(
                              materialType,
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            materialType.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _getMaterialColor(materialType),
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (hasFile)
                          Row(
                            children: [
                              Icon(
                                Icons.visibility,
                                size: 16,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'View',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _viewMaterial(
    String url,
    String materialType,
    String title,
  ) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file available to open'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => Scaffold(
                appBar: AppBar(
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                body: _getMaterialViewer(url, materialType),
              ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open material: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _getMaterialViewer(String url, String materialType) {
    try {
      switch (materialType) {
        case 'pdf':
          return SfPdfViewer.network(
            url,
            canShowScrollHead: true,
            canShowScrollStatus: true,
          );
        case 'image':
        case 'jpg':
        case 'jpeg':
        case 'png':
          return PhotoView(
            imageProvider: NetworkImage(url),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 2,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder:
                (context, event) => Center(
                  child: CircularProgressIndicator(
                    value:
                        event == null
                            ? null
                            : event.cumulativeBytesLoaded /
                                event.expectedTotalBytes!,
                  ),
                ),
          );
        case 'video':
          return _VideoPlayerWidget(videoUrl: url);
        default:
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Preview not available for .$materialType files',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Add download functionality if needed
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download started...')),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download File'),
                ),
              ],
            ),
          );
      }
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load file: $e',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
  }

  IconData _getMaterialIcon(String materialType) {
    switch (materialType) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      case 'image':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getMaterialColor(String materialType) {
    switch (materialType) {
      case 'pdf':
        return Colors.red[700]!;
      case 'video':
        return Colors.purple[700]!;
      case 'audio':
        return Colors.orange[700]!;
      case 'image':
        return Colors.green[700]!;
      default:
        return Colors.blue[700]!;
    }
  }

  Widget _buildQuestionImage(String? imageUrl, BuildContext context) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        const SizedBox(height: 12),
        Text(
          'Question Image:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageUrl,
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
                    color: primaryColor,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[100],
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.grey, size: 48),
                        SizedBox(height: 8),
                        Text('Failed to load image'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMultipleChoiceQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select the correct answer:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        ...q.options!.asMap().entries.map((entry) {
          final optIndex = entry.key;
          final option = entry.value;
          final isCorrect = option == q.correctAnswer;

          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isCorrect ? Colors.green : Colors.grey[300]!,
                width: isCorrect ? 2 : 1,
              ),
            ),
            child: ListTile(
              title: Text(
                option,
                style: TextStyle(
                  color: isCorrect ? Colors.green : null,
                  fontWeight: isCorrect ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCorrect ? Colors.green : Colors.grey[200],
                ),
                child: Icon(
                  isCorrect ? Icons.check : Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildMultipleChoiceWithImagesQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select the correct answer:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        ...q.options!.asMap().entries.map((entry) {
          final optIndex = entry.key;
          final option = entry.value;
          final isCorrect = option == q.correctAnswer;

          final optionImage = q.getOptionImage(optIndex);
          final hasOptionImage = optionImage != null && optionImage.isNotEmpty;

          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isCorrect ? Colors.green : Colors.grey[300]!,
                width: isCorrect ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasOptionImage)
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      border: Border.all(color: Colors.grey[300]!, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      child: Image.network(
                        optionImage!,
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
                              color: primaryColor,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[100],
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ListTile(
                  title: Text(
                    option.isNotEmpty ? option : 'Option ${optIndex + 1}',
                    style: TextStyle(
                      color: isCorrect ? Colors.green : null,
                      fontWeight:
                          isCorrect ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCorrect ? Colors.green : Colors.grey[200],
                    ),
                    child: Icon(
                      isCorrect ? Icons.check : Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: hasOptionImage ? 8 : 16,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildTrueFalseQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    final trueFalseOptions = q.options ?? ['True', 'False'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select the correct answer:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        ...trueFalseOptions.map((opt) {
          final isCorrect = opt == q.correctAnswer;
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isCorrect ? Colors.green : Colors.grey[300]!,
                width: isCorrect ? 2 : 1,
              ),
            ),
            child: ListTile(
              title: Text(
                opt,
                style: TextStyle(
                  color: isCorrect ? Colors.green : null,
                  fontWeight: isCorrect ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCorrect ? Colors.green : Colors.grey[200],
                ),
                child: Icon(
                  isCorrect ? Icons.check : Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildFillInTheBlankQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Correct Answer:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.green[700],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Text(
              q.correctAnswer ?? "No answer provided",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFillInTheBlankWithImageQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Correct Answer:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Text(
              q.correctAnswer ?? "No answer provided",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragAndDropQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Drag and Drop Items:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.orange[700],
            ),
          ),
          const SizedBox(height: 12),
          ...q.options!.map((opt) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.drag_handle, color: Colors.grey),
                title: Text(opt),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${q.options!.indexOf(opt) + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildMatchingQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Matching Pairs:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.purple[700],
            ),
          ),
          const SizedBox(height: 12),
          ...q.matchingPairs!.map((pair) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pair.leftItem,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.swap_horiz, color: Colors.purple),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple[100]!),
                        ),
                        child:
                            (pair.rightItemUrl != null &&
                                    pair.rightItemUrl!.isNotEmpty)
                                ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    pair.rightItemUrl!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Text('Failed to load image'),
                                      );
                                    },
                                  ),
                                )
                                : Center(
                                  child: Text(
                                    'No image',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAudioQuestion(QuizQuestion q, int index, BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.audiotrack, color: primaryColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Question',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
                Text(
                  'Playback not available in preview',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionContent(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    Widget content;

    switch (q.type) {
      case QuestionType.multipleChoice:
        content = _buildMultipleChoiceQuestion(q, index, context);
        break;
      case QuestionType.multipleChoiceWithImages:
        content = _buildMultipleChoiceWithImagesQuestion(q, index, context);
        break;
      case QuestionType.trueFalse:
        content = _buildTrueFalseQuestion(q, index, context);
        break;
      case QuestionType.fillInTheBlank:
        content = _buildFillInTheBlankQuestion(q, index, context);
        break;
      case QuestionType.fillInTheBlankWithImage:
        content = _buildFillInTheBlankWithImageQuestion(q, index, context);
        break;
      case QuestionType.dragAndDrop:
        content = _buildDragAndDropQuestion(q, index, context);
        break;
      case QuestionType.matching:
        content = _buildMatchingQuestion(q, index, context);
        break;
      case QuestionType.audio:
        content = _buildAudioQuestion(q, index, context);
        break;
      default:
        content = Container(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Question type not supported: ${q.type}',
            style: TextStyle(color: Colors.grey[600]),
          ),
        );
        break;
    }

    return content;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[50],
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Quiz Header
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.quiz, size: 48, color: primaryColor),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.questions.length} ${widget.questions.length == 1 ? 'question' : 'questions'}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Lesson Materials Section (NEW)
            if (widget.taskId != null) _buildLessonMaterialsSection(context),

            // Questions Section
            _buildSectionHeader('Questions Preview', Icons.visibility, context),

            if (widget.questions.isEmpty)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.help_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        'No questions available',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...widget.questions.asMap().entries.map((entry) {
                final index = entry.key;
                final q = entry.value;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Question Header
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Question ${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  q.type.displayName,
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Question Text
                        Text(
                          q.questionText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.blueGrey,
                          ),
                        ),

                        // Display question image for ALL question types that have question images
                        if (q.questionImageUrl != null &&
                            q.questionImageUrl!.isNotEmpty)
                          Column(
                            children: [
                              const SizedBox(height: 12),
                              _buildQuestionImage(q.questionImageUrl, context),
                            ],
                          ),

                        const SizedBox(height: 16),

                        // Question Content based on type
                        _buildQuestionContent(q, index, context),
                      ],
                    ),
                  ),
                );
              }).toList(),

            // Bottom spacing
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerWidget({required this.videoUrl});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _videoPlayerController.initialize().timeout(
        const Duration(seconds: 30),
      );

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        placeholder: Container(
          color: Colors.grey[300],
          child: const Center(child: Icon(Icons.videocam, size: 50)),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 50, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load video',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );

      setState(() {
        _isLoading = false;
      });
    } on TimeoutException {
      setState(() {
        _isLoading = false;
        _error = 'Video loading timeout';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty || _chewieController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Failed to load video',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              _error,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
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

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}

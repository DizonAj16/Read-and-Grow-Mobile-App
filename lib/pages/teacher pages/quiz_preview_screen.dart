import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/class_details_page.dart';
import 'package:flutter/material.dart';
import '../../../../models/quiz_questions.dart';

class QuizPreviewScreen extends StatefulWidget {
  final String title;
  final List<QuizQuestion> questions;
  final bool isPreview;
  final Map<String, dynamic>? classDetails;

  // ✅ Added for student context
  final String? studentId;
  final String? assignmentId;

  const QuizPreviewScreen({
    super.key,
    required this.title,
    required this.questions,
    this.isPreview = false,
    this.classDetails,
    this.studentId,       // ✅ newly added
    this.assignmentId,    // ✅ newly added
  });

  @override
  State<QuizPreviewScreen> createState() => _QuizPreviewScreenState();
}

class _QuizPreviewScreenState extends State<QuizPreviewScreen> {
  late ColorScheme _colorScheme;
  
  @override
  void initState() {
    super.initState();
    for (var q in widget.questions) {
      q.userAnswer = q.userAnswer ?? '';
      q.matchingPairs ??= [];
      for (var pair in q.matchingPairs!) {
        pair.userSelected = pair.userSelected ?? '';
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = Theme.of(context).colorScheme;
  }

  Color _getPrimaryColor([double opacity = 1.0]) {
    return _colorScheme.primary.withOpacity(opacity);
  }

  Color _getPrimaryContainerColor([double opacity = 1.0]) {
    return _colorScheme.primaryContainer.withOpacity(opacity);
  }

  Color _getOnPrimaryColor([double opacity = 1.0]) {
    return _colorScheme.onPrimary.withOpacity(opacity);
  }

  Color _getSurfaceVariantColor([double opacity = 1.0]) {
    return _colorScheme.surfaceVariant.withOpacity(opacity);
  }

  Widget _buildImageWidget(String? imageUrl, {double height = 120, BoxFit fit = BoxFit.contain}) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container();
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,
          fit: fit,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[100],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.grey[400], size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load image',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuestionWidget(QuizQuestion q, int questionIndex) {
    final primaryColor = _getPrimaryColor();
    final primaryLight = _getPrimaryColor(0.1);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question image (for fill in the blank with image AND multiple choice with images)
        if ((q.type == QuestionType.fillInTheBlankWithImage || 
             q.type == QuestionType.multipleChoiceWithImages) &&
            q.questionImageUrl != null && q.questionImageUrl!.isNotEmpty)
          Column(
            children: [
              _buildImageWidget(q.questionImageUrl),
              const SizedBox(height: 8),
            ],
          ),
        
        // Question text
        Text(
          q.questionText,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 16),
        
        // Question content based on type
        _buildQuestionContent(q, questionIndex),
      ],
    );
  }

  Widget _buildQuestionContent(QuizQuestion q, int questionIndex) {
    final primaryColor = _getPrimaryColor();
    final primaryLight = _getPrimaryColor(0.1);
    final primaryMedium = _getPrimaryColor(0.3);
    
    // Multiple Choice with Images
    if (q.type == QuestionType.multipleChoiceWithImages && q.options!.isNotEmpty) {
      return Column(
        children: q.options!.asMap().entries.map((entry) {
          final optIndex = entry.key;
          final opt = entry.value;
          final isCorrect = q.correctAnswer == opt;
          final isSelected = q.userAnswer == opt;
          
          // Get option image from the QuizQuestion model
          final String? optionImageUrl = q.getOptionImage(optIndex);
          
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: widget.isPreview && isCorrect
                    ? Colors.green
                    : isSelected
                        ? primaryColor
                        : Colors.grey[300]!,
                width: widget.isPreview && isCorrect ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Option image (if exists)
                if (optionImageUrl != null && optionImageUrl.isNotEmpty)
                  _buildImageWidget(optionImageUrl, height: 100),
                
                ListTile(
                  title: Text(
                    opt.isNotEmpty ? opt : 'Image Option ${optIndex + 1}',
                    style: TextStyle(
                      color: widget.isPreview && isCorrect ? Colors.green : null,
                      fontWeight: widget.isPreview && isCorrect
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  leading: widget.isPreview
                      ? Container(
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
                        )
                      : Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? primaryColor : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? Container(
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primaryColor,
                                  ),
                                )
                              : null,
                        ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    // Regular Multiple Choice
    if (q.type == QuestionType.multipleChoice && q.options!.isNotEmpty) {
      return Column(
        children: q.options!.asMap().entries.map((entry) {
          final optIndex = entry.key;
          final opt = entry.value;
          final isCorrect = q.correctAnswer == opt;
          final isSelected = q.userAnswer == opt;
          
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: widget.isPreview && isCorrect
                    ? Colors.green
                    : isSelected
                        ? primaryColor
                        : Colors.grey[300]!,
                width: widget.isPreview && isCorrect ? 2 : 1,
              ),
            ),
            child: ListTile(
              title: Text(
                opt,
                style: TextStyle(
                  color: widget.isPreview && isCorrect ? Colors.green : null,
                  fontWeight: widget.isPreview && isCorrect
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              leading: widget.isPreview
                  ? Container(
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
                    )
                  : Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? primaryColor : Colors.grey,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primaryColor,
                              ),
                            )
                          : null,
                    ),
            ),
          );
        }).toList(),
      );
    }

    // True/False
    if (q.type == QuestionType.trueFalse) {
      final trueFalseOptions = q.options != null && q.options!.isNotEmpty 
          ? q.options! 
          : ['True', 'False'];
      
      return Column(
        children: trueFalseOptions.asMap().entries.map((entry) {
          final optIndex = entry.key;
          final opt = entry.value;
          final isCorrect = q.correctAnswer?.toLowerCase() == opt.toLowerCase();
          final isSelected = q.userAnswer == opt;
          
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: widget.isPreview && isCorrect
                    ? Colors.green
                    : isSelected
                        ? primaryColor
                        : Colors.grey[300]!,
                width: widget.isPreview && isCorrect ? 2 : 1,
              ),
            ),
            child: ListTile(
              title: Text(
                opt,
                style: TextStyle(
                  color: widget.isPreview && isCorrect ? Colors.green : null,
                  fontWeight: widget.isPreview && isCorrect
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              leading: widget.isPreview
                  ? Container(
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
                    )
                  : Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? primaryColor : Colors.grey,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primaryColor,
                              ),
                            )
                          : null,
                    ),
            ),
          );
        }).toList(),
      );
    }

    // Fill in the Blank with Image
    if (q.type == QuestionType.fillInTheBlankWithImage) {
      return widget.isPreview
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The question image is already displayed above in _buildQuestionWidget
                
                Container(
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
                      Text(
                        q.correctAnswer ?? "",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The question image is already displayed above in _buildQuestionWidget
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primaryMedium),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Answer:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Type your answer here...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onChanged: (val) => q.userAnswer = val,
                      ),
                    ],
                  ),
                ),
              ],
            );
    }

    // Regular Fill in the Blank
    if (q.type == QuestionType.fillInTheBlank) {
      return widget.isPreview
          ? Container(
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
                  Text(
                    q.correctAnswer ?? "",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Answer:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Type your answer here...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (val) => q.userAnswer = val,
                  ),
                ],
              ),
            );
    }

    // Drag and Drop
    if (q.type == QuestionType.dragAndDrop && q.options!.isNotEmpty) {
      return widget.isPreview
          ? Column(
              children: q.options!
                  .map((opt) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(Icons.drag_handle, color: Colors.grey),
                          title: Text(opt),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${q.options!.indexOf(opt) + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            )
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Drag to reorder items:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = q.options!.removeAt(oldIndex);
                        q.options!.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (int i = 0; i < q.options!.length; i++)
                        Card(
                          key: ValueKey('${q.options![i]}-$i'),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(Icons.drag_handle, color: Colors.grey),
                            title: Text(q.options![i]),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
    }

    // Matching
    if (q.type == QuestionType.matching && q.matchingPairs!.isNotEmpty) {
      return widget.isPreview
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Matching Pairs:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
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
                                  color: primaryLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  pair.leftItem,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.swap_horiz, color: primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: primaryMedium),
                                ),
                                child: (pair.rightItemUrl != null &&
                                        pair.rightItemUrl!.isNotEmpty)
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          pair.rightItemUrl!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.error, color: Colors.red),
                                                  Text('Failed to load', style: TextStyle(fontSize: 12)),
                                                ],
                                              ),
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
            )
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Drag the text to match the images:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: q.matchingPairs!.map((pair) {
                      return Draggable<String>(
                        data: pair.leftItem,
                        feedback: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pair.leftItem,
                              style: TextStyle(
                                color: _getOnPrimaryColor(),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(pair.leftItem),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            pair.leftItem,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: q.matchingPairs!.map((pair) {
                      return DragTarget<String>(
                        onAccept: (received) {
                          setState(() {
                            pair.userSelected = received;
                          });
                        },
                        builder: (context, candidateData, rejectedData) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: primaryMedium),
                                    ),
                                    child: (pair.rightItemUrl != null &&
                                            pair.rightItemUrl!.isNotEmpty)
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              pair.rightItemUrl!,
                                              fit: BoxFit.contain,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Center(
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.error, color: Colors.red),
                                                      Text('Error', style: TextStyle(fontSize: 12)),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                        : Center(
                                            child: Text(
                                              'Drop here',
                                              style: TextStyle(color: Colors.grey[600]),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: pair.userSelected!.isEmpty
                                            ? _getSurfaceVariantColor()
                                            : Colors.green[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: pair.userSelected!.isEmpty
                                              ? Colors.grey[300]!
                                              : Colors.green!,
                                        ),
                                      ),
                                      child: Text(
                                        pair.userSelected!.isEmpty
                                            ? 'Drop text here'
                                            : pair.userSelected!,
                                        style: TextStyle(
                                          color: pair.userSelected!.isEmpty
                                              ? Colors.grey
                                              : Colors.black,
                                          fontWeight: pair.userSelected!.isEmpty
                                              ? FontWeight.normal
                                              : FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getSurfaceVariantColor(),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          'Question type not supported',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final primaryColor = _getPrimaryColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.1),
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

  Future<Map<String, dynamic>> _fetchUpdatedClassDetails() async {
    if (widget.classDetails == null) return {};
    final classId = widget.classDetails!['id'];
    final updatedData = await ClassroomService.getClassDetails(classId);
    return updatedData;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor();
    final primaryLight = _getPrimaryColor(0.1);
    
    return WillPopScope(
      onWillPop: () async {
        if (widget.isPreview && widget.classDetails != null) {
          final updatedData = await _fetchUpdatedClassDetails();
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ClassDetailsPage(classDetails: updatedData),
              ),
            );
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isPreview
                ? 'Quiz Preview: ${widget.title}'
                : widget.title,
            style: TextStyle(color: _getOnPrimaryColor()),
          ),
          backgroundColor: primaryColor,
          foregroundColor: _getOnPrimaryColor(),
          elevation: 0,
          leading: widget.isPreview 
              ? IconButton(
                  icon: Icon(Icons.arrow_back, color: _getOnPrimaryColor()),
                  onPressed: () async {
                    if (widget.classDetails != null) {
                      final updatedData = await _fetchUpdatedClassDetails();
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClassDetailsPage(classDetails: updatedData),
                          ),
                        );
                      }
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                )
              : BackButton(color: _getOnPrimaryColor()),
        ),
        body: Container(
          color: Colors.grey[50],
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Quiz Header
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.quiz,
                        size: 48,
                        color: primaryColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.questions.length} ${widget.questions.length == 1 ? 'question' : 'questions'}',
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Questions Section
              _buildSectionHeader('Questions', Icons.question_answer),

              if (widget.questions.isEmpty)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.help_outline, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'No questions available',
                          style: TextStyle(color: Colors.grey),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: primaryLight,
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
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    q.type.name.toUpperCase().replaceAll('_', ' '),
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
                          _buildQuestionWidget(q, index),
                        ],
                      ),
                    ),
                  );
                }).toList(),

              // Finish Button for Preview Mode
              if (widget.isPreview && widget.classDetails != null)
                Container(
                  margin: const EdgeInsets.only(top: 24, bottom: 20),
                  child: ElevatedButton(
                    onPressed: () async {
                      final updatedData = await _fetchUpdatedClassDetails();
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClassDetailsPage(classDetails: updatedData),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: _getOnPrimaryColor(),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: _getOnPrimaryColor()),
                        const SizedBox(width: 8),
                        Text(
                          'Finish Preview',
                          style: TextStyle(
                            fontSize: 16,
                            color: _getOnPrimaryColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
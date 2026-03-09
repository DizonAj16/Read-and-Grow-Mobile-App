import 'package:deped_reading_app_laravel/models/quiz_questions.dart';
import 'package:flutter/material.dart';

class QuizPreviewScreen extends StatelessWidget {
  final String title;
  final List<QuizQuestion> questions;

  const QuizPreviewScreen({
    super.key,
    required this.title,
    required this.questions,
  });

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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.grey, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
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

    debugPrint("Building Multiple Choice Question: ${q.questionText}");
    debugPrint("Options: ${q.options}");
    debugPrint("Option Images: ${q.optionImages}");

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

    debugPrint(
      "Building Multiple Choice with Images Question: ${q.questionText}",
    );
    debugPrint("Options: ${q.options}");
    debugPrint("Option Images: ${q.optionImages}");

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

          // Get the image URL for this option
          final optionImage = q.getOptionImage(optIndex);
          final hasOptionImage = optionImage != null && optionImage.isNotEmpty;

          debugPrint("Option $optIndex - Image URL: $optionImage");

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
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    debugPrint("Building True/False Question: ${q.questionText}");
    // Ensure we have True/False options
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
    debugPrint("Building Fill in Blank Question: ${q.questionText}");
    debugPrint("Correct Answer: ${q.correctAnswer}");

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
    final primaryColor = Theme.of(context).colorScheme.primary;

    debugPrint("Building Fill in Blank with Image Question: ${q.questionText}");
    debugPrint("Question Image URL: ${q.questionImageUrl}");
    debugPrint("Correct Answer: ${q.correctAnswer}");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Display the answer
        Container(
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDragAndDropQuestion(
    QuizQuestion q,
    int index,
    BuildContext context,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    debugPrint("Building Drag & Drop Question: ${q.questionText}");
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    debugPrint("Building Matching Question: ${q.questionText}");
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
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.error,
                                              color: Colors.red,
                                            ),
                                            Text(
                                              'Failed to load',
                                              style: TextStyle(fontSize: 12),
                                            ),
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
    );
  }

  Widget _buildAudioQuestion(QuizQuestion q, int index, BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    debugPrint("Building Audio Question: ${q.questionText}");
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
    debugPrint("\n=== START PROCESSING QUESTION ${index + 1} ===");
    debugPrint("Question Type: ${q.type.name}");
    debugPrint("Question Text: ${q.questionText}");
    debugPrint("Question Image URL: ${q.questionImageUrl}");
    debugPrint("Option Images: ${q.optionImages}");
    debugPrint("Options: ${q.options}");
    debugPrint("Correct Answer: ${q.correctAnswer}");

    // Call debug method to see all question data
    q.debugQuestionData();

    Widget content;

    switch (q.type) {
      case QuestionType.multipleChoice:
        debugPrint("Processing as Multiple Choice...");
        content = _buildMultipleChoiceQuestion(q, index, context);
        break;
      case QuestionType.multipleChoiceWithImages:
        debugPrint("Processing as Multiple Choice with Images...");
        content = _buildMultipleChoiceWithImagesQuestion(q, index, context);
        break;
      case QuestionType.trueFalse:
        debugPrint("Processing as True/False...");
        content = _buildTrueFalseQuestion(q, index, context);
        break;
      case QuestionType.fillInTheBlank:
        debugPrint("Processing as Fill in the Blank...");
        content = _buildFillInTheBlankQuestion(q, index, context);
        break;
      case QuestionType.fillInTheBlankWithImage:
        debugPrint("Processing as Fill in the Blank with Image...");
        content = _buildFillInTheBlankWithImageQuestion(q, index, context);
        break;
      case QuestionType.dragAndDrop:
        debugPrint("Processing as Drag & Drop...");
        content = _buildDragAndDropQuestion(q, index, context);
        break;
      case QuestionType.matching:
        debugPrint("Processing as Matching...");
        content = _buildMatchingQuestion(q, index, context);
        break;
      case QuestionType.audio:
        debugPrint("Processing as Audio...");
        content = _buildAudioQuestion(q, index, context);
        break;
      default:
        debugPrint("Unknown question type!");
        content = Container(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Question type not supported: ${q.type}',
            style: TextStyle(color: Colors.grey[600]),
          ),
        );
        break;
    }

    debugPrint("=== END PROCESSING QUESTION ${index + 1} ===\n");
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    debugPrint("\n\n=== BUILDING QUIZ PREVIEW SCREEN ===");
    debugPrint("Quiz Title: $title");
    debugPrint("Total questions: ${questions.length}");

    // Detailed debug for each question
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      debugPrint("\n🔍 QUESTION ${i + 1} ANALYSIS:");
      debugPrint("  - ID: ${q.id}");
      debugPrint("  - Text: ${q.questionText}");
      debugPrint("  - Type: ${q.type.name}");
      debugPrint("  - Type enum: ${q.type}");
      debugPrint("  - Question Image URL: ${q.questionImageUrl}");
      debugPrint(
        "  - Has Question Image: ${q.questionImageUrl != null && q.questionImageUrl!.isNotEmpty}",
      );
      debugPrint("  - Option Images: ${q.optionImages}");
      debugPrint("  - Options: ${q.options}");
      debugPrint("  - Correct Answer: ${q.correctAnswer}");
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
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
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${questions.length} ${questions.length == 1 ? 'question' : 'questions'}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Questions Section
            _buildSectionHeader('Questions Preview', Icons.visibility, context),

            if (questions.isEmpty)
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
              ...questions.asMap().entries.map((entry) {
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
                        // This includes multipleChoiceWithImages and fillInTheBlankWithImage
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

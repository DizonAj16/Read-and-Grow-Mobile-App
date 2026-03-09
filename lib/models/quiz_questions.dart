import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

enum QuestionType {
  multipleChoice,
  fillInTheBlank,
  dragAndDrop,
  matching,
  trueFalse,
  audio,
  multipleChoiceWithImages, // NEW: Multiple choice with pictures
  fillInTheBlankWithImage,  // NEW: Fill in the blank with picture
}

// Convert enum → database string
String questionTypeToDb(QuestionType type) {
  switch (type) {
    case QuestionType.multipleChoice:
      return 'multiple_choice';
    case QuestionType.trueFalse:
      return 'true_false';
    case QuestionType.fillInTheBlank:
      return 'fill_in_the_blank';
    case QuestionType.dragAndDrop:
      return 'drag_and_drop';
    case QuestionType.matching:
      return 'matching';
    case QuestionType.audio:
      return 'audio';
    case QuestionType.multipleChoiceWithImages: // NEW
      return 'multiple_choice_with_images';
    case QuestionType.fillInTheBlankWithImage:  // NEW
      return 'fill_in_the_blank_with_image';
  }
}

QuestionType questionTypeFromDb(String dbType) {
  switch (dbType) {
    case 'multiple_choice':
    case 'multipleChoice':
      return QuestionType.multipleChoice;
    case 'true_false':
    case 'trueOrFalse':
    case 'trueFalse':
      return QuestionType.trueFalse;
    case 'fill_in_the_blank':
    case 'fillInTheBlanks':
      return QuestionType.fillInTheBlank;
    case 'matching':
      return QuestionType.matching;
    case 'drag_and_drop':
    case 'dragAndDrop':
      return QuestionType.dragAndDrop;
    case 'audio':
      return QuestionType.audio;
    case 'multiple_choice_with_images': // NEW
      return QuestionType.multipleChoiceWithImages;
    case 'fill_in_the_blank_with_image': // NEW
      return QuestionType.fillInTheBlankWithImage;
    default:
      debugPrint(
        "⚠️ Unknown question type: $dbType, defaulting to multipleChoice",
      );
      return QuestionType.multipleChoice;
  }
}

class QuizQuestion {
  final String? id;
  String questionText;
  QuestionType type;
  List<String>? options;
  String? correctAnswer;
  List<MatchingPair>? matchingPairs;
  String userAnswer;
  int? timeLimitSeconds;
  Map<String, String>? optionImages; // NEW: For multiple choice with pictures
  String? questionImageUrl; // NEW: For fill-in-the-blank with image

  TextEditingController? textController;
  List<TextEditingController>? optionControllers;

  QuizQuestion({
    this.id,
    required this.questionText,
    required this.type,
    this.options,
    this.correctAnswer,
    this.matchingPairs,
    this.timeLimitSeconds,
    String? userAnswer,
    this.textController,
    this.optionControllers,
    this.optionImages, // NEW
    this.questionImageUrl, // NEW
  }) : userAnswer = userAnswer ?? '' {
    // Always ensure textController is initialized with questionText
    if (textController == null) {
      textController = TextEditingController(text: questionText);
    } else {
      // If controller exists but text doesn't match, update it
      if (textController!.text != questionText) {
        textController!.text = questionText;
      }
    }
    
    // Initialize option controllers if options exist
    if (options != null && options!.isNotEmpty && optionControllers == null) {
      optionControllers = options!
          .map((opt) => TextEditingController(text: opt))
          .toList();
    }
  }

  // Enhanced debug method
  void debugQuestionData() {
    debugPrint("=== QUESTION DEBUG INFO ===", wrapWidth: 1000);
    debugPrint("ID: $id");
    debugPrint("Question Text: $questionText");
    debugPrint("Text Controller Text: ${textController?.text}");
    debugPrint("Type: $type (${type.name})");
    debugPrint("Options: $options");
    debugPrint("Correct Answer: $correctAnswer");
    debugPrint("Number of Matching Pairs: ${matchingPairs?.length ?? 0}");
    debugPrint("Question Image URL: $questionImageUrl");
    debugPrint("Has Question Image: ${questionImageUrl != null && questionImageUrl!.isNotEmpty}");
    
    if (optionImages != null && optionImages!.isNotEmpty) {
      debugPrint("Option Images Map (${optionImages!.length} items):");
      optionImages!.forEach((key, value) {
        debugPrint("  Key '$key' (${key.runtimeType}): '$value'");
      });
      
      // Test getOptionImage for each option
      if (options != null) {
        debugPrint("Testing getOptionImage for each option:");
        for (int i = 0; i < options!.length; i++) {
          final img = getOptionImage(i);
          debugPrint("  Option $i (${options![i]}): $img");
        }
      }
    } else {
      debugPrint("Option Images: null or empty");
    }
    
    if (matchingPairs != null) {
      for (int i = 0; i < matchingPairs!.length; i++) {
        debugPrint("  Pair $i: ${matchingPairs![i].leftItem} -> ${matchingPairs![i].rightItemUrl}");
      }
    }
    debugPrint("============================");
  }

  // NEW: Detailed debug method for image issues
  void debugQuestionDataDetailed() {
    debugPrint("\n" + "="*60);
    debugPrint("QUESTION DETAILED DEBUG INFO");
    debugPrint("="*60);
    debugPrint("ID: $id");
    debugPrint("Question Text: $questionText");
    debugPrint("Type: $type (${type.name})");
    debugPrint("Correct Answer: $correctAnswer");
    debugPrint("Question Image URL: $questionImageUrl");
    debugPrint("Has Question Image: ${questionImageUrl != null && questionImageUrl!.isNotEmpty}");
    debugPrint("Options: ${options?.join(' | ') ?? 'None'}");
    
    if (optionImages != null) {
      debugPrint("\nOPTION IMAGES MAP DETAILS:");
      debugPrint("  Map size: ${optionImages!.length}");
      debugPrint("  Map keys: ${optionImages!.keys.join(', ')}");
      debugPrint("  Map values: ${optionImages!.values.join(', ')}");
      
      // Show each key-value pair with type info
      optionImages!.forEach((key, value) {
        debugPrint("  Key: '$key' (Type: ${key.runtimeType}), Value: '$value' (Length: ${value.length})");
      });
      
      // Test getOptionImage for each index
      debugPrint("\nGET OPTION IMAGE TEST:");
      if (options != null) {
        for (int i = 0; i < options!.length; i++) {
          final img = getOptionImage(i);
          debugPrint("  Index $i: '$img' (exists: ${img != null && img.isNotEmpty})");
        }
      }
    } else {
      debugPrint("\nOPTION IMAGES: null");
    }
    debugPrint("="*60 + "\n");
  }

  // ------------------------------
  // Copy helper
  // ------------------------------
  QuizQuestion copyWith({
    String? id,
    String? questionText,
    QuestionType? type,
    List<String>? options,
    String? correctAnswer,
    List<MatchingPair>? matchingPairs,
    String? userAnswer,
    int? timeLimitSeconds,
    TextEditingController? textController,
    List<TextEditingController>? optionControllers,
    Map<String, String>? optionImages, // NEW
    String? questionImageUrl, // NEW
  }) {
    final newQuestion = QuizQuestion(
      id: id ?? this.id,
      questionText: questionText ?? this.questionText,
      type: type ?? this.type,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      matchingPairs: matchingPairs ?? this.matchingPairs,
      timeLimitSeconds: timeLimitSeconds ?? this.timeLimitSeconds,
      userAnswer: userAnswer ?? this.userAnswer,
      optionImages: optionImages ?? this.optionImages, // NEW
      questionImageUrl: questionImageUrl ?? this.questionImageUrl, // NEW
    );
    
    // Preserve controllers if provided
    if (textController != null) newQuestion.textController = textController;
    if (optionControllers != null) newQuestion.optionControllers = optionControllers;
    
    return newQuestion;
  }

factory QuizQuestion.fromMap(Map<String, dynamic> map) {
  debugPrint("\n" + "="*50);
  debugPrint("PARSING QUESTION FROM MAP");
  debugPrint("="*50);
  debugPrint("Full map keys: ${map.keys.join(', ')}");
  
  final rawType = map['question_type']?.toString() ?? '';
  debugPrint("Raw type from map: '$rawType'");
  
  final mappedType = questionTypeFromDb(rawType);
  debugPrint("Mapped to type: $mappedType (${mappedType.name})");

  // Parse options
  List<String> optionsList = [];
  Map<String, String> parsedOptionImages = {};
  
  // Check if option_images is passed directly (from JSONB column)
  if (map['option_images'] != null) {
    debugPrint("Found option_images in map: ${map['option_images']}");
    debugPrint("option_images type: ${map['option_images'].runtimeType}");
    
    if (map['option_images'] is Map) {
      final optionImagesMap = map['option_images'] as Map;
      optionImagesMap.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          parsedOptionImages[key.toString()] = value.toString();
          debugPrint("  Added option image: key='$key', value='$value'");
        }
      });
    }
    // If it's a string (JSON), it should already be parsed by TaskService
  }

  // Also parse options from question_options
  if (map['question_options'] != null && map['question_options'] is List) {
    debugPrint("Found question_options list with ${(map['question_options'] as List).length} items");
    final options = map['question_options'] as List;
    
    for (int i = 0; i < options.length; i++) {
      final option = options[i];
      debugPrint("\nParsing option $i: $option");
      
      // Extract option text
      final optionText = option['option_text']?.toString() ?? 
                        option['text']?.toString() ?? 
                        option['label']?.toString() ?? '';
      debugPrint("  Option text: '$optionText'");
      optionsList.add(optionText);
      
      // Check if option has its own image (alternative structure)
      final optionImage = option['option_image']?.toString();
      if (optionImage != null && optionImage.isNotEmpty && 
          !parsedOptionImages.containsKey(i.toString())) {
        parsedOptionImages[i.toString()] = optionImage;
        debugPrint("  Found option image in question_options: '$optionImage'");
      }
    }
  } else {
    debugPrint("No question_options found in map");
  }

    // Determine correct answer
    String? correctAns;
    if (optionsList.isNotEmpty) {
      final correctOpt = (map['question_options'] as List?)
          ?.firstWhere((o) => o['is_correct'] == true, orElse: () => null);
      if (correctOpt != null) {
        correctAns = correctOpt['option_text']?.toString() ??
                    correctOpt['text']?.toString() ??
                    correctOpt['label']?.toString();
        debugPrint("Found correct answer in options: '$correctAns'");
      }
    }

    // Fill-in-the-blank fallback - check for direct correct answer field
    if (correctAns == null) {
      if (map['correct_answer'] != null) {
        correctAns = map['correct_answer']?.toString();
        debugPrint("Found correct_answer field: '$correctAns'");
      } else if (map['correctAnswer'] != null) {
        correctAns = map['correctAnswer']?.toString();
        debugPrint("Found correctAnswer field: '$correctAns'");
      }
    }

    // Parse matching pairs
    List<MatchingPair> pairs = [];
    if (map['matching_pairs'] != null && map['matching_pairs'] is List) {
      debugPrint("Found ${(map['matching_pairs'] as List).length} matching pairs");
      pairs = (map['matching_pairs'] as List)
          .map((m) {
            final pair = MatchingPair.fromMap(m);
            pair.leftItemController = TextEditingController(text: pair.leftItem);
            return pair;
          })
          .toList();
    }

    // Check for question image
    final questionImageUrl = map['question_image_url']?.toString() ?? 
                           map['questionImageUrl']?.toString() ??
                           map['image_url']?.toString();
    
    if (questionImageUrl != null && questionImageUrl.isNotEmpty) {
      debugPrint("Found question image URL: '$questionImageUrl'");
    }

    // Debug what we parsed
    debugPrint("\nPARSED DATA SUMMARY:");
    debugPrint("  Options: $optionsList");
    debugPrint("  Option Images: $parsedOptionImages");
    debugPrint("  Correct Answer: $correctAns");
    debugPrint("  Question Image URL: $questionImageUrl");
    debugPrint("="*50 + "\n");

    return QuizQuestion(
      id: map['id']?.toString(),
      questionText: map['question_text']?.toString() ?? '',
      type: mappedType,
      options: optionsList,
      correctAnswer: correctAns,
      matchingPairs: pairs,
      timeLimitSeconds: map['time_limit_seconds'] as int?,
      questionImageUrl: questionImageUrl,
      optionImages: parsedOptionImages.isNotEmpty ? parsedOptionImages : null,
    );
  }

  static QuestionType _inferQuestionType(Map<String, dynamic> map) {
    debugPrint("Inferring question type from map...");
    
    final opts = map['options'] ?? map['question_options'];
    final pairs = map['matching_pairs'] ?? map['pairs'];
    final text = (map['question_text'] ?? '').toString().toLowerCase();
    final hasQuestionImage = map['question_image_url'] != null || 
                           map['questionImageUrl'] != null ||
                           map['image_url'] != null;
    
    // Check for option images
    bool hasOptionImages = false;
    if (map['option_images'] != null && map['option_images'] is Map && (map['option_images'] as Map).isNotEmpty) {
      hasOptionImages = true;
    } else if (opts is List) {
      // Check if any option has an image
      for (final option in opts) {
        if (option is Map) {
          if (option['option_image'] != null || 
              option['image_url'] != null || 
              option['imageUrl'] != null) {
            hasOptionImages = true;
            break;
          }
        }
      }
    }

    debugPrint("  hasQuestionImage: $hasQuestionImage");
    debugPrint("  hasOptionImages: $hasOptionImages");
    debugPrint("  text contains 'blank': ${text.contains('blank')}");
    debugPrint("  has correct_answer: ${map['correct_answer'] != null}");

    // Check for new question types with images FIRST
    if (hasOptionImages && opts is List && opts.isNotEmpty) {
      debugPrint("  → Inferred as: multipleChoiceWithImages");
      return QuestionType.multipleChoiceWithImages;
    }
    
    if (hasQuestionImage && (text.contains('blank') || map['correct_answer'] != null)) {
      debugPrint("  → Inferred as: fillInTheBlankWithImage");
      return QuestionType.fillInTheBlankWithImage;
    }

    // Matching
    if (pairs is List && pairs.isNotEmpty) {
      debugPrint("  → Inferred as: matching");
      return QuestionType.matching;
    }

    // Has options → may be MCQ or TF
    if (opts is List && opts.isNotEmpty) {
      final normalized = opts.map((e) {
        if (e is Map) {
          return (e['option_text'] ?? e['text'] ?? e['label'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
        }
        return e.toString().toLowerCase().trim();
      }).toList();

      // TRUE FALSE DETECTION
      if (normalized.length == 2 &&
          normalized.contains('true') &&
          normalized.contains('false')) {
        debugPrint("  → Inferred as: trueFalse");
        return QuestionType.trueFalse;
      }

      debugPrint("  → Inferred as: multipleChoice");
      return QuestionType.multipleChoice;
    }

    // Fill in the blank detection
    if (text.contains('blank') || map['correct_answer'] != null) {
      debugPrint("  → Inferred as: fillInTheBlank");
      return QuestionType.fillInTheBlank;
    }

    debugPrint("  → Inferred as: multipleChoice (default)");
    return QuestionType.multipleChoice;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question_text': questionText,
      'question_type': questionTypeToDb(type),
      'options': options,
      'correct_answer': correctAnswer,
      'matching_pairs': matchingPairs?.map((p) => p.toMap()).toList(),
      'userAnswer': userAnswer,
      'time_limit_seconds': timeLimitSeconds,
      'question_image_url': questionImageUrl,
      'option_images': optionImages,
    };
  }
  
  // Enhanced helper method to get option image for a specific index
  String? getOptionImage(int index) {
    if (optionImages == null) return null;
    
    // Try multiple key formats
    final img = optionImages![index.toString()] ?? // Try "0", "1", etc.
               optionImages![index] ??            // Try 0, 1, etc. (if key is int)
               optionImages!['$index'];           // Try as string again
    
    if (img != null && img.isNotEmpty) {
      return img;
    }
    
    return null;
  }
  
  // Helper method to set option image for a specific index
  void setOptionImage(int index, String imageUrl) {
    optionImages ??= {};
    optionImages![index.toString()] = imageUrl;
  }
  
  // Helper method to remove option image for a specific index
  void removeOptionImage(int index) {
    optionImages?.remove(index.toString());
    optionImages?.remove(index);
    optionImages?.remove('$index');
  }
  
  // NEW: Check if any option has an image
  bool hasOptionImages() {
    if (optionImages == null || optionImages!.isEmpty) return false;
    
    for (final url in optionImages!.values) {
      if (url != null && url.isNotEmpty) {
        return true;
      }
    }
    
    return false;
  }
  
  // NEW: Get all option images as a list
  List<String?> getOptionImagesList() {
    if (options == null) return [];
    
    final List<String?> images = [];
    for (int i = 0; i < options!.length; i++) {
      images.add(getOptionImage(i));
    }
    
    return images;
  }
}

class MatchingPair {
  String leftItem;
  File? rightItemFile;
  String? rightItemUrl;
  String userSelected;
  String? correctAnswer;

  TextEditingController? leftItemController;

  MatchingPair({
    required this.leftItem,
    this.rightItemFile,
    this.rightItemUrl,
    String? userSelected,
    this.correctAnswer,
    this.leftItemController,
  }) : userSelected = userSelected ?? '' {
    // Initialize leftItemController if not provided
    if (leftItemController == null) {
      leftItemController = TextEditingController(text: leftItem);
    } else {
      // Update controller text if it doesn't match leftItem
      if (leftItemController!.text != leftItem) {
        leftItemController!.text = leftItem;
      }
    }
  }

  factory MatchingPair.fromMap(Map<String, dynamic> map) {
    debugPrint("🟪 Parsing MatchingPair: $map");

    return MatchingPair(
      leftItem: (map['left_item'] ??
              map['leftItem'] ??
              map['left'] ??
              map['text'] ??
              map['label'] ??
              '')
          .toString(),
      rightItemUrl: (map['right_item_url'] ??
              map['rightItemUrl'] ??
              map['right'] ??
              map['imageUrl'] ??
              map['url'])
          ?.toString(),
      userSelected: map['userSelected']?.toString() ??
          map['user_selected']?.toString() ??
          '',
      correctAnswer: map['correct_answer']?.toString() ??
          map['correctAnswer']?.toString() ??
          map['answer']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'leftItem': leftItem,
      'rightItemUrl': rightItemUrl,
      'userSelected': userSelected,
      'correct_answer': correctAnswer,
    };
  }
}
extension QuestionTypeDisplay on QuestionType {
  String get displayName {
    // Convert camelCase → Title Case with spaces
    final String camel = name;
    
    // Insert space before each uppercase letter (except first char)
    final buffer = StringBuffer();
    for (int i = 0; i < camel.length; i++) {
      final char = camel[i];
      if (i > 0 && char.toUpperCase() == char) {
        buffer.write(' ');
      }
      buffer.write(char.toUpperCase());
    }
    
    return buffer.toString();
  }
}
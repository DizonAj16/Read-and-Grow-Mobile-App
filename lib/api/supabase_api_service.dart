import 'dart:convert';
import 'dart:io';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/classroom%20tabs/add_lesson_with_essay_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/quiz_questions.dart';
import '../utils/file_validator.dart';

class ApiService {
  static const String supabaseUrl =
      'https://zrcynmiiduwrtlcyzvzi.supabase.co/rest/v1';
  static const String supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpyY3lubWlpZHV3cnRsY3l6dnppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcyNDExMzIsImV4cCI6MjA3MjgxNzEzMn0.NPDpQKXC5h7qiSTPsIIty8qdNn1DnSHptIkagWlmTHM';

  static final SupabaseClient supabase = SupabaseClient(
    'https://zrcynmiiduwrtlcyzvzi.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpyY3lubWlpZHV3cnRsY3l6dnppIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NzI0MTEzMiwiZXhwIjoyMDcyODE3MTMyfQ.2Bm8PCz6NS4uH4dRRSbcY9Ad7VLmCY7BitWSZjAjaB8',
  );
// REPLACE the entire uploadFile method:
static Future<String?> uploadFile(
  Uint8List fileBytes,
  String fileName,
) async {
  try {
    // Validate size from bytes
    final validation = FileValidator.validateBytes(fileBytes);
    if (!validation.isValid) {
      throw FileSizeLimitException(
        FileValidator.backendLimitMessage(FileValidator.defaultMaxSizeMB),
        actualSizeMB: validation.actualSizeMB,
        limitMB: validation.limitMB,
      );
    }

    final storageFileName =
        'file_${DateTime.now().millisecondsSinceEpoch}_$fileName';

    try {
      final response = await supabase.storage
          .from('materials')
          .uploadBinary(storageFileName, fileBytes);

      if (response.isEmpty) {
        print('❌ Failed to upload file: $storageFileName');
        return null;
      }
    } catch (e) {
      print('❌ Error uploading file: $e');
      return null;
    }

    final fileUrl = supabase.storage
        .from('materials')
        .getPublicUrl(storageFileName);

    print('✅ Uploaded: $fileUrl');
    return fileUrl;
  } catch (e) {
    if (e is FileSizeLimitException) rethrow;
    print('⚠️ Error uploading file: $e');
    return null;
  }
}

  /// Converts Dart enum to snake_case for Supabase enum
  static String questionTypeToSnakeCase(QuestionType type) {
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
      case QuestionType.fillInTheBlankWithImage: // NEW
        return 'fill_in_the_blank_with_image';
    }
  }

  static Future<List<Map<String, dynamic>>> getLessons() async {
    final response = await http.get(
      Uri.parse('$supabaseUrl/tasks?select=id,title'),
      headers: {'apikey': supabaseKey, 'Authorization': 'Bearer $supabaseKey'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      debugPrint('Error fetching lessons: ${response.body}');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>?> getQuizzes() async {
    final response = await http.get(
      Uri.parse('$supabaseUrl/quizzes?select=*'),
      headers: {'apikey': supabaseKey, 'Authorization': 'Bearer $supabaseKey'},
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      debugPrint('Error fetching quizzes: ${response.body}');
      return null;
    }
  }

  static Future<List<QuizQuestion>?> getQuizQuestions(String quizId) async {
    final response = await http.get(
      Uri.parse(
        '$supabaseUrl/quiz_questions?quiz_id=eq.$quizId&select=*,matching_pairs!fk_question(*)',
      ),
      headers: {'apikey': supabaseKey, 'Authorization': 'Bearer $supabaseKey'},
    );

    if (response.statusCode != 200) {
      debugPrint('Error fetching questions: ${response.body}');
      return null;
    }

    final List data = jsonDecode(response.body);

    return data.map((q) {
      QuestionType type;
      switch (q['question_type']) {
        case 'multiple_choice':
          type = QuestionType.multipleChoice;
          break;
        case 'true_false':
          type = QuestionType.trueFalse;
          break;
        case 'fill_in_the_blank':
          type = QuestionType.fillInTheBlank;
          break;
        case 'drag_and_drop':
          type = QuestionType.dragAndDrop;
          break;
        case 'matching':
          type = QuestionType.matching;
          break;
        case 'audio':
          type = QuestionType.audio;
          break;
        case 'multiple_choice_with_images': // NEW
          type = QuestionType.multipleChoiceWithImages;
          break;
        case 'fill_in_the_blank_with_image': // NEW
          type = QuestionType.fillInTheBlankWithImage;
          break;
        default:
          type = QuestionType.multipleChoice;
      }

      List<String>? options;
      if ((type == QuestionType.multipleChoice ||
              type == QuestionType.dragAndDrop ||
              type == QuestionType.multipleChoiceWithImages) && // NEW
          q['options'] != null) {
        options = List<String>.from(q['options']);
      }

      List<MatchingPair>? matchingPairs;
      if (type == QuestionType.matching && q['matching_pairs'] != null) {
        matchingPairs =
            (q['matching_pairs'] as List)
                .map(
                  (pair) => MatchingPair(
                    leftItem: pair['left_item'] ?? '',
                    rightItemUrl: pair['right_item_url'] ?? '',
                  ),
                )
                .toList();
      }

      // Parse option images for multiple choice with images
      Map<String, String> optionImages = {};
      if (type == QuestionType.multipleChoiceWithImages &&
          q['option_images'] != null &&
          q['option_images'] is Map) {
        final imagesMap = q['option_images'] as Map;
        imagesMap.forEach((key, value) {
          if (value is String) {
            optionImages[key.toString()] = value;
          }
        });
      }

      return QuizQuestion(
        questionText: q['question_text'] ?? '',
        type: type,
        options: options,
        matchingPairs: matchingPairs,
        correctAnswer: q['correct_answer'],
        questionImageUrl: q['question_image_url']?.toString(), // NEW
        optionImages: optionImages.isNotEmpty ? optionImages : null, // NEW
      );
    }).toList();
  }

  static Future<Map<String, dynamic>?> addQuiz({
    required String taskId,
    required String title,
    required List<QuizQuestion> questions,
    required String classRoomId,
    Map<int, Map<int, String?>>? optionImages, // NEW: Option images from UI
    Map<int, String?>? questionImages, // NEW: Question images from UI
  }) async {
    try {
      final quizResponse = await http.post(
        Uri.parse('$supabaseUrl/quizzes'),
        headers: {
          'apikey': supabaseKey,
          'Authorization': 'Bearer $supabaseKey',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        body: jsonEncode({
          'task_id': taskId,
          'title': title,
          'class_room_id': classRoomId,
        }),
      );

      if (quizResponse.statusCode != 201) {
        print(
          '❌ Error creating quiz: ${quizResponse.statusCode} ${quizResponse.body}',
        );
        return null;
      }

      final quizData = jsonDecode(quizResponse.body);
      final quizId = quizData[0]['id'];
      print('✅ Quiz created with ID: $quizId');

      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        try {
          // Prepare question data with image fields
          final questionData = {
            'quiz_id': quizId,
            'question_text': q.questionText,
            'question_type': questionTypeToSnakeCase(q.type),
            'sort_order': i,
          };

          // Add question image URL for appropriate question types
          // NEW: Support question images for multiple choice with images
          if (q.type == QuestionType.fillInTheBlankWithImage ||
              q.type == QuestionType.multipleChoiceWithImages) {
            String? imageUrlToSave;

            // Check for uploaded question image
            if (questionImages != null && questionImages.containsKey(i)) {
              imageUrlToSave = questionImages[i];
            }
            // Also check if question already has image URL (from editing)
            else if (q.questionImageUrl != null &&
                q.questionImageUrl!.isNotEmpty) {
              imageUrlToSave = q.questionImageUrl;
            }

            // Only add to questionData if we have a valid URL
            if (imageUrlToSave != null && imageUrlToSave.isNotEmpty) {
              questionData['question_image_url'] = imageUrlToSave;
            }
          }

          final questionResponse = await http.post(
            Uri.parse('$supabaseUrl/quiz_questions'),
            headers: {
              'apikey': supabaseKey,
              'Authorization': 'Bearer $supabaseKey',
              'Content-Type': 'application/json',
              'Prefer': 'return=representation',
            },
            body: jsonEncode(questionData),
          );

          if (questionResponse.statusCode != 201) {
            print('❌ Error adding question ${i + 1}: ${questionResponse.body}');
            continue;
          }

          final questionId = jsonDecode(questionResponse.body)[0]['id'];
          print('✅ Question ${i + 1} added with ID: $questionId');

          // Handle option images for multiple choice with images
          if (q.type == QuestionType.multipleChoiceWithImages &&
              optionImages != null &&
              optionImages.containsKey(i) &&
              q.options != null) {
            // Save option images as JSON in the question record
            final optionImagesForQuestion = <String, String>{};
            final questionOptionImages = optionImages[i]!;

            for (int j = 0; j < q.options!.length; j++) {
              final imageUrl = questionOptionImages[j];
              if (imageUrl != null && imageUrl.isNotEmpty) {
                optionImagesForQuestion[j.toString()] = imageUrl;
              }
            }

            // Update the question with option images
            if (optionImagesForQuestion.isNotEmpty) {
              await http.patch(
                Uri.parse('$supabaseUrl/quiz_questions?id=eq.$questionId'),
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': 'Bearer $supabaseKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'option_images': optionImagesForQuestion}),
              );
            }
          }

          // Handle regular multiple choice, true/false, and multiple choice with images
          if ((q.type == QuestionType.multipleChoice ||
                  q.type == QuestionType.trueFalse ||
                  q.type == QuestionType.multipleChoiceWithImages) &&
              q.options != null) {
            bool hasCorrect = false;
            for (var j = 0; j < q.options!.length; j++) {
              final option = q.options![j];
              final isCorrect = option == q.correctAnswer;
              if (isCorrect) hasCorrect = true;

              await http.post(
                Uri.parse('$supabaseUrl/question_options'),
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': 'Bearer $supabaseKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'question_id': questionId,
                  'option_text': option,
                  'is_correct': isCorrect,
                }),
              );
            }

            if (!hasCorrect) {
              print(
                '⚠️ Warning: Question ${i + 1} has no correct answer selected!',
              );
            }
          }

          if (q.type == QuestionType.dragAndDrop && q.options != null) {
            // For drag and drop, save options in order (correct order is the original order)
            for (int idx = 0; idx < q.options!.length; idx++) {
              await http.post(
                Uri.parse('$supabaseUrl/question_options'),
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': 'Bearer $supabaseKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'question_id': questionId,
                  'option_text': q.options![idx],
                  'is_correct':
                      true, // All options are part of the correct sequence
                  'sort_order': idx, // Store the correct order
                }),
              );
            }
          }

          if ((q.type == QuestionType.dragAndDrop ||
                  q.type == QuestionType.matching) &&
              q.matchingPairs != null) {
            for (var pair in q.matchingPairs!) {
              await http.post(
                Uri.parse('$supabaseUrl/matching_pairs'),
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': 'Bearer $supabaseKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'question_id': questionId,
                  'left_item': pair.leftItem,
                  'right_item_url': pair.rightItemUrl,
                }),
              );
            }
          }

          if ((q.type == QuestionType.fillInTheBlank ||
                  q.type == QuestionType.fillInTheBlankWithImage) &&
              q.correctAnswer != null) {
            // Save fill-in-the-blank answer to question_options for consistency
            await http.post(
              Uri.parse('$supabaseUrl/question_options'),
              headers: {
                'apikey': supabaseKey,
                'Authorization': 'Bearer $supabaseKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'question_id': questionId,
                'option_text': q.correctAnswer!.trim(),
                'is_correct': true,
              }),
            );
            // Also save to fill_in_the_blank_answers table for backward compatibility
            await http.post(
              Uri.parse('$supabaseUrl/fill_in_the_blank_answers'),
              headers: {
                'apikey': supabaseKey,
                'Authorization': 'Bearer $supabaseKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'question_id': questionId,
                'correct_answer': q.correctAnswer!.trim(),
              }),
            );
          }
        } catch (e) {
          print('⚠️ Failed to add question ${i + 1}: $e');
        }
      }

      return {'quiz_id': quizId};
    } catch (e) {
      print('❌ Failed to create quiz: $e');
      return null;
    }
  }

  /// Update an existing quiz
  static Future<bool> updateQuiz({
    required String quizId,
    required String title,
    required List<QuizQuestion> questions,
    Map<int, Map<int, String?>>? optionImages, // NEW: Option images from UI
    Map<int, String?>? questionImages, // NEW: Question images from UI
  }) async {
    try {
      // Update quiz title
      final quizResponse = await http.patch(
        Uri.parse('$supabaseUrl/quizzes?id=eq.$quizId'),
        headers: {
          'apikey': supabaseKey,
          'Authorization': 'Bearer $supabaseKey',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        body: jsonEncode({'title': title}),
      );

      if (quizResponse.statusCode != 200 && quizResponse.statusCode != 204) {
        print(
          '❌ Error updating quiz: ${quizResponse.statusCode} ${quizResponse.body}',
        );
        return false;
      }

      // Delete existing questions and their related data
      final existingQuestions = await supabase
          .from('quiz_questions')
          .select('id')
          .eq('quiz_id', quizId);

      for (var q in existingQuestions) {
        final questionId = q['id'].toString();
        // Delete question options
        await supabase
            .from('question_options')
            .delete()
            .eq('question_id', questionId);
        // Delete matching pairs
        await supabase
            .from('matching_pairs')
            .delete()
            .eq('question_id', questionId);
        // Delete question
        await supabase.from('quiz_questions').delete().eq('id', questionId);
      }

      // Add new questions (enhanced logic to support new question types)
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        try {
          // Prepare question data with image fields
          final questionData = {
            'quiz_id': quizId,
            'question_text': q.questionText,
            'question_type': questionTypeToSnakeCase(q.type),
            'sort_order': i,
          };

          // Add question image URL for appropriate question types
          // NEW: Support question images for multiple choice with images
          // Add question image URL for appropriate question types
          // NEW: Support question images for multiple choice with images
          if (q.type == QuestionType.fillInTheBlankWithImage ||
              q.type == QuestionType.multipleChoiceWithImages) {
            String? imageUrlToSave;

            // Check for uploaded question image
            if (questionImages != null && questionImages.containsKey(i)) {
              imageUrlToSave = questionImages[i];
            }
            // Also check if question already has image URL (from editing)
            else if (q.questionImageUrl != null &&
                q.questionImageUrl!.isNotEmpty) {
              imageUrlToSave = q.questionImageUrl;
            }

            // Only add to questionData if we have a valid URL
            if (imageUrlToSave != null && imageUrlToSave.isNotEmpty) {
              questionData['question_image_url'] = imageUrlToSave;
            }

            final questionResponse = await http.post(
              Uri.parse('$supabaseUrl/quiz_questions'),
              headers: {
                'apikey': supabaseKey,
                'Authorization': 'Bearer $supabaseKey',
                'Content-Type': 'application/json',
                'Prefer': 'return=representation',
              },
              body: jsonEncode(questionData),
            );

            if (questionResponse.statusCode != 201) {
              print(
                '❌ Error adding question ${i + 1}: ${questionResponse.body}',
              );
              continue;
            }

            final questionId = jsonDecode(questionResponse.body)[0]['id'];
            print('✅ Question ${i + 1} added with ID: $questionId');

            // Handle option images for multiple choice with images
            if (q.type == QuestionType.multipleChoiceWithImages &&
                optionImages != null &&
                optionImages.containsKey(i) &&
                q.options != null) {
              // Save option images as JSON in the question record
              final optionImagesForQuestion = <String, String>{};
              final questionOptionImages = optionImages[i]!;

              for (int j = 0; j < q.options!.length; j++) {
                final imageUrl = questionOptionImages[j];
                if (imageUrl != null && imageUrl.isNotEmpty) {
                  optionImagesForQuestion[j.toString()] = imageUrl;
                }
              }

              // Update the question with option images
              if (optionImagesForQuestion.isNotEmpty) {
                await http.patch(
                  Uri.parse('$supabaseUrl/quiz_questions?id=eq.$questionId'),
                  headers: {
                    'apikey': supabaseKey,
                    'Authorization': 'Bearer $supabaseKey',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({'option_images': optionImagesForQuestion}),
                );
              }
            }

            if ((q.type == QuestionType.multipleChoice ||
                    q.type == QuestionType.trueFalse ||
                    q.type == QuestionType.multipleChoiceWithImages) &&
                q.options != null) {
              bool hasCorrect = false;
              for (var option in q.options!) {
                final isCorrect = option == q.correctAnswer;
                if (isCorrect) hasCorrect = true;

                await http.post(
                  Uri.parse('$supabaseUrl/question_options'),
                  headers: {
                    'apikey': supabaseKey,
                    'Authorization': 'Bearer $supabaseKey',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'question_id': questionId,
                    'option_text': option,
                    'is_correct': isCorrect,
                  }),
                );
              }

              if (!hasCorrect) {
                print(
                  '⚠️ Warning: Question ${i + 1} has no correct answer selected!',
                );
              }
            }

            if (q.type == QuestionType.dragAndDrop && q.options != null) {
              for (int idx = 0; idx < q.options!.length; idx++) {
                await http.post(
                  Uri.parse('$supabaseUrl/question_options'),
                  headers: {
                    'apikey': supabaseKey,
                    'Authorization': 'Bearer $supabaseKey',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'question_id': questionId,
                    'option_text': q.options![idx],
                    'sort_order': idx,
                    'is_correct': false,
                  }),
                );
              }
            }

            if (q.type == QuestionType.fillInTheBlank &&
                q.correctAnswer != null) {
              await http.post(
                Uri.parse('$supabaseUrl/question_options'),
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': 'Bearer $supabaseKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'question_id': questionId,
                  'option_text': q.correctAnswer!.trim(),
                  'is_correct': true,
                }),
              );
            }

            if (q.type == QuestionType.matching && q.matchingPairs != null) {
              for (var pair in q.matchingPairs!) {
                await http.post(
                  Uri.parse('$supabaseUrl/matching_pairs'),
                  headers: {
                    'apikey': supabaseKey,
                    'Authorization': 'Bearer $supabaseKey',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'question_id': questionId,
                    'left_item': pair.leftItem,
                    'right_item_url': pair.rightItemUrl,
                  }),
                );
              }
            }

            if (q.type == QuestionType.trueFalse && q.correctAnswer != null) {
              await http.post(
                Uri.parse('$supabaseUrl/question_options'),
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': 'Bearer $supabaseKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'question_id': questionId,
                  'correct_answer': q.correctAnswer!.trim(),
                }),
              );
            }
          }
        } catch (e) {
          print('⚠️ Failed to add question ${i + 1}: $e');
        }
      }

      return true;
    } catch (e) {
      print('❌ Failed to update quiz: $e');
      return false;
    }
  }

  /// Delete a quiz and all its related data
  /// This includes:
  /// - Quiz questions and their options/matching pairs
  /// - Assignments that reference this quiz
  /// - Student submissions for those assignments
  /// - Student recordings related to quiz questions
  /// - The quiz itself
  ///
  /// Returns true if deletion was successful, false otherwise
  static Future<bool> deleteQuiz(String quizId) async {
    // Validate quiz ID
    if (quizId.isEmpty || quizId.trim().isEmpty) {
      debugPrint('❌ [DELETE_QUIZ] Invalid quiz ID provided');
      return false;
    }

    try {
      debugPrint('🗑️ [DELETE_QUIZ] Starting deletion of quiz: $quizId');

      // 1. Verify quiz exists before attempting deletion
      final quizExists =
          await supabase
              .from('quizzes')
              .select('id, title')
              .eq('id', quizId)
              .maybeSingle();

      if (quizExists == null) {
        debugPrint('❌ [DELETE_QUIZ] Quiz not found: $quizId');
        return false;
      }

      final quizTitle = quizExists['title']?.toString() ?? 'Unknown Quiz';
      debugPrint('✅ [DELETE_QUIZ] Quiz found: $quizTitle');

      // 2. Get all assignments that reference this quiz
      List<Map<String, dynamic>> assignments = [];
      try {
        assignments = List<Map<String, dynamic>>.from(
          await supabase.from('assignments').select('id').eq('quiz_id', quizId),
        );
        debugPrint(
          '📋 [DELETE_QUIZ] Found ${assignments.length} assignments referencing this quiz',
        );
      } catch (e) {
        debugPrint('⚠️ [DELETE_QUIZ] Error fetching assignments: $e');
        // Continue with deletion even if we can't fetch assignments
      }

      // 3. Delete student submissions for those assignments
      int totalSubmissionsDeleted = 0;
      for (var assignment in assignments) {
        final assignmentId = assignment['id']?.toString();
        if (assignmentId != null && assignmentId.isNotEmpty) {
          try {
            // Delete student submissions
            await supabase
                .from('student_submissions')
                .delete()
                .eq('assignment_id', assignmentId);

            debugPrint(
              '✅ [DELETE_QUIZ] Deleted student submissions for assignment $assignmentId',
            );
            totalSubmissionsDeleted++;
          } catch (e) {
            debugPrint(
              '⚠️ [DELETE_QUIZ] Error deleting submissions for assignment $assignmentId: $e',
            );
            // Continue with deletion even if submissions deletion fails
          }
        }
      }

      if (totalSubmissionsDeleted > 0) {
        debugPrint(
          '📊 [DELETE_QUIZ] Processed $totalSubmissionsDeleted assignments with submissions',
        );
      }

      // 4. Delete assignments that reference this quiz
      if (assignments.isNotEmpty) {
        try {
          final deleteResult =
              await supabase
                  .from('assignments')
                  .delete()
                  .eq('quiz_id', quizId)
                  .select();

          final deletedCount = (deleteResult as List).length;
          debugPrint('✅ [DELETE_QUIZ] Deleted $deletedCount assignments');
        } catch (e) {
          debugPrint('⚠️ [DELETE_QUIZ] Error deleting assignments: $e');
          // This is important but not critical - continue with question deletion
        }
      }

      // 5. Get all questions for this quiz
      List<Map<String, dynamic>> questions = [];
      try {
        questions = List<Map<String, dynamic>>.from(
          await supabase
              .from('quiz_questions')
              .select('id')
              .eq('quiz_id', quizId),
        );
        debugPrint(
          '❓ [DELETE_QUIZ] Found ${questions.length} questions to delete',
        );
      } catch (e) {
        debugPrint('⚠️ [DELETE_QUIZ] Error fetching questions: $e');
        // Continue - we'll try to delete quiz anyway
      }

      // 6. Collect question IDs and delete related data for each question
      final questionIds = <String>[];
      int optionsDeleted = 0;
      int pairsDeleted = 0;

      for (var question in questions) {
        final questionId = question['id']?.toString();
        if (questionId != null && questionId.isNotEmpty) {
          questionIds.add(questionId);

          try {
            // Delete question options
            await supabase
                .from('question_options')
                .delete()
                .eq('question_id', questionId);
            optionsDeleted++;

            // Delete matching pairs
            await supabase
                .from('matching_pairs')
                .delete()
                .eq('question_id', questionId);
            pairsDeleted++;

            debugPrint(
              '✅ [DELETE_QUIZ] Deleted options and pairs for question $questionId',
            );
          } catch (e) {
            debugPrint(
              '⚠️ [DELETE_QUIZ] Error deleting question data for $questionId: $e',
            );
            // Continue with deletion even if question data deletion fails
          }
        }
      }

      debugPrint(
        '📊 [DELETE_QUIZ] Deleted $optionsDeleted question options and $pairsDeleted matching pairs',
      );

      // 7. Delete student recordings related to quiz questions (before deleting questions)
      // This must happen before deleting questions to avoid foreign key constraint issues
      if (questionIds.isNotEmpty) {
        try {
          int recordingsDeleted = 0;
          for (var questionId in questionIds) {
            try {
              await supabase
                  .from('student_recordings')
                  .delete()
                  .eq('quiz_question_id', questionId);
              recordingsDeleted++;
            } catch (e) {
              debugPrint(
                '⚠️ [DELETE_QUIZ] Error deleting recordings for question $questionId: $e',
              );
              // Continue with other questions
            }
          }
          if (recordingsDeleted > 0) {
            debugPrint(
              '✅ [DELETE_QUIZ] Cleaned up $recordingsDeleted student recordings',
            );
          }
        } catch (e) {
          debugPrint('⚠️ [DELETE_QUIZ] Error deleting student recordings: $e');
          // Continue with deletion even if recordings deletion fails
        }
      }

      // 8. Delete all questions (CRITICAL STEP - must succeed)
      if (questions.isNotEmpty) {
        try {
          final deleteResult =
              await supabase
                  .from('quiz_questions')
                  .delete()
                  .eq('quiz_id', quizId)
                  .select();

          final deletedCount = (deleteResult as List).length;
          debugPrint('✅ [DELETE_QUIZ] Deleted $deletedCount questions');
        } catch (e) {
          debugPrint('❌ [DELETE_QUIZ] Error deleting questions: $e');
          return false; // Critical failure
        }
      }

      // 9. Delete the quiz itself (CRITICAL - must succeed)
      try {
        final deleteResult =
            await supabase.from('quizzes').delete().eq('id', quizId).select();

        // Verify deletion was successful
        final deletedList = deleteResult as List;
        if (deletedList.isEmpty) {
          debugPrint('⚠️ [DELETE_QUIZ] Quiz deletion returned no rows');
          // Verify quiz is actually deleted
          final verifyDeleted =
              await supabase
                  .from('quizzes')
                  .select('id')
                  .eq('id', quizId)
                  .maybeSingle();

          if (verifyDeleted != null) {
            debugPrint(
              '❌ [DELETE_QUIZ] Quiz still exists after deletion attempt',
            );
            return false;
          }
        }

        debugPrint('✅ [DELETE_QUIZ] Quiz "$quizTitle" deleted successfully');
        debugPrint(
          '📊 [DELETE_QUIZ] Deletion completed: ${assignments.length} assignments, ${questions.length} questions',
        );
        return true;
      } catch (e) {
        debugPrint('❌ [DELETE_QUIZ] Error deleting quiz: $e');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [DELETE_QUIZ] Failed to delete quiz: $e');
      debugPrint('❌ [DELETE_QUIZ] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Fetch quiz data for editing
  static Future<Map<String, dynamic>?> fetchQuizForEdit(String quizId) async {
    try {
      final quiz =
          await supabase
              .from('quizzes')
              .select('id, title, task_id')
              .eq('id', quizId)
              .maybeSingle();

      if (quiz == null) return null;

      final questions = await supabase
          .from('quiz_questions')
          .select('''
            id,
            question_text,
            question_type,
            sort_order,
            question_image_url,
            option_images,
            question_options(*),
            matching_pairs(*)
          ''')
          .eq('quiz_id', quizId)
          .order('sort_order', ascending: true);

      // Debug print to see what we're getting
      for (var q in questions) {
        debugPrint('Question type from DB: ${q['question_type']}');
        debugPrint('Question image URL: ${q['question_image_url']}');
        debugPrint('Option images: ${q['option_images']}');
      }

      return {'quiz': quiz, 'questions': questions};
    } catch (e) {
      debugPrint('❌ Failed to fetch quiz: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> addLesson({
    String? readingLevelId,
    required String classRoomId,
    required String title,
    String? description,
    int? timeLimitMinutes,
    bool unlocksNextLevel = false,
  }) async {
    final body = {
      if (readingLevelId != null) 'reading_level_id': readingLevelId,
      'class_room_id': classRoomId,
      'title': title,
      'description': description,
      'time_limit_minutes': timeLimitMinutes,
      'unlocks_next_level': unlocksNextLevel,
    };

    final response = await http.post(
      Uri.parse('$supabaseUrl/tasks'),
      headers: {
        'apikey': supabaseKey,
        'Authorization': 'Bearer $supabaseKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body)[0];
    } else {
      debugPrint('Error adding lesson: ${response.body}');
      return null;
    }
  }

  // Add to ApiService class
  static Future<Map<String, dynamic>?> addEssayAssignment({
    required String taskId,
    required String title,
    required List<EssayQuestion> questions,
    required String classRoomId,
    required String assignmentId,
  }) async {
    try {
      // Use Supabase client instead of HTTP
      final essayResponse =
          await supabase
              .from('essay_assignments')
              .insert({
                'assignment_id': assignmentId,
                'task_id': taskId,
                'title': title,
                'class_room_id': classRoomId,
              })
              .select()
              .single();

      final essayId = essayResponse['id'].toString();
      print('✅ Essay assignment created with ID: $essayId');

      // Add essay questions
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        try {
          final questionData = {
            'essay_assignment_id': essayId,
            'question_text': q.questionText,
            'sort_order': i,
            'word_limit': q.wordLimit,
          };

          if (q.questionImageUrl != null && q.questionImageUrl!.isNotEmpty) {
            questionData['question_image_url'] = q.questionImageUrl;
          }

          await supabase.from('essay_questions').insert(questionData);

          print('✅ Essay question ${i + 1} added');
        } catch (e) {
          print('⚠️ Failed to add essay question ${i + 1}: $e');
        }
      }

      return {'essay_id': essayId};
    } catch (e) {
      print('❌ Failed to create essay assignment: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> getEssaySubmissions({
    required String classRoomId,
    required String assignmentId,
  }) async {
    try {
      // Simpler query without joins
      final response = await supabase
          .from('student_essay_responses')
          .select('*')
          .eq('assignment_id', assignmentId)
          .order('submitted_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching essay submissions: $e');
      return null;
    }
  }

  // Method to grade an essay
  static Future<bool> gradeEssay({
    required String submissionId,
    required double score,
    required String feedback,
  }) async {
    try {
      await supabase
          .from('student_essay_responses')
          .update({
            'teacher_score': score,
            'teacher_feedback': feedback,
            'is_graded': true,
            'graded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', submissionId);

      return true;
    } catch (e) {
      print('❌ Error grading essay: $e');
      return false;
    }
  }
}

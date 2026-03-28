import 'dart:convert';

import 'package:deped_reading_app_laravel/models/quiz_questions.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TaskService {
  /// Fetch all quizzes for a given class
/// Fetch all quizzes for a given class WITH assignments
static Future<List<Map<String, dynamic>>> fetchTasksForClass(
  String classId,
) async {
  try {
    final supabase = Supabase.instance.client;
    
    // Fetch quizzes with their assignments directly
    final response = await supabase
        .from('quizzes')
        .select('''
          id, 
          title, 
          task_id, 
          class_room_id,
          tasks(id, title, created_at),
          assignments!inner(id, due_date)
        ''')
        .eq('class_room_id', classId);

    final list = List<Map<String, dynamic>>.from(response);

    // Sort by tasks.created_at descending
    list.sort((a, b) {
      final aDate = a['tasks']?['created_at'] != null
          ? DateTime.parse(a['tasks']['created_at'])
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b['tasks']?['created_at'] != null
          ? DateTime.parse(b['tasks']['created_at'])
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return list;
  } catch (e) {
    debugPrint("❌ Error fetching assignments: $e");
    return [];
  }
}

  /// Fetch quiz info along with questions, options, and correct answers
/// Fetch quiz info along with questions, options, and correct answers
static Future<Map<String, dynamic>?> fetchQuizWithQuestions(
  String quizId,
) async {
  try {
    final supabase = Supabase.instance.client;

    debugPrint("\n\n================= FETCHING QUIZ =================");
    debugPrint("📌 Quiz ID: $quizId");
    debugPrint("=================================================\n");

    // 1️⃣ Fetch quiz info
    final quiz = await supabase
        .from('quizzes')
        .select('id, title, task_id')
        .eq('id', quizId)
        .maybeSingle();

    debugPrint("📘 Raw Quiz Info: $quiz");

    if (quiz == null) {
      debugPrint("❌ Quiz not found in the database.");
      return null;
    }

    // 2️⃣ Fetch questions with all relationships INCLUDING NEW IMAGE FIELDS
    // REMOVE ALL COMMENTS FROM THE QUERY STRING!
    final questions = await supabase
        .from('quiz_questions')
        .select('''
          id,
          question_text,
          question_type,
          sort_order,
          time_limit_seconds,
          question_image_url,
          option_images,
          question_options(*),
          matching_pairs(*)
        ''')
        .eq('quiz_id', quizId)
        .order('sort_order', ascending: true);

    debugPrint("📥 Raw Questions Fetched: ${questions.length}\n");

    final quizQuestions = <QuizQuestion>[];

    int i = 1;
    for (final q in questions) {
      debugPrint("\n-----------------------------------------------");
      debugPrint("🔍 QUESTION $i RAW DB DATA:");
      debugPrint("ID: ${q['id']}");
      debugPrint("Text: ${q['question_text']}");
      debugPrint("Type: ${q['question_type']}");
      debugPrint("Question Image URL: ${q['question_image_url']}");
      debugPrint("Option Images JSON: ${q['option_images']}");
      debugPrint("Option Images Type: ${q['option_images']?.runtimeType}");
      
      // Parse option_images from JSONB column
      Map<String, String>? parsedOptionImages;
      if (q['option_images'] != null) {
        try {
          // Check if option_images is already a Map
          if (q['option_images'] is Map) {
            final optionImagesMap = q['option_images'] as Map;
            parsedOptionImages = {};
            optionImagesMap.forEach((key, value) {
              if (value != null && value.toString().isNotEmpty) {
                parsedOptionImages![key.toString()] = value.toString();
              }
            });
            debugPrint("Parsed option images from Map: $parsedOptionImages");
          } 
          // Check if option_images is a String (JSON string)
          else if (q['option_images'] is String) {
            final jsonString = q['option_images'] as String;
            if (jsonString.isNotEmpty && jsonString != '{}') {
              final decoded = json.decode(jsonString) as Map<String, dynamic>;
              parsedOptionImages = {};
              decoded.forEach((key, value) {
                if (value != null && value.toString().isNotEmpty) {
                  parsedOptionImages![key] = value.toString();
                }
              });
              debugPrint("Parsed option images from JSON string: $parsedOptionImages");
            }
          }
        } catch (e) {
          debugPrint("❌ Error parsing option_images: $e");
        }
      }

      // Use QuizQuestion.fromMap for safe parsing
      final question = QuizQuestion.fromMap({
        'id': q['id'],
        'question_text': q['question_text'],
        'question_type': q['question_type'],
        'question_options': q['question_options'] ?? [],
        'matching_pairs': q['matching_pairs'] ?? [],
        'time_limit_seconds': q['time_limit_seconds'],
        'question_image_url': q['question_image_url'],
        'option_images': parsedOptionImages, // Pass the parsed option images
      });

      // Debug log
      question.debugQuestionDataDetailed();

      quizQuestions.add(question);
      i++;
    }

    debugPrint("\n================= SUMMARY =================");
    debugPrint("🟢 Quiz Title: ${quiz['title']}");
    debugPrint("🟢 Total Questions Built: ${quizQuestions.length}");
    
    // Count question types
    final typeCounts = <String, int>{};
    for (final q in quizQuestions) {
      final typeName = q.type.name;
      typeCounts[typeName] = (typeCounts[typeName] ?? 0) + 1;
    }
    
    debugPrint("🟢 Question Types Breakdown:");
    typeCounts.forEach((type, count) {
      debugPrint("  • $type: $count");
    });
    
    // Check for images
    int questionsWithImages = 0;
    int optionsWithImages = 0;
    
    for (final q in quizQuestions) {
      if (q.questionImageUrl != null && q.questionImageUrl!.isNotEmpty) {
        questionsWithImages++;
      }
      if (q.optionImages != null && q.optionImages!.isNotEmpty) {
        optionsWithImages++;
      }
    }
    
    debugPrint("🟢 Questions with question images: $questionsWithImages");
    debugPrint("🟢 Questions with option images: $optionsWithImages");
    debugPrint("===========================================\n");

    return {'quiz': quiz, 'questions': quizQuestions};
  } catch (e, st) {
    debugPrint('❌ ERROR FETCHING QUIZ: $e');
    debugPrint(st.toString());
    return null;
  }
}

// Add to TaskService class

/// Delete a file from storage with proper bucket detection
static Future<bool> deleteStorageFile(String fileUrl) async {
  try {
    final supabase = Supabase.instance.client;
    
    if (fileUrl.isEmpty) return true;
    
    // Extract bucket and path from URL
    final (bucket, storagePath) = _extractBucketAndPath(fileUrl);
    
    if (bucket == null || storagePath == null) {
      debugPrint('⚠️ [STORAGE] Could not extract bucket/path from: $fileUrl');
      return false;
    }
    
    debugPrint('🗑️ [STORAGE] Deleting from bucket "$bucket": $storagePath');
    
    // Delete from the correct bucket
    await supabase.storage.from(bucket).remove([storagePath]);
    debugPrint('✅ [STORAGE] Deleted: $storagePath');
    return true;
  } catch (e) {
    debugPrint('❌ [STORAGE] Error deleting file: $e');
    return false;
  }
}

/// Extract bucket name and storage path from a Supabase storage URL
static (String? bucket, String? path) _extractBucketAndPath(String url) {
  try {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    
    // URL format: .../storage/v1/object/public/[BUCKET_NAME]/[PATH]
    final publicIndex = pathSegments.indexOf('public');
    if (publicIndex >= 0 && publicIndex + 1 < pathSegments.length) {
      final bucket = pathSegments[publicIndex + 1];
      // Return everything after the bucket
      final path = pathSegments.sublist(publicIndex + 2).join('/');
      debugPrint('🔍 [EXTRACT] Found bucket: $bucket, path: $path');
      return (bucket, path);
    }
    
    // Fallback: Try to extract from URL string using known bucket names
    final knownBuckets = [
      'materials',
      'student_voice',
      'essay_submissions',
      'document',
      'student_essay_attachments'
    ];
    
    for (final bucket in knownBuckets) {
      final bucketPattern = '/$bucket/';
      if (url.contains(bucketPattern)) {
        final parts = url.split(bucketPattern);
        if (parts.length > 1) {
          debugPrint('🔍 [EXTRACT] Found bucket via pattern: $bucket, path: ${parts[1]}');
          return (bucket, parts[1]);
        }
      }
    }
    
    debugPrint('⚠️ [EXTRACT] Could not extract bucket from URL: $url');
    return (null, null);
  } catch (e) {
    debugPrint('⚠️ [EXTRACT] Error extracting bucket and path: $e');
    return (null, null);
  }
}

/// Extract storage path from Supabase URL
static String? _extractStoragePath(String url) {
  try {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    
    // Find bucket name in path (materials, document, etc.)
    final bucketIndex = pathSegments.indexOf('materials');
    if (bucketIndex >= 0 && bucketIndex + 1 < pathSegments.length) {
      return pathSegments.sublist(bucketIndex + 1).join('/');
    }
    
    // Fallback: split by bucket name
    if (url.contains('materials/')) {
      final parts = url.split('materials/');
      if (parts.length > 1) return parts[1];
    }
    
    return null;
  } catch (e) {
    return null;
  }
}

/// Get all images associated with a quiz (both question and option images)
/// Get all images associated with a quiz (both question, option images, and matching pair images)
static Future<List<String>> getQuizImages(String quizId) async {
  final supabase = Supabase.instance.client;
  final images = <String>[];
  
  try {
    // Get all questions for this quiz
    final questions = await supabase
        .from('quiz_questions')
        .select('id, question_image_url, option_images')
        .eq('quiz_id', quizId);
    
    for (final question in questions) {
      final questionId = question['id'] as String;
      
      // Add question image (stored in question_images folder)
      final questionImage = question['question_image_url'] as String?;
      if (questionImage != null && questionImage.isNotEmpty) {
        images.add(questionImage);
        debugPrint('📸 Found question image: $questionImage');
      }
      
      // Add option images (stored in option_images folder)
      final optionImages = question['option_images'];
      if (optionImages != null) {
        if (optionImages is Map) {
          optionImages.forEach((key, value) {
            if (value != null && value.toString().isNotEmpty) {
              images.add(value.toString());
              debugPrint('📸 Found option image for key $key: $value');
            }
          });
        } else if (optionImages is String && optionImages.isNotEmpty) {
          try {
            final decoded = json.decode(optionImages) as Map;
            decoded.forEach((key, value) {
              if (value != null && value.toString().isNotEmpty) {
                images.add(value.toString());
                debugPrint('📸 Found option image from JSON: $value');
              }
            });
          } catch (e) {
            debugPrint('⚠️ Error parsing option_images JSON: $e');
          }
        }
      }
      
      // ========== NEW: Get matching pair images for this question ==========
      final matchingPairs = await supabase
          .from('matching_pairs')
          .select('right_item_url')
          .eq('question_id', questionId);
      
      for (final pair in matchingPairs) {
        final rightItemUrl = pair['right_item_url'] as String?;
        if (rightItemUrl != null && rightItemUrl.isNotEmpty) {
          images.add(rightItemUrl);
          debugPrint('📸 Found matching pair image: $rightItemUrl');
        }
      }
    }
    
    // Remove duplicates
    final uniqueImages = images.toSet().toList();
    debugPrint('📸 Total unique images found: ${uniqueImages.length}');
    
    return uniqueImages;
  } catch (e) {
    debugPrint('❌ Error getting quiz images: $e');
    return [];
  }
}

/// Get all images associated with an essay assignment (including attached files from JSONB)
static Future<List<String>> getEssayImages(String essayId, String assignmentId) async {
  final supabase = Supabase.instance.client;
  final images = <String>[];
  
  try {
    // 1. Get essay questions that have images
    final essayQuestions = await supabase
        .from('essay_questions')
        .select('question_image_url')
        .eq('essay_assignment_id', essayId);
    
    for (final question in essayQuestions) {
      final questionImage = question['question_image_url'] as String?;
      if (questionImage != null && questionImage.isNotEmpty) {
        images.add(questionImage);
        debugPrint('📸 Found essay question image: $questionImage');
      }
    }
    
    // 2. Get student essay responses with attached files from JSONB column
    final essayResponses = await supabase
        .from('student_essay_responses')
        .select('attached_files')
        .eq('assignment_id', assignmentId);
    
    for (final response in essayResponses) {
      final attachedFiles = response['attached_files'];
      if (attachedFiles != null) {
        List<String> attachmentUrls = [];
        
        // Parse attached_files JSONB
        if (attachedFiles is List) {
          // Already parsed as List
          attachmentUrls = attachedFiles.cast<String>();
        } else if (attachedFiles is String && attachedFiles.isNotEmpty) {
          // Parse JSON string
          try {
            final decoded = json.decode(attachedFiles);
            if (decoded is List) {
              attachmentUrls = decoded.cast<String>();
            }
          } catch (e) {
            debugPrint('⚠️ Error parsing attached_files JSON: $e');
          }
        } else if (attachedFiles is Map && attachedFiles.containsKey('files')) {
          // Alternative structure if files are stored under 'files' key
          final files = attachedFiles['files'];
          if (files is List) {
            attachmentUrls = files.cast<String>();
          }
        }
        
        // Add each attachment URL to the list
        for (final url in attachmentUrls) {
          if (url.isNotEmpty) {
            images.add(url);
            debugPrint('📸 Found student attachment: $url');
          }
        }
      }
    }
    
    debugPrint('📸 Total essay images found: ${images.length}');
    return images;
  } catch (e) {
    debugPrint('❌ Error getting essay images: $e');
    return [];
  }
}


}

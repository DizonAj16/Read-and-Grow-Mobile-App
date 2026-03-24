import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/material_model.dart';
import '../utils/validators.dart';
import '../utils/data_validators.dart';
import '../utils/database_helpers.dart';
import '../utils/file_validator.dart';

class MaterialService {
  static final supabase = Supabase.instance.client;

static Future<bool> uploadMaterialFile({
  // REMOVE:  required File file,
  required Uint8List fileBytes,      // ← raw bytes, works on web + native
  required String fileName,          // ← original filename (with extension)
  required String materialTitle,
  required String classroomId,
  String? materialType,
  String? description,
  double sizeLimitMB = FileValidator.defaultMaxSizeMB,
}) async {
  try {
    debugPrint('📦 [UPLOAD_MATERIAL] Starting material upload');

    final user = supabase.auth.currentUser;
    if (user == null) throw Exception("No logged in teacher");

    if (materialTitle.trim().isEmpty) throw Exception("Material title is required");
    if (classroomId.isEmpty || !Validators.isValidUUID(classroomId))
      throw Exception("Invalid classroom ID");

    // ✅ Validate size from bytes (works on web + native)
    final sizeValidation = FileValidator.validateBytes(fileBytes, limitMB: sizeLimitMB);
    if (!sizeValidation.isValid) {
      throw FileSizeLimitException(
        FileValidator.backendLimitMessage(sizeLimitMB),
        actualSizeMB: sizeValidation.actualSizeMB,
        limitMB: sizeLimitMB,
      );
    }

    final fileExtension = fileName.split('.').last.toLowerCase();
    final allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'mp4', 'mp3'];
    if (!allowedExtensions.contains(fileExtension))
      throw Exception('File type not allowed: $fileExtension');

    final materialData = <String, dynamic>{
      'material_title': materialTitle.trim(),
      'class_room_id': classroomId,
      'uploaded_by': user.id,
      if (materialType != null && materialType.isNotEmpty)
        'material_type': materialType,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    };

    final contentType = _contentTypeFromExtension(fileExtension);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitized = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = "$classroomId/$timestamp-$sanitized";

    await supabase.storage.from('materials').uploadBinary(
      storagePath,
      fileBytes,
      fileOptions: FileOptions(upsert: true, contentType: contentType),
    );

    final publicUrl = supabase.storage.from('materials').getPublicUrl(storagePath);
    if (publicUrl.isEmpty) throw Exception("Failed to get file URL");

    final finalData = {
      ...materialData,
      'material_file_url': publicUrl,
      'file_size': fileBytes.lengthInBytes.toString(),
      'file_extension': fileExtension,
    };

    final validationErrors = DataValidators.validateMaterialData(finalData);
    if (DataValidators.hasErrors(validationErrors)) {
      await supabase.storage.from('materials').remove([storagePath]);
      throw Exception(DataValidators.getErrorMessage(validationErrors));
    }

    final insertResult = await DatabaseHelpers.safeInsert(
      supabase: supabase,
      table: 'materials',
      data: finalData,
    );

    if (insertResult == null || insertResult.containsKey('error')) {
      await supabase.storage.from('materials').remove([storagePath]);
      throw Exception(insertResult?['error'] ?? 'Failed to save material record');
    }

    debugPrint('✅ [UPLOAD_MATERIAL] Done — ID: ${insertResult['id']}');
    return true;
  } on FileSizeLimitException {
    rethrow;
  } catch (e, st) {
    debugPrint("❌ [UPLOAD_MATERIAL] $e\n$st");
    return false;
  }
}

// Helper (add as private static inside MaterialService)
static String? _contentTypeFromExtension(String ext) {
  const map = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'mp4': 'video/mp4',
    'mp3': 'audio/mpeg',
  };
  return map[ext];
}

  static Future<List<MaterialModel>> getClassroomMaterials(String classId) async {
    try {
      // Validate class ID
      if (classId.isEmpty || !Validators.isValidUUID(classId)) {
        print("Invalid class ID: $classId");
        return [];
      }

      final response = await DatabaseHelpers.safeGetList(
        supabase: supabase,
        table: 'materials',
        filters: {'class_room_id': classId},
        orderBy: 'created_at',
        ascending: false,
      );

      print("📥 Raw response: ${response.length} materials");

      final materials = <MaterialModel>[];
      for (var json in response) {
        try {
          materials.add(MaterialModel.fromJson(Map<String, dynamic>.from(json)));
        } catch (e) {
          print("Error parsing material: $e");
          // Continue with other materials
        }
      }

      return materials;
    } catch (e) {
      print("Error fetching classroom materials: $e");
      return [];
    }
  }

  static Future<List<MaterialModel>> fetchStudentMaterials() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        print("No logged in student");
        return [];
      }

      if (user.id.isEmpty) {
        print("Invalid user ID");
        return [];
      }

      final enrollments = await DatabaseHelpers.safeGetList(
        supabase: supabase,
        table: 'student_enrollments',
        filters: {'student_id': user.id},
      );

      if (enrollments.isEmpty) return [];

      final classIds = enrollments
          .map((e) => DatabaseHelpers.safeStringFromResult(e, 'class_room_id'))
          .where((id) => id.isNotEmpty && Validators.isValidUUID(id))
          .toList();

      if (classIds.isEmpty) return [];

      // Fetch materials for all classes
      final allMaterials = <MaterialModel>[];
      for (final classId in classIds) {
        try {
          final materials = await getClassroomMaterials(classId);
          allMaterials.addAll(materials);
        } catch (e) {
          print("Error fetching materials for class $classId: $e");
          // Continue with other classes
        }
      }

      return allMaterials;
    } catch (e) {
      print("Error fetching student materials: $e");
      return [];
    }
  }

  static Future<bool> deleteMaterial(int materialId) async {
    try {
      if (materialId <= 0) {
        print("Invalid material ID: $materialId");
        return false;
      }

      final material = await DatabaseHelpers.safeGetSingle(
        supabase: supabase,
        table: 'materials',
        filters: {'id': materialId},
      );

      if (material == null) {
        print("Material not found: $materialId");
        return false;
      }

      final fileUrl = DatabaseHelpers.safeStringFromResult(material, 'material_file_url');
      
      // Try to delete file from storage if URL contains path
      if (fileUrl.isNotEmpty && fileUrl.contains("materials/")) {
        try {
          final path = fileUrl.split("/").last;
          if (path.isNotEmpty) {
            await supabase.storage.from('materials').remove([path]);
          }
        } catch (storageError) {
          print("Error deleting file from storage: $storageError");
          // Continue with database deletion even if storage deletion fails
        }
      }

      final deleteSuccess = await DatabaseHelpers.safeDelete(
        supabase: supabase,
        table: 'materials',
        id: materialId.toString(),
      );

      return deleteSuccess;
    } catch (e) {
      print("Error deleting material: $e");
      return false;
    }
  }

  static Future<List<MaterialModel>> getMaterialsByType(
      String classId, String type) async {
    try {
      // Validate class ID
      if (classId.isEmpty || !Validators.isValidUUID(classId)) {
        print("Invalid class ID: $classId");
        return [];
      }

      final response = await DatabaseHelpers.safeGetList(
        supabase: supabase,
        table: 'materials',
        filters: {
          'class_room_id': classId,
          'material_type': type,
        },
        orderBy: 'created_at',
        ascending: false,
      );

      final materials = <MaterialModel>[];
      for (var json in response) {
        try {
          materials.add(MaterialModel.fromJson(Map<String, dynamic>.from(json)));
        } catch (e) {
          print("Error parsing material: $e");
          // Continue with other materials
        }
      }

      return materials;
    } catch (e) {
      print("Error fetching materials by type: $e");
      return [];
    }
  }
}

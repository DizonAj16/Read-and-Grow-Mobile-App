import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../api/user_service.dart';
import '../../models/teacher_model.dart';
import '../../utils/validators.dart';
import '../../utils/data_validators.dart';
import '../../utils/database_helpers.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class EditTeacherProfilePage extends StatefulWidget {
  const EditTeacherProfilePage({super.key});

  @override
  State<EditTeacherProfilePage> createState() => _EditTeacherProfilePageState();
}

class _EditTeacherProfilePageState extends State<EditTeacherProfilePage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _positionController;
  late TextEditingController _usernameController;
  
  // State variables
  Teacher? _currentTeacher;
  XFile? _pickedImageFile;
  Uint8List? _webImageBytes; // ADD THIS
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _positionController = TextEditingController();
    _usernameController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _positionController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No logged in user');
      }

      if (!Validators.isValidUUID(user.id)) {
        throw Exception('Invalid user ID');
      }

      final teacherData = await _loadTeacherData(user.id);

      setState(() {
        _currentTeacher = teacherData;
        
        // Populate controllers
        _nameController.text = teacherData.name;
        _emailController.text = teacherData.email ?? '';
        _positionController.text = teacherData.position ?? '';
        _usernameController.text = teacherData.username ?? '';
        
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading teacher data: $e');
      setState(() {
        _errorMessage = 'Failed to load profile data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<Teacher> _loadTeacherData(String userId) async {
    try {
      // Try to load from Supabase
      final response = await DatabaseHelpers.safeGetSingle(
        supabase: supabase,
        table: 'teachers',
        id: userId,
      );

      if (response == null) {
        // Fallback to SharedPreferences
        try {
          final teacher = await Teacher.fromPrefs();
          return teacher;
        } catch (e) {
          throw Exception('Teacher record not found');
        }
      }

      // Also get username from users table
      final userResponse = await DatabaseHelpers.safeGetSingle(
        supabase: supabase,
        table: 'users',
        id: userId,
      );

      final teacherJson = Map<String, dynamic>.from(response);
      if (userResponse != null) {
        teacherJson['username'] = DatabaseHelpers.safeStringFromResult(userResponse, 'username');
      }

      return Teacher.fromJson(teacherJson);
    } catch (e) {
      debugPrint('Error parsing teacher data: $e');
      throw Exception('Failed to parse teacher data');
    }
  }

Future<void> _pickImage() async {
  try {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _pickedImageFile = pickedFile;
        _webImageBytes = bytes;
      });
    }
  } catch (e) {
    debugPrint('Error picking image: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }
}

  Future<bool> _checkDuplicateEmail(String email, String excludeUserId) async {
    try {
      if (!Validators.isValidUUID(excludeUserId)) {
        return false;
      }

      // Check for duplicate email excluding current teacher
      final teachers = await DatabaseHelpers.safeGetList(
        supabase: supabase,
        table: 'teachers',
        filters: {'teacher_email': email},
        limit: 10,
      );

      // Filter out current teacher
      return teachers.any((teacher) {
        final id = DatabaseHelpers.safeStringFromResult(teacher, 'id');
        return id.isNotEmpty && id != excludeUserId;
      });
    } catch (e) {
      debugPrint('Error checking duplicate email: $e');
      return false;
    }
  }

  Future<bool> _checkDuplicateUsername(String username, String excludeUserId) async {
    try {
      if (!Validators.isValidUUID(excludeUserId)) {
        return false;
      }

      // Check in users table (unique constraint)
      final users = await DatabaseHelpers.safeGetList(
        supabase: supabase,
        table: 'users',
        filters: {'username': username},
        limit: 10,
      );

      // Check if any user (other than current) has this username
      return users.any((user) {
        final id = DatabaseHelpers.safeStringFromResult(user, 'id');
        return id.isNotEmpty && id != excludeUserId;
      });
    } catch (e) {
      debugPrint('Error checking duplicate username: $e');
      return false;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final user = supabase.auth.currentUser;
      final currentTeacher = _currentTeacher;
      if (user == null || currentTeacher == null) {
        throw Exception('No logged in user');
      }

      final trimmedName = _nameController.text.trim();
      final trimmedEmail = _emailController.text.trim();
      final trimmedPosition = _positionController.text.trim();
      final trimmedUsername = _usernameController.text.trim();

      // Check for duplicate email (if changed)
      final currentEmail = _currentTeacher?.email ?? '';
      if (trimmedEmail.isNotEmpty && trimmedEmail != currentEmail) {
        final emailExists = await _checkDuplicateEmail(trimmedEmail, user.id);
        if (emailExists) {
          throw Exception('Email already exists. Please use a different email.');
        }
      }

      // Check for duplicate username (if changed)
      final currentUsername = _currentTeacher?.username ?? '';
      if (trimmedUsername.isNotEmpty && trimmedUsername != currentUsername) {
        final usernameExists = await _checkDuplicateUsername(trimmedUsername, user.id);
        if (usernameExists) {
          throw Exception('Username already exists. Please use a different username.');
        }
      }

      // Upload profile picture if selected
      String? profilePictureUrl;
      if (_pickedImageFile != null) {
  final uploadedUrl = await UserService.uploadProfilePicture(
    userId: user.id,
    role: 'teacher',
    filePath: kIsWeb ? _pickedImageFile!.name : _pickedImageFile!.path,
    fileBytes: kIsWeb ? _webImageBytes : null, // ✅ pass bytes for web
  );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          profilePictureUrl = uploadedUrl;
        } else {
          throw Exception('Failed to upload profile picture');
        }
      }

      // Validate teacher data before update
      final teacherData = {
        'teacher_name': trimmedName,
        'teacher_email': trimmedEmail.isNotEmpty ? trimmedEmail : null,
        'teacher_position': trimmedPosition.isNotEmpty ? trimmedPosition : null,
      };
      final validationErrors = DataValidators.validateTeacherData(teacherData);
      if (DataValidators.hasErrors(validationErrors)) {
        throw Exception(DataValidators.getErrorMessage(validationErrors));
      }

      // Update teacher record
      final updatePayload = <String, dynamic>{
        'teacher_name': trimmedName,
        'teacher_position': trimmedPosition.isNotEmpty ? trimmedPosition : null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Only update email if it's not empty and changed
      if (trimmedEmail.isNotEmpty && trimmedEmail != currentEmail) {
        updatePayload['teacher_email'] = trimmedEmail;
      }

      if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
        updatePayload['profile_picture'] = profilePictureUrl;
      }

      // Remove null values
      updatePayload.removeWhere((key, value) => value == null);

      final updateSuccess = await DatabaseHelpers.safeUpdate(
        supabase: supabase,
        table: 'teachers',
        id: user.id,
        data: updatePayload,
      );

      if (!updateSuccess) {
        throw Exception('Failed to update teacher record');
      }

      // Update username in users table if changed
      if (trimmedUsername.isNotEmpty && trimmedUsername != currentUsername) {
        final userUpdateSuccess = await DatabaseHelpers.safeUpdate(
          supabase: supabase,
          table: 'users',
          id: user.id,
          data: {'username': trimmedUsername},
        );

        if (!userUpdateSuccess) {
          debugPrint('Warning: Failed to update username in users table');
          // Don't throw - teacher record was updated successfully
        }
      }

      // Update local preferences
      final updatedTeacher = Teacher(
        id: currentTeacher.id,
        userId: currentTeacher.userId ?? int.tryParse(user.id),
        name: trimmedName,
        position: trimmedPosition.isNotEmpty ? trimmedPosition : null,
        email: trimmedEmail.isNotEmpty ? trimmedEmail : currentTeacher.email,
        username: trimmedUsername.isNotEmpty ? trimmedUsername : currentTeacher.username,
        profilePicture: profilePictureUrl ?? currentTeacher.profilePicture,
        createdAt: currentTeacher.createdAt,
        updatedAt: DateTime.now(),
      );
      await updatedTeacher.saveToPrefs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text('Profile updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        );
        
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage ?? 'Failed to update profile',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading profile...',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage != null && _currentTeacher == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Oops!',
                          style: textTheme.headlineSmall?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _loadData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Profile Picture Section
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.1),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Profile Picture',
                                style: textTheme.titleMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          colorScheme.primary.withOpacity(0.2),
                                          colorScheme.primary.withOpacity(0.05),
                                        ],
                                      ),
                                    ),
                                    child: CircleAvatar(
  radius: 60,
  backgroundColor: Colors.transparent,
  backgroundImage: _webImageBytes != null
      ? MemoryImage(_webImageBytes!) // ✅ Web picked image
      : _pickedImageFile != null && !kIsWeb
          ? FileImage(File(_pickedImageFile!.path)) // Mobile picked image
          : _currentTeacher?.profilePicture != null &&
                  _currentTeacher!.profilePicture!.isNotEmpty
              ? NetworkImage(_currentTeacher!.profilePicture!) // Existing profile
              : null,
  child: _pickedImageFile == null &&
          _webImageBytes == null &&
          (_currentTeacher?.profilePicture == null ||
              _currentTeacher!.profilePicture!.isEmpty)
      ? Icon(Icons.person, size: 70,
          color: colorScheme.primary.withOpacity(0.4))
      : null,
),
                                  ),
                                  Positioned(
                                    bottom: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: _pickImage,
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              colorScheme.primary,
                                              colorScheme.primaryContainer,
                                            ],
                                          ),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: colorScheme.primary.withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                          border: Border.all(
                                            color: colorScheme.surface,
                                            width: 3,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.camera_alt,
                                          color: colorScheme.onPrimary,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Tap camera icon to change photo',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Form Fields Section
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Personal Information',
                                style: textTheme.titleMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Update your profile details below',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Name Field
                              _buildTextField(
                                controller: _nameController,
                                label: 'Full Name *',
                                icon: Icons.person_outline,
                                validator: _validateName,
                              ),
                              const SizedBox(height: 20),

                              // Email Field
                              _buildTextField(
                                controller: _emailController,
                                label: 'Email (Optional)',
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                validator: _validateEmail,
                              ),
                              const SizedBox(height: 20),

                              // Position Field
                              _buildTextField(
                                controller: _positionController,
                                label: 'Position (Optional)',
                                icon: Icons.work_outline,
                                validator: _validatePosition,
                              ),
                              const SizedBox(height: 20),

                              // Username Field
                              _buildTextField(
                                controller: _usernameController,
                                label: 'Username (Optional)',
                                icon: Icons.alternate_email,
                                validator: _validateUsername,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Error Message Display
                        if (_errorMessage != null && _isSaving == false)
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: _errorMessage != null ? 1.0 : 0.0,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorScheme.error.withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: colorScheme.error,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Save Button
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primaryContainer,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                              disabledBackgroundColor: colorScheme.primary.withOpacity(0.5),
                            ),
                            child: _isSaving
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            colorScheme.onPrimary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Saving...',
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onPrimary,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.save_as_rounded,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Save Changes',
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Cancel Button
                        TextButton(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  Navigator.pop(context);
                                },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        prefixIcon: Icon(
          icon,
          color: colorScheme.primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outline.withOpacity(0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outline.withOpacity(0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
  }

  // Validation Methods
  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    // Optional field, but if provided, must be valid
    if (value != null && value.trim().isNotEmpty) {
      final trimmed = value.trim();
      final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      if (!emailRegex.hasMatch(trimmed)) {
        return 'Please enter a valid email address';
      }
    }
    return null;
  }

  String? _validatePosition(String? value) {
    // Optional field, no validation needed
    return null;
  }

  String? _validateUsername(String? value) {
    // Optional field, but if provided, must be valid
    if (value != null && value.trim().isNotEmpty) {
      final trimmed = value.trim();
      if (trimmed.length < 2) {
        return 'Username must be at least 2 characters';
      }
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
        return 'Username can only contain letters, numbers, and underscores';
      }
    }
    return null;
  }
}
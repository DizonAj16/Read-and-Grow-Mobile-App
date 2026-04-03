import 'dart:ui';
import 'package:deped_reading_app_laravel/api/user_service.dart';
import 'package:deped_reading_app_laravel/models/student_model.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../widgets/ui_states.dart';
import '../../utils/database_helpers.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'edit_student_profile_page.dart';

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  late Future<Student> _studentFuture;
  XFile? _pickedImageFile;
  bool _isUploading = false;
  Student? _currentStudent;

  @override
  void initState() {
    super.initState();
    _studentFuture = _initializeStudentData();
  }

  Future<Student> _initializeStudentData() async {
    final supabase = Supabase.instance.client;

    Student student;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No logged in student');

      if (currentUser.id.isEmpty) {
        throw Exception('Invalid user ID');
      }

      final response = await DatabaseHelpers.safeGetSingle(
        supabase: supabase,
        table: 'students',
        id: currentUser.id,
      );

      if (response == null) throw Exception('Student record not found');

      try {
        student = Student.fromJson(Map<String, dynamic>.from(response));
        await student.saveToPrefs();
        debugPrint('✅ Student data fetched from Supabase');
      } catch (e) {
        debugPrint('Error parsing student data: $e');
        throw Exception('Failed to parse student data');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching from Supabase: $e');

      try {
        student = await Student.fromPrefs();
        debugPrint('📦 Student data loaded from SharedPreferences');
      } catch (prefsError) {
        debugPrint('Error loading from preferences: $prefsError');
        student = Student(
          id: '',
          studentName: 'Student',
          studentLrn: null,
          completedTasks: 0,
        );
      }
    }

    if (student.profilePicture != null && student.profilePicture!.isNotEmpty) {
      try {
        if (student.profilePicture!.startsWith('http')) {
          debugPrint('🖼️ Profile picture is already a full URL');
          return student;
        }

        final bucketBaseUrl = supabase.storage
            .from('materials')
            .getPublicUrl(student.profilePicture!);

        if (bucketBaseUrl.isNotEmpty) {
          student = student.copyWith(profilePicture: bucketBaseUrl);
          debugPrint('🖼️ Normalized profile picture URL: $bucketBaseUrl');
        }
      } catch (e) {
        debugPrint('⚠️ Error normalizing profile picture URL: $e');
      }
    }

    return student;
  }

  Future<void> _pickAndUploadImage(Student student) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      setState(() => _pickedImageFile = pickedFile);

      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => ConfirmationDialog(
              imagePath: pickedFile.path,
              title: "Confirm Upload",
            ),
      );

      if (confirmed != true) {
        setState(() => _pickedImageFile = null);
        return;
      }

      setState(() => _isUploading = true);
      final uploadStartTime = DateTime.now();

      final uploadedUrl = await UserService.uploadProfilePicture(
        userId: student.userId.toString(),
        role: 'student',
        filePath: pickedFile.path,
      );

      final elapsed = DateTime.now().difference(uploadStartTime);
      final remainingDelay = const Duration(seconds: 2) - elapsed;
      if (remainingDelay > Duration.zero) {
        await Future.delayed(remainingDelay);
      }

      if (uploadedUrl != null) {
        final updatedStudent = student.copyWith(profilePicture: uploadedUrl);
        await updatedStudent.saveToPrefs();

        setState(() {
          _studentFuture = Future.value(updatedStudent);
          _pickedImageFile = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(UploadSuccessSnackBar());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(UploadErrorSnackBar(500));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'My Profile',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimary,
          ),
        ),
        backgroundColor: colorScheme.primary.withOpacity(0.8),
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.edit, color: colorScheme.onPrimary),
            tooltip: 'Edit Info',
            onPressed:
                _currentStudent == null
                    ? null
                    : () => _handleEditStudent(_currentStudent!),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primary,
              colorScheme.secondary,
            ],
          ),
        ),
        child: FutureBuilder<Student>(
          future: _studentFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingState(message: 'Loading profile...');
            }

            if (!snapshot.hasData || snapshot.hasError) {
              return const ErrorState(message: "Couldn't load profile");
            }

            final student = snapshot.data!;
            _currentStudent = student;
            return _buildProfileContent(student);
          },
        ),
      ),
    );
  }

  Future<void> _handleEditStudent(Student student) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const EditStudentProfilePage()),
    );

    if (updated == true) {
      setState(() {
        _studentFuture = _initializeStudentData();
      });
    }
  }

  Widget _buildProfileContent(Student student) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 80),
          _GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _ProfileAvatar(
                  student: student,
                  pickedImage: _pickedImageFile,
                  isUploading: _isUploading,
                  onTap: () => _pickAndUploadImage(student),
                ),
                const SizedBox(height: 18),
                Text(
                  student.studentName,
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'ComicNeue',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          _GlassCard(
            child: Column(
              children: [
                _InfoTile(
                  icon: Icons.school_rounded,
                  text: "LRN: ${student.studentLrn ?? 'Not set'}",
                  iconColor: colorScheme.primary,
                ),
                Divider(
                  height: 0,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.onPrimary.withOpacity(0.3),
                ),
                _InfoTile(
                  icon: Icons.star_rounded,
                  text: "Grade: ${student.studentGrade ?? 'Not set'}",
                  iconColor: colorScheme.secondary,
                ),
                Divider(
                  height: 0,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.onPrimary.withOpacity(0.3),
                ),
                _InfoTile(
                  icon: Icons.group_rounded,
                  text: "Section: ${student.studentSection ?? 'Not set'}",
                  iconColor: colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const _GlassCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.onSurface.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(0),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final Student student;
  final XFile? pickedImage;
  final bool isUploading;
  final VoidCallback onTap;

  const _ProfileAvatar({
    required this.student,
    this.pickedImage,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Hero(
      tag: 'student-profile-image',
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.onPrimary,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
              ],
            ),
            child:
                isUploading
                    ? Lottie.asset('assets/animation/loading_rainbow.json')
                    : CircleAvatar(
                      radius: 60,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage: _getProfileImage(student),
                      child:
                          pickedImage == null && student.profilePicture == null
                              ? Icon(
                                Icons.person,
                                size: 50,
                                color: colorScheme.onPrimaryContainer,
                              )
                              : null,
                    ),
          ),
          Positioned(
            bottom: 0,
            right: 4,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.secondary,
                  border: Border.all(
                    color: colorScheme.onSecondary,
                    width: 2,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: 20,
                  color: colorScheme.onSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider<Object> _getProfileImage(Student student) {
    if (pickedImage != null) return FileImage(File(pickedImage!.path));
    if (student.profilePicture != null)
      return NetworkImage(student.profilePicture!);
    return const AssetImage('assets/placeholder/student_placeholder.png');
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;

  const _InfoTile({
    required this.icon,
    required this.text,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.primary;
    
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: effectiveIconColor.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: effectiveIconColor, size: 24),
      ),
      title: Text(
        text,
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontSize: 18,
          fontFamily: 'ComicNeue',
        ),
      ),
    );
  }
}

class ConfirmationDialog extends StatelessWidget {
  final String imagePath;
  final String title;

  const ConfirmationDialog({required this.imagePath, required this.title});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.onPrimary, width: 2),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'ComicNeue',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.onPrimary, width: 3),
                borderRadius: BorderRadius.circular(100),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: Image.file(
                  File(imagePath),
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Use this as your new profile picture?",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontSize: 16,
                fontFamily: 'ComicNeue',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: colorScheme.onError,
                      fontFamily: 'ComicNeue',
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[400],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'Yes!',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'ComicNeue',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UploadSuccessSnackBar extends SnackBar {
  UploadSuccessSnackBar()
    : super(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            const Text(
              "Yay! New profile picture saved!",
              style: TextStyle(fontFamily: 'ComicNeue'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
}

class UploadErrorSnackBar extends SnackBar {
  UploadErrorSnackBar(int? statusCode)
    : super(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              "Oops! Upload failed${statusCode != null ? ' (Code: $statusCode)' : ''}",
              style: const TextStyle(fontFamily: 'ComicNeue'),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
}
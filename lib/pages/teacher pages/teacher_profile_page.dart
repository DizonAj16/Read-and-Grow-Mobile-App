import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:deped_reading_app_laravel/api/supabase_auth_service.dart';
import 'package:deped_reading_app_laravel/api/user_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:deped_reading_app_laravel/utils/file_validator.dart';
import '../../models/teacher_model.dart';
import 'edit_teacher_profile_page.dart';

class TeacherProfilePage extends StatefulWidget {
  const TeacherProfilePage({super.key});

  @override
  State<TeacherProfilePage> createState() => _TeacherProfilePageState();
}

class _TeacherProfilePageState extends State<TeacherProfilePage> {
  Teacher? _teacher;
  String baseUrl = 'http://10.0.2.2:8000';
  XFile? _pickedImageFile;
  late Future<Teacher> _teacherFuture;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _teacherFuture = _loadTeacherData();
  }

  Future<Teacher> _loadTeacherData() async {
    final startTime = DateTime.now();

    try {
      // ✅ Call SupabaseAuthService instead of AuthService
      final profileResponse = await SupabaseAuthService.getAuthProfile();

      // ✅ Cast maps safely
      final Map<String, dynamic> userData =
          (profileResponse?['user'] as Map?)?.cast<String, dynamic>() ?? {};
      final Map<String, dynamic> profileData =
          (profileResponse?['profile'] as Map?)?.cast<String, dynamic>() ?? {};

      // ✅ Merge into one JSON for Teacher model
      final teacherJson = {
        ...userData,
        ...profileData,
        'id': userData['id'], // Supabase user id
        'teacher_id': profileData['id'], // teacher table id
      };

      final teacher = Teacher.fromJson(teacherJson);
      await teacher.saveToPrefs();

      if (mounted) {
        setState(() => _teacher = teacher);
      }

      // ✅ Ensure minimum 2 second loading
      final elapsed = DateTime.now().difference(startTime);
      final remaining = const Duration(seconds: 2) - elapsed;
      if (remaining > Duration.zero) await Future.delayed(remaining);

      return teacher;
    } catch (e) {
      debugPrint("⚠️ API failed, loading from prefs instead: $e");

      try {
        final teacher = await Teacher.fromPrefs();
        if (mounted) {
          setState(() => _teacher = teacher);
        }

        final elapsed = DateTime.now().difference(startTime);
        final remaining = const Duration(seconds: 2) - elapsed;
        if (remaining > Duration.zero) await Future.delayed(remaining);

        return teacher;
      } catch (prefsError) {
        debugPrint("❌ Failed to load teacher from prefs: $prefsError");

        final elapsed = DateTime.now().difference(startTime);
        final remaining = const Duration(seconds: 2) - elapsed;
        if (remaining > Duration.zero) await Future.delayed(remaining);

        return Future.error("Unable to load teacher data.");
      }
    }
  }

  Future<void> _pickAndUploadImage({
    required String role,
    required String userId,
  }) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      final sizeValidation = await validateFileSize(
        File(pickedFile.path),
        limitMB: FileValidator.defaultMaxSizeMB,
      );
      if (!sizeValidation.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade100, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sizeValidation.getUserMessage(),
                      style: TextStyle(
                        color: Colors.red.shade100,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              duration: const Duration(seconds: 4),
              elevation: 6,
            ),
          );
        }
        return; // Prevent upload button from triggering
      }

      setState(() {
        _pickedImageFile = pickedFile;
      });

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 25,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title with icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_camera_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Confirm Upload",
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Image preview
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.4),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.file(
                        File(pickedFile.path),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Smaller and lighter text
                  Text(
                    "Use this image as your profile picture?",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Buttons with icons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          icon: Icon(
                            Icons.cancel_rounded,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.8),
                          ),
                          label: Text(
                            "Cancel",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          icon: Icon(
                            Icons.cloud_upload_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                          label: Text(
                            "Upload",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (confirmed != true) {
        setState(() => _pickedImageFile = null);
        return;
      }

      setState(() => _isUploading = true);

      final uploadedUrl = await UserService.uploadProfilePicture(
        userId: userId,
        role: role,
        filePath: pickedFile.path,
      );

      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        debugPrint('✅ Uploaded Profile URL: $uploadedUrl');

        // Reload teacher data to get the updated profile picture
        setState(() {
          _isUploading = false;
          _pickedImageFile = null;
        });
        
        // Reload teacher data
        final updatedTeacher = await _loadTeacherData();
        
        if (mounted) {
          setState(() {
            _teacher = updatedTeacher;
            _teacherFuture = Future.value(updatedTeacher);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade100, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Profile picture updated successfully!",
                      style: TextStyle(
                        color: Colors.green.shade100,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              duration: const Duration(seconds: 3),
              elevation: 6,
            ),
          );
        }
      }  else {
        // Error SnackBar
        if (mounted) {
          setState(() {
            _isUploading = false;
            _pickedImageFile = null;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade100, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Failed to upload image. Please try again.",
                      style: TextStyle(
                        color: Colors.red.shade100,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              duration: const Duration(seconds: 4),
              elevation: 6,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error uploading profile picture: $e');
      // Exception SnackBar
      if (mounted) {
        setState(() {
          _isUploading = false;
          _pickedImageFile = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade100,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Error uploading image: ${e.toString().split(':').last}",
                    style: TextStyle(
                      color: Colors.orange.shade100,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            duration: const Duration(seconds: 4),
            elevation: 6,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Widget _glassCard({
    required Widget child,
    double blur = 0.5,
    double opacity = 0.25, // Increased opacity for better readability
    EdgeInsets? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.3), // Brighter border
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15), // Darker shadow
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: padding ?? const EdgeInsets.all(0),
          child: child,
        ),
      ),
    );
  }

  Widget _getProfileImageWidget() {
    if (_pickedImageFile != null) {
      return FadeInImage(
        placeholder: const AssetImage(
          'assets/placeholder/avatar_placeholder.jpg',
        ),
        image: FileImage(File(_pickedImageFile!.path)),
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeInCurve: Curves.fastEaseInToSlowEaseOut,
      );
    } else if (_teacher?.profilePicture != null &&
        _teacher!.profilePicture!.isNotEmpty) {
      // Handle profile picture URL - check if it's already a full URL or needs Supabase storage path
      String profileUrl = _teacher!.profilePicture!;
      
      // If not a full URL, assume it's a Supabase storage file path and get public URL
      if (!profileUrl.startsWith('http')) {
        try {
          final supabase = Supabase.instance.client;
          // Remove leading slash if present
          final cleanPath = profileUrl.replaceFirst(RegExp(r'^/'), '');
          profileUrl = supabase.storage
              .from('materials')
              .getPublicUrl(cleanPath);
          debugPrint('🖼️ Normalized teacher profile URL from path: $profileUrl');
        } catch (e) {
          debugPrint('⚠️ Error normalizing teacher profile URL: $e');
          // Fallback: try constructing URL from baseUrl if available
          String cleanBaseUrl = baseUrl.replaceAll(RegExp(r'/api/?$'), '');
          final profilePath = _teacher!.profilePicture!.replaceFirst(
            RegExp(r'^/'),
            '',
          );
          profileUrl = '$cleanBaseUrl/$profilePath';
        }
      }
      
      // Add cache buster for network images to force refresh
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      if (profileUrl.contains('?')) {
        // Replace existing query params with new timestamp
        profileUrl = profileUrl.split('?').first + '?t=$timestamp';
      } else {
        profileUrl += '?t=$timestamp';
      }
      
      debugPrint('🖼️ Final teacher profile URL: $profileUrl');

      return FadeInImage.assetNetwork(
        placeholder: 'assets/placeholder/avatar_placeholder.jpg',
        image: profileUrl,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 100),
        fadeInCurve: Curves.fastEaseInToSlowEaseOut,
        imageErrorBuilder:
            (context, error, stackTrace) => _buildInitialsAvatar(),
      );
    } else {
      return Image.asset(
        'assets/placeholder/avatar_placeholder.jpg',
        fit: BoxFit.cover,
      );
    }
  }

  Widget _buildInitialsAvatar() {
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        _teacher?.name.isNotEmpty == true
            ? _teacher!.name.substring(0, 1).toUpperCase()
            : 'T',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Teacher Profile",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.9),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: FutureBuilder<Teacher>(
        future: _teacherFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerLoading();
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            );
          }

          if (snapshot.hasData) {
            _teacher = snapshot.data;
          }

          final teacherName = _teacher?.name ?? "Teacher";
          final teacherPosition = _teacher?.position ?? "";
          final teacherEmail = _teacher?.email ?? "";

          return _buildTeacherProfileContent(
            context,
            teacherName,
            teacherPosition,
            teacherEmail,
          );
        },
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Stack(
      children: [
        Image.asset(
          'assets/background/stamaria_mobile_bg.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        Container(
          color: Colors.black.withOpacity(
            0.4,
          ), // Darker overlay for better contrast
          width: double.infinity,
          height: double.infinity,
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context).size.height -
                    (MediaQuery.of(context).padding.top + kToolbarHeight),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Shimmer.fromColors(
                    baseColor: Colors.grey.shade400,
                    highlightColor: Colors.grey.shade200,
                    child: _glassCard(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 16,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 140,
                            height: 140,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            width: 200,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 150,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Shimmer.fromColors(
                    baseColor: Colors.grey.shade400,
                    highlightColor: Colors.grey.shade200,
                    child: _glassCard(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Container(
                              width: double.infinity,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          Divider(
                            height: 0,
                            indent: 16,
                            endIndent: 16,
                            color: Colors.white70,
                          ),
                          ListTile(
                            leading: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Container(
                              width: 180,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Shimmer.fromColors(
                    baseColor: Colors.grey.shade400,
                    highlightColor: Colors.grey.shade200,
                    child: Container(
                      width: 200,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeacherProfileContent(
    BuildContext context,
    String teacherName,
    String teacherPosition,
    String teacherEmail,
  ) {
    return Stack(
      children: [
        Image.asset(
          'assets/background/stamaria_mobile_bg.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        Container(
          color: Colors.black.withOpacity(
            0.7,
          ), // Darker overlay for better text contrast
          width: double.infinity,
          height: double.infinity,
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context).size.height -
                    (MediaQuery.of(context).padding.top + kToolbarHeight),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Profile Card
                  _glassCard(
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 20,
                    ),
                    child: Column(
                      children: [
                        _heroAvatarWithEditButton(),
                        const SizedBox(height: 20),
                        Text(
                          teacherName,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.6),
                                blurRadius: 6,
                                offset: const Offset(1, 2),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.work_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              teacherPosition.isNotEmpty
                                  ? teacherPosition
                                  : "Position not set",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.4),
                                    blurRadius: 4,
                                    offset: const Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Info Card
                  _glassCard(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.email_outlined,
                            color: Colors.white.withOpacity(0.9),
                            size: 24,
                          ),
                          title: Text(
                            teacherEmail.isNotEmpty
                                ? teacherEmail
                                : "Email not set",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 3,
                                  offset: const Offset(1, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(
                          height: 0,
                          indent: 16,
                          endIndent: 16,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.white.withOpacity(0.9),
                            size: 24,
                          ),
                          title: Text(
                            _teacher?.createdAt != null
                                ? "Joined: ${DateFormat.yMMMMd().format(_teacher!.createdAt!.toLocal())}"
                                : "Joined date unknown",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 3,
                                  offset: const Offset(1, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EditTeacherProfilePage(),
                        ),
                      );
                      if (result == true && mounted) {
                        // Refresh teacher data
                        setState(() {
                          _teacherFuture = _loadTeacherData();
                        });
                      }
                    },
                    icon: const Icon(Icons.edit, size: 20),
                    label: const Text(
                      "Edit Profile",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      elevation: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroAvatarWithEditButton() {
    return Hero(
      tag: 'teacher-profile-image',
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            CircleAvatar(
              backgroundColor: Colors.transparent,
              radius: 70,
              child:
                  _isUploading
                      ? Lottie.asset(
                        'assets/animation/loading_rainbow.json',
                        width: 90,
                        height: 90,
                        fit: BoxFit.contain,
                      )
                      : ClipOval(
                        child: SizedBox(
                          width: 140,
                          height: 140,
                          child: _getProfileImageWidget(),
                        ),
                      ),
            ),
            Positioned(
              bottom: 0,
              right: 4,
              child: GestureDetector(
                onTap: () async {
                  if (_teacher?.userId != null) {
                    await _showUploadConfirmationDialog();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUploadConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 25,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title with icon
                Icon(
                  Icons.photo_camera_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  "Upload New Profile Picture",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "Would you like to upload a new profile picture?",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                // Buttons with icons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        icon: Icon(
                          Icons.cancel_rounded,
                          size: 20,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.8),
                        ),
                        label: Text(
                          "Cancel",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        icon: Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        label: Text(
                          "Yes",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _pickAndUploadImage(
        role: 'teacher',
        userId: _teacher!.userId.toString(),
      );
    }
  }
}

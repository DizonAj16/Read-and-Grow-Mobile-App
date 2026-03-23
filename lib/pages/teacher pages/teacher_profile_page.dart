import 'dart:io';
import 'dart:ui';
import 'package:deped_reading_app_laravel/api/supabase_auth_service.dart';
import 'package:deped_reading_app_laravel/api/user_service.dart';
import 'package:deped_reading_app_laravel/utils/file_validator.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/teacher_model.dart';
import 'edit_teacher_profile_page.dart';

class TeacherProfilePage extends StatefulWidget {
  const TeacherProfilePage({super.key});

  @override
  State<TeacherProfilePage> createState() => _TeacherProfilePageState();
}

class _TeacherProfilePageState extends State<TeacherProfilePage> {
  Teacher?         _teacher;
  XFile?           _pickedImageFile;
  Uint8List?       _webImageBytes; // holds picked image bytes for web preview & upload
  late Future<Teacher> _teacherFuture;
  bool             _isUploading = false;

  // Fallback base URL for non-Supabase paths (mobile dev only)

  // ── Lifecycle ──────────────────────────────

  @override
  void initState() {
    super.initState();
    _teacherFuture = _loadTeacherData();
  }

  // ── Data loading ───────────────────────────

  /// Fetches the teacher profile from Supabase; falls back to prefs on failure.
  /// Enforces a minimum 2-second loading time for UX consistency.
  Future<Teacher> _loadTeacherData() async {
    final startTime = DateTime.now();

    try {
      // ✅ Call SupabaseAuthService instead of AuthService
      final profileResponse = await SupabaseAuthService.getAuthProfile();

      // ✅ Cast maps safely
      final Map<String, dynamic> userData    = (profileResponse?['user']    as Map?)?.cast<String, dynamic>() ?? {};
      final Map<String, dynamic> profileData = (profileResponse?['profile'] as Map?)?.cast<String, dynamic>() ?? {};

      // ✅ Merge into one JSON for Teacher model
      final teacherJson = {
        ...userData,
        ...profileData,
        'id':         userData['id'],    // Supabase user id
        'teacher_id': profileData['id'], // teacher table id
      };

      final teacher = Teacher.fromJson(teacherJson);
      await teacher.saveToPrefs();

      if (mounted) setState(() => _teacher = teacher);

      // ✅ Ensure minimum 2 second loading
      await _waitForMinDuration(startTime, const Duration(seconds: 2));
      return teacher;

    } catch (e) {
      debugPrint("⚠️ API failed, loading from prefs instead: $e");

      try {
        final teacher = await Teacher.fromPrefs();
        if (mounted) setState(() => _teacher = teacher);

        await _waitForMinDuration(startTime, const Duration(seconds: 2));
        return teacher;

      } catch (prefsError) {
        debugPrint("❌ Failed to load teacher from prefs: $prefsError");
        await _waitForMinDuration(startTime, const Duration(seconds: 2));
        return Future.error("Unable to load teacher data.");
      }
    }
  }

  /// Waits until [minDuration] has elapsed since [startTime].
  Future<void> _waitForMinDuration(DateTime startTime, Duration minDuration) async {
    final elapsed   = DateTime.now().difference(startTime);
    final remaining = minDuration - elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);
  }

  // ── Image picking & uploading ──────────────

  /// Opens the gallery, validates size, shows a preview dialog, then uploads.
  /// Uses bytes on web (no file system access) and file path on mobile.
  Future<void> _pickAndUploadImage({
    required String role,
    required String userId,
  }) async {
    try {
      final picker     = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      // Read bytes — works on both web and mobile
      final bytes = await pickedFile.readAsBytes();

      // Validate file size using bytes (works on both web and mobile)
      if (bytes.lengthInBytes > FileValidator.defaultMaxSizeMB * 1024 * 1024) {
        if (mounted) {
          _showSnackBar(
            'File too large. Max size is ${FileValidator.defaultMaxSizeMB}MB.',
            color: Colors.red.shade800,
          );
        }
        return;
      }

      setState(() {
        _pickedImageFile = pickedFile;
        _webImageBytes   = bytes;
      });

      // Show preview and ask for confirmation
      final confirmed = await _showImagePreviewDialog(pickedFile, bytes);

      if (confirmed != true) {
        _clearPickedImage();
        return;
      }

      setState(() => _isUploading = true);

      // ✅ Upload using bytes (works on both web and mobile)
      final uploadedUrl = await UserService.uploadProfilePicture(
        userId:    userId,
        role:      role,
        filePath:  kIsWeb ? pickedFile.name : pickedFile.path,
        fileBytes: kIsWeb ? bytes : null, // pass bytes for web
      );

      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        // Reload teacher data to reflect new profile picture
        _clearPickedImage();
        final updatedTeacher = await _loadTeacherData();

        if (mounted) {
          setState(() {
            _teacher        = updatedTeacher;
            _teacherFuture  = Future.value(updatedTeacher);
          });
          _showSnackBar(
            'Profile picture updated successfully!',
            color: Colors.green.shade800,
          );
        }
      } else {
        _clearPickedImage();
        if (mounted) {
          _showSnackBar(
            'Failed to upload image. Please try again.',
            color: Colors.red.shade800,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error uploading profile picture: $e');
      _clearPickedImage();
      if (mounted) {
        _showSnackBar(
          'Error: ${e.toString().split(':').last}',
          color: Colors.orange.shade800,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// Clears the locally picked image state.
  void _clearPickedImage() {
    if (mounted) {
      setState(() {
        _pickedImageFile = null;
        _webImageBytes   = null;
        _isUploading     = false;
      });
    }
  }

  // ── Dialogs ────────────────────────────────

  /// Shows a preview of the picked image and returns true if the user confirms upload.
  Future<bool?> _showImagePreviewDialog(XFile pickedFile, Uint8List bytes) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:    const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:        Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withOpacity(0.25),
                blurRadius: 25,
                offset:     const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_camera_rounded,
                      color: Theme.of(context).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text("Confirm Upload",
                      style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),

              const SizedBox(height: 20),

              // Image preview circle
              Container(
                width:  120,
                height: 120,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  // ✅ Use Image.memory on web, Image.file on mobile
                  child: kIsWeb
                      ? Image.memory(bytes, fit: BoxFit.cover)
                      : Image.file(File(pickedFile.path), fit: BoxFit.cover),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                "Use this image as your profile picture?",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      icon:  const Icon(Icons.cancel_rounded, size: 20),
                      label: const Text("Cancel"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape:   RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon:  const Icon(Icons.cloud_upload_rounded, size: 20),
                      label: const Text("Upload"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape:   RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the "would you like to upload?" confirmation before opening the picker.
  Future<void> _showUploadConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:    const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:        Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withOpacity(0.25),
                blurRadius: 25,
                offset:     const Offset(0, 12),
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
                size:  40,
              ),
              const SizedBox(height: 16),
              Text(
                "Upload New Profile Picture",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color:      Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "Would you like to upload a new profile picture?",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                        size:  20,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                      ),
                      label: Text(
                        "Cancel",
                        style: TextStyle(
                          color:      Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape:   RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
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
                        size:  20,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      label: Text(
                        "Yes",
                        style: TextStyle(
                          color:      Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape:   RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _pickAndUploadImage(
        role:   'teacher',
        userId: _teacher!.userId.toString(),
      );
    }
  }

  // ── Helpers ────────────────────────────────

  /// Shows a floating snackbar with [message] and [color].
  void _showSnackBar(String message, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:          Text(message),
        backgroundColor:  color,
        behavior:         SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Widgets ────────────────────────────────

  /// Glassmorphism card used throughout the profile page.
  Widget _glassCard({
    required Widget child,
    double     blur    = 0.5,
    double     opacity = 0.25, // Increased opacity for better readability
    EdgeInsets? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.3), // Brighter border
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withOpacity(0.15), // Darker shadow
                blurRadius: 20,
                offset:     const Offset(0, 8),
              ),
            ],
          ),
          padding: padding ?? EdgeInsets.zero,
          child:   child,
        ),
      ),
    );
  }

  /// Returns the correct image widget based on platform and current state.
  Widget _getProfileImageWidget() {
    // ✅ Web: use memory bytes for picked image
    if (_webImageBytes != null) {
      return Image.memory(_webImageBytes!, fit: BoxFit.cover);
    }

    // Mobile: use file path for picked image
    if (_pickedImageFile != null && !kIsWeb) {
      return FadeInImage(
        placeholder: const AssetImage('assets/placeholder/avatar_placeholder.jpg'),
        image:       FileImage(File(_pickedImageFile!.path)),
        fit:         BoxFit.cover,
      );
    }

    // Network image from Supabase
    if (_teacher?.profilePicture != null && _teacher!.profilePicture!.isNotEmpty) {
      String profileUrl = _teacher!.profilePicture!;

      // Resolve relative Supabase storage path to full public URL
      if (!profileUrl.startsWith('http')) {
        try {
          final cleanPath = profileUrl.replaceFirst(RegExp(r'^/'), '');
          profileUrl = Supabase.instance.client.storage
              .from('materials')
              .getPublicUrl(cleanPath);
        } catch (e) {
          debugPrint('⚠️ Error normalizing URL: $e');
        }
      }

      // Append cache-buster to force reload after upload
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      profileUrl = profileUrl.contains('?')
          ? '${profileUrl.split('?').first}?t=$timestamp'
          : '$profileUrl?t=$timestamp';

      return FadeInImage.assetNetwork(
        placeholder:       'assets/placeholder/avatar_placeholder.jpg',
        image:             profileUrl,
        fit:               BoxFit.cover,
        imageErrorBuilder: (_, __, ___) => _buildInitialsAvatar(),
      );
    }

    // Default placeholder
    return Image.asset('assets/placeholder/avatar_placeholder.jpg', fit: BoxFit.cover);
  }

  /// Fallback avatar showing the teacher's first initial.
  Widget _buildInitialsAvatar() {
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        _teacher?.name.isNotEmpty == true
            ? _teacher!.name.substring(0, 1).toUpperCase()
            : 'T',
        style: const TextStyle(
          color:      Colors.white,
          fontWeight: FontWeight.bold,
          fontSize:   24,
        ),
      ),
    );
  }

  /// Avatar wrapped in a Hero with an overlaid camera edit button.
  Widget _heroAvatarWithEditButton() {
    return Hero(
      tag: 'teacher-profile-image',
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Avatar — shows Lottie spinner while uploading
            CircleAvatar(
              backgroundColor: Colors.transparent,
              radius: 70,
              child: _isUploading
                  ? Lottie.asset(
                      'assets/animation/loading_rainbow.json',
                      width: 90, height: 90, fit: BoxFit.contain,
                    )
                  : ClipOval(
                      child: SizedBox(
                        width: 140, height: 140,
                        child: _getProfileImageWidget(),
                      ),
                    ),
            ),

            // Camera edit button
            Positioned(
              bottom: 0,
              right:  4,
              child: GestureDetector(
                onTap: () async {
                  if (_teacher?.userId != null) {
                    await _showUploadConfirmationDialog();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:  Theme.of(context).colorScheme.primary,
                    shape:  BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size:  20,
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

  // ── Build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Teacher Profile",
          style: TextStyle(
            color:      Colors.white,
            fontWeight: FontWeight.w600,
            fontSize:   18,
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

          if (snapshot.hasData) _teacher = snapshot.data;

          return _buildTeacherProfileContent(
            context,
            _teacher?.name     ?? "Teacher",
            _teacher?.position ?? "",
            _teacher?.email    ?? "",
          );
        },
      ),
    );
  }

  /// Shimmer skeleton shown while teacher data is loading.
  Widget _buildShimmerLoading() {
    return Stack(
      children: [
        // Background image
        Image.asset(
          'assets/background/stamaria_mobile_bg.jpg',
          fit: BoxFit.cover, width: double.infinity, height: double.infinity,
        ),

        // Darker overlay for better contrast
        Container(
          color: Colors.black.withOpacity(0.4),
          width: double.infinity, height: double.infinity,
        ),

        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    (MediaQuery.of(context).padding.top + kToolbarHeight),
              ),
              child: Column(
                mainAxisAlignment:  MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // Profile card skeleton
                  Shimmer.fromColors(
                    baseColor:      Colors.grey.shade400,
                    highlightColor: Colors.grey.shade200,
                    child: _glassCard(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      child: Column(
                        children: [
                          // Avatar placeholder
                          Container(
                            width: 140, height: 140,
                            decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Name placeholder
                          Container(
                            width: 200, height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Position placeholder
                          Container(
                            width: 150, height: 20,
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

                  // Info card skeleton
                  Shimmer.fromColors(
                    baseColor:      Colors.grey.shade400,
                    highlightColor: Colors.grey.shade200,
                    child: _glassCard(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              width: 24, height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle,
                              ),
                            ),
                            title: Container(
                              width: double.infinity, height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const Divider(height: 0, indent: 16, endIndent: 16, color: Colors.white70),
                          ListTile(
                            leading: Container(
                              width: 24, height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle,
                              ),
                            ),
                            title: Container(
                              width: 180, height: 16,
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

                  // Button skeleton
                  Shimmer.fromColors(
                    baseColor:      Colors.grey.shade400,
                    highlightColor: Colors.grey.shade200,
                    child: Container(
                      width: 200, height: 48,
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

  /// Main profile content shown after data loads.
  Widget _buildTeacherProfileContent(
    BuildContext context,
    String teacherName,
    String teacherPosition,
    String teacherEmail,
  ) {
    return Stack(
      children: [
        // Background image
        Image.asset(
          'assets/background/stamaria_mobile_bg.jpg',
          fit: BoxFit.cover, width: double.infinity, height: double.infinity,
        ),

        // Darker overlay for better text contrast
        Container(
          color: Colors.black.withOpacity(0.7),
          width: double.infinity, height: double.infinity,
        ),

        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    (MediaQuery.of(context).padding.top + kToolbarHeight),
              ),
              child: Column(
                mainAxisAlignment:  MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // Profile Card — avatar, name, position
                  _glassCard(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    child: Column(
                      children: [
                        _heroAvatarWithEditButton(),
                        const SizedBox(height: 20),
                        Text(
                          teacherName,
                          style: TextStyle(
                            fontSize:   24,
                            fontWeight: FontWeight.bold,
                            color:      Colors.white,
                            shadows: [
                              Shadow(
                                color:      Colors.black.withOpacity(0.6),
                                blurRadius: 6,
                                offset:     const Offset(1, 2),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.work_outline, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              teacherPosition.isNotEmpty ? teacherPosition : "Position not set",
                              style: TextStyle(
                                fontSize:   16,
                                color:      Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                    color:      Colors.black.withOpacity(0.4),
                                    blurRadius: 4,
                                    offset:     const Offset(1, 1),
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

                  // Info Card — email and join date
                  _glassCard(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.email_outlined,
                            color: Colors.white.withOpacity(0.9),
                            size:  24,
                          ),
                          title: Text(
                            teacherEmail.isNotEmpty ? teacherEmail : "Email not set",
                            style: TextStyle(
                              color:      Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize:   15,
                              shadows: [
                                Shadow(
                                  color:      Colors.black.withOpacity(0.3),
                                  blurRadius: 3,
                                  offset:     const Offset(1, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(
                          height:    0,
                          indent:    16,
                          endIndent: 16,
                          color:     Colors.white.withOpacity(0.3),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.white.withOpacity(0.9),
                            size:  24,
                          ),
                          title: Text(
                            _teacher?.createdAt != null
                                ? "Joined: ${DateFormat.yMMMMd().format(_teacher!.createdAt!.toLocal())}"
                                : "Joined date unknown",
                            style: TextStyle(
                              color:      Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize:   15,
                              shadows: [
                                Shadow(
                                  color:      Colors.black.withOpacity(0.3),
                                  blurRadius: 3,
                                  offset:     const Offset(1, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Edit Profile button
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditTeacherProfilePage(),
                        ),
                      );
                      // Refresh teacher data if edits were saved
                      if (result == true && mounted) {
                        setState(() => _teacherFuture = _loadTeacherData());
                      }
                    },
                    icon:  const Icon(Icons.edit, size: 20),
                    label: const Text(
                      "Edit Profile",
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding:   const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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
}
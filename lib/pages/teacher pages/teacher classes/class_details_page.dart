import 'dart:convert';
import 'dart:io';
import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/classroom%20tabs/essay_grading_tab.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/classroom%20tabs/students_management_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/classroom%20tabs/materials_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/classroom%20tabs/tasks_page.dart';
// Import the 3 pages you want to move inside classroom
import 'package:deped_reading_app_laravel/pages/teacher%20pages/reading_recordings_grading_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/view_graded_recordings_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher_reading_materials_page.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'classroom tabs/class_info.dart';
import 'classroom tabs/class_analytics_page.dart';
import 'classroom tabs/student_reading_progress_page.dart'; // Import the new progress page

class ClassDetailsPage extends StatefulWidget {
  final Map<String, dynamic> classDetails;

  const ClassDetailsPage({super.key, required this.classDetails});

  @override
  State<ClassDetailsPage> createState() => _ClassDetailsPageState();
}

class _ClassDetailsPageState extends State<ClassDetailsPage> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  bool _isUploading = false;
  String? _previewBackground;

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<String> _getBackgroundUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String baseUrl = prefs.getString('base_url') ?? 'http://10.0.2.2:8000/api';

    if (baseUrl.endsWith('/api')) {
      baseUrl = baseUrl.replaceAll('/api', '');
    }

    final classId = widget.classDetails['id'].toString();
    final storedBg = prefs.getString("class_background_$classId");
    final bgImage = storedBg ?? widget.classDetails['background_image'];

    if (bgImage != null && bgImage.isNotEmpty) {
      if (bgImage.startsWith('http')) {
        return bgImage;
      }
      return '$baseUrl/storage/class_backgrounds/$bgImage';
    }
    return '';
  }

  Future<void> _pickAndUploadBackground() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).colorScheme.surface,
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
                Icon(
                  Icons.image_rounded,
                  color: Theme.of(dialogContext).colorScheme.primary,
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  "Upload New Background",
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "Would you like to upload a new class background image?",
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      dialogContext,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
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
                            dialogContext,
                          ).colorScheme.onSurface.withOpacity(0.8),
                        ),
                        label: Text(
                          "Cancel",
                          style: TextStyle(
                            color:
                                Theme.of(dialogContext).colorScheme.onSurface,
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
                              dialogContext,
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
                          color: Theme.of(dialogContext).colorScheme.onPrimary,
                        ),
                        label: Text(
                          "Yes",
                          style: TextStyle(
                            color:
                                Theme.of(dialogContext).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(dialogContext).colorScheme.primary,
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

    if (confirmed != true) {
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _previewBackground = pickedFile.path);

    final confirmUpdate = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_rounded,
                        color: Theme.of(ctx).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Preview Image",
                        style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.primary.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(pickedFile.path),
                        fit: BoxFit.cover,
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: 220,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Do you want to set this as the new class background?",
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: Icon(
                            Icons.cancel_rounded,
                            size: 20,
                            color: Theme.of(
                              ctx,
                            ).colorScheme.onSurface.withOpacity(0.8),
                          ),
                          label: Text(
                            "Cancel",
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.onSurface,
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
                                ctx,
                              ).colorScheme.outline.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: Theme.of(ctx).colorScheme.onPrimary,
                          ),
                          label: Text(
                            "Update",
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(ctx).colorScheme.primary,
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
          ),
    );

    if (confirmUpdate != true) {
      setState(() => _previewBackground = null);
      return;
    }

    setState(() => _isUploading = true);

    try {
      final response = await ClassroomService.uploadClassBackground(
        classId: (widget.classDetails['id'].toString()),
        filePath: pickedFile.path,
      );

      if (response != null && response.statusCode == 200) {
        final responseBody = response.body;
        final data = jsonDecode(responseBody);
        final newBackgroundUrl = data['background_image'] as String?;

        if (newBackgroundUrl != null && newBackgroundUrl.isNotEmpty) {
          setState(() {
            _previewBackground = null;
          });

          final prefs = await SharedPreferences.getInstance();
          final classId = widget.classDetails['id'].toString();
          await prefs.setString("class_background_$classId", newBackgroundUrl);

          if (mounted) {
            setState(() {});
          }

          await Future.delayed(const Duration(seconds: 2));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Background image updated!",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green[700],
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 8,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Failed to upload background. Please try again.",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.redAccent.shade400,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Something went wrong: $e",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 8,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final classId =
        widget.classDetails['id'] ?? widget.classDetails['class_name'];
    final className = widget.classDetails['class_name'] ?? 'Class';

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder:
            (context, _) => [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                floating: false,
                elevation: 0,
                backgroundColor: colorScheme.primary,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  titlePadding: const EdgeInsets.only(bottom: 12),
                  title: Hero(
                    tag: 'class-title-$classId',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        className,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: Colors.white,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                  background: FutureBuilder<String>(
                    future: _getBackgroundUrl(),
                    builder: (context, snapshot) {
                      final bgUrl = snapshot.data ?? '';

                      ImageProvider backgroundProvider;
                      if (_previewBackground != null) {
                        backgroundProvider = FileImage(
                          File(_previewBackground!),
                        );
                      } else if (bgUrl.isNotEmpty) {
                        backgroundProvider = NetworkImage(bgUrl);
                      } else {
                        backgroundProvider = const AssetImage(
                          'assets/background/classroombg.jpg',
                        );
                      }

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Hero(
                            tag: 'class-bg-${widget.classDetails['id']}',
                            child: Image(
                              image: backgroundProvider,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) => Image.asset(
                                    'assets/background/classroombg.jpg',
                                    fit: BoxFit.cover,
                                  ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.6),
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.4),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          if (_isUploading)
                            Positioned.fill(
                              child: Container(
                                color: Colors.white,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 120,
                                        height: 120,
                                        child: Image.asset(
                                          'assets/animation/upload.gif',
                                          width: 100,
                                          height: 100,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        "Uploading background image...",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 8,
                            left: 8,
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: _pickAndUploadBackground,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          children: [
            ClassInfoPage(classDetails: widget.classDetails),
            StudentsManagementPage(
              classId: widget.classDetails['id'].toString(),
            ),
            MaterialsPage(classId: widget.classDetails['id'].toString()),
            TasksPage(classId: widget.classDetails['id'].toString()),
            // // Add the 3 new pages here - pass classId to filter content by classroom
            // ReadingRecordingsGradingPage(
            //   classId: widget.classDetails['id'].toString(),
            // ),
            // ViewGradedRecordingsPage(
            //   classId: widget.classDetails['id'].toString(),
            // ),
            TeacherReadingMaterialsPage(
              classId: widget.classDetails['id'].toString(),
            ),
            // Add the new reading progress page
            StudentReadingProgressPage(
              classId: widget.classDetails['id'].toString(),
            ),
            // In ClassDetailsPage, update the ClassAnalyticsPage constructor call:
            // In the ClassAnalyticsPage constructor call:
            ClassAnalyticsPage(
              classId: widget.classDetails['id'].toString(),
              teacherId:
                  widget.classDetails['teacher_id'].toString(), // If available
            ),
            EssayGradingTabPage(classId: widget.classDetails['id'].toString()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(colorScheme),
    );
  }

  // Custom bottom navigation bar to handle more than 5 items
  Widget _buildBottomNavigationBar(ColorScheme colorScheme) {
    // Create a list of all tab items
    final tabItems = [
      _buildTabItem(Icons.info_outline, Icons.info, "Info"),
      _buildTabItem(Icons.people_outline, Icons.people, "Students"),
      _buildTabItem(Icons.assignment_outlined, Icons.assignment, "Materials"),
      _buildTabItem(Icons.task_outlined, Icons.task, "Tasks"),
      // _buildTabItem(Icons.mic_outlined, Icons.mic, "Grade"),
      // _buildTabItem(Icons.check_circle_outline, Icons.check_circle, "Graded"),
      _buildTabItem(
        Icons.library_books_outlined,
        Icons.library_books,
        "Reading",
      ),
      _buildTabItem(
        Icons.trending_up_outlined,
        Icons.trending_up,
        "Progress",
      ), // New progress tab
      _buildTabItem(Icons.analytics_outlined, Icons.analytics, "Analytics"),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70, // Slightly taller for scrolling
          child: Row(
            children: [
              // Left scroll button
              if (_currentIndex > 0)
                IconButton(
                  icon: Icon(Icons.chevron_left, color: colorScheme.primary),
                  onPressed: () {
                    if (_currentIndex > 0) {
                      _onTabTapped(_currentIndex - 1);
                    }
                  },
                ),

              // Main tab area
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabItems.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _currentIndex;
                    return GestureDetector(
                      onTap: () => _onTabTapped(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected
                                  ? tabItems[index].activeIcon
                                  : tabItems[index].icon,
                              color:
                                  isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface.withOpacity(0.6),
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tabItems[index].label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                color:
                                    isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurface.withOpacity(
                                          0.6,
                                        ),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Right scroll button
              if (_currentIndex < tabItems.length - 1)
                IconButton(
                  icon: Icon(Icons.chevron_right, color: colorScheme.primary),
                  onPressed: () {
                    if (_currentIndex < tabItems.length - 1) {
                      _onTabTapped(_currentIndex + 1);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  _TabItem _buildTabItem(IconData icon, IconData activeIcon, String label) {
    return _TabItem(icon: icon, activeIcon: activeIcon, label: label);
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  _TabItem({required this.icon, required this.activeIcon, required this.label});
}

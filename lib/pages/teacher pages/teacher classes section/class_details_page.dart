import 'dart:convert';
import 'dart:io';
import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/classroom%20tabs/essay_grading_tab.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/classroom%20tabs/materials_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/classroom%20tabs/students_management_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/classroom%20tabs/tasks_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher_reading_materials_page.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'classroom tabs/class_analytics_page.dart';
import 'classroom tabs/class_info.dart';
import 'classroom tabs/student_reading_progress_page.dart'; // Import the new progress page

class ClassDetailsPage extends StatefulWidget {
  final Map<String, dynamic> classDetails;

  const ClassDetailsPage({super.key, required this.classDetails});

  @override
  State<ClassDetailsPage> createState() => _ClassDetailsPageState();
}

class _ClassDetailsPageState extends State<ClassDetailsPage> {
  int              _currentIndex     = 0;
  bool             _isUploading      = false;
  String?          _previewBackground;
  final PageController _pageController = PageController();

  // ── Tab definitions ────────────────────────

  /// All tabs shown in the scrollable bottom navigation bar.
  late final _tabItems = [
    _TabItem(icon: Icons.info_outline,          activeIcon: Icons.info,          label: 'Info'),
    _TabItem(icon: Icons.people_outline,         activeIcon: Icons.people,         label: 'Students'),
    _TabItem(icon: Icons.assignment_outlined,    activeIcon: Icons.assignment,    label: 'Materials'),
    _TabItem(icon: Icons.task_outlined,          activeIcon: Icons.task,          label: 'Tasks'),
    // _TabItem(icon: Icons.mic_outlined,        activeIcon: Icons.mic,           label: 'Grade'),
    // _TabItem(icon: Icons.check_circle_outline,activeIcon: Icons.check_circle,  label: 'Graded'),
    _TabItem(icon: Icons.library_books_outlined, activeIcon: Icons.library_books, label: 'Reading'),
    _TabItem(icon: Icons.trending_up_outlined,   activeIcon: Icons.trending_up,   label: 'Progress'), // New progress tab
    _TabItem(icon: Icons.analytics_outlined,     activeIcon: Icons.analytics,     label: 'Analytics'),
    _TabItem(icon: Icons.edit_note_outlined,     activeIcon: Icons.edit_note,     label: 'Essays'),
  ];

  // ── Navigation ─────────────────────────────

  /// Switches to [index] tab and animates the PageView.
  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve:    Curves.easeInOut,
    );
  }

  // ── Background image ───────────────────────

  /// Resolves the class background URL from prefs or classDetails,
  /// falling back to an empty string if none is set.
  Future<String> _getBackgroundUrl() async {
    final prefs   = await SharedPreferences.getInstance();
    String baseUrl = prefs.getString('base_url') ?? 'http://10.0.2.2:8000/api';

    // Strip /api suffix for storage URL construction
    if (baseUrl.endsWith('/api')) {
      baseUrl = baseUrl.replaceAll('/api', '');
    }

    final classId  = widget.classDetails['id'].toString();
    final storedBg = prefs.getString('class_background_$classId');
    final bgImage  = storedBg ?? widget.classDetails['background_image'];

    if (bgImage != null && bgImage.isNotEmpty) {
      // Already a full URL — return as-is
      if (bgImage.startsWith('http')) return bgImage;
      return '$baseUrl/storage/class_backgrounds/$bgImage';
    }

    return '';
  }

  /// Guides the user through a two-step flow: confirm intent → pick image →
  /// preview → upload. Rolls back preview state on cancel or failure.
  Future<void> _pickAndUploadBackground() async {
    // Step 1: Ask if they want to upload a new background
    final confirmed = await _showUploadIntentDialog();
    if (confirmed != true) return;

    // Step 2: Pick image from gallery
    final picker     = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _previewBackground = pickedFile.path);

    // Step 3: Show preview and ask for final confirmation
    final confirmUpdate = await _showImagePreviewDialog(pickedFile.path);
    if (confirmUpdate != true) {
      setState(() => _previewBackground = null);
      return;
    }

    // Step 4: Upload
    setState(() => _isUploading = true);

    try {
      final response = await ClassroomService.uploadClassBackground(
        classId:  widget.classDetails['id'].toString(),
        filePath: pickedFile.path,
      );

      if (response != null && response.statusCode == 200) {
        final data             = jsonDecode(response.body);
        final newBackgroundUrl = data['background_image'] as String?;

        if (newBackgroundUrl != null && newBackgroundUrl.isNotEmpty) {
          setState(() => _previewBackground = null);

          // Persist new background URL locally
          final prefs   = await SharedPreferences.getInstance();
          final classId = widget.classDetails['id'].toString();
          await prefs.setString('class_background_$classId', newBackgroundUrl);

          if (mounted) setState(() {});

          await Future.delayed(const Duration(seconds: 2));
          if (mounted) _showSnackBar('Background image updated!', color: Colors.green[700]!);
        }
      } else {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          _showSnackBar(
            'Failed to upload background. Please try again.',
            color: Colors.redAccent.shade400,
          );
        }
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _showSnackBar('Something went wrong: $e', color: Colors.orange.shade700);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Dialogs ────────────────────────────────

  /// Shows the initial "would you like to upload?" confirmation dialog.
  Future<bool?> _showUploadIntentDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:    const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:        Theme.of(dialogContext).colorScheme.surface,
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
              Icon(
                Icons.image_rounded,
                color: Theme.of(dialogContext).colorScheme.primary,
                size:  40,
              ),
              const SizedBox(height: 16),
              Text(
                'Upload New Background',
                style: Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                  color:      Theme.of(dialogContext).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Would you like to upload a new class background image?',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 24),
              _buildDialogButtons(
                dialogContext: dialogContext,
                confirmLabel:  'Yes',
                confirmIcon:   Icons.check_circle_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the image preview dialog with a confirm/cancel option.
  Future<bool?> _showImagePreviewDialog(String imagePath) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:    const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:        Theme.of(ctx).colorScheme.surface,
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
                  Icon(Icons.image_rounded,
                      color: Theme.of(ctx).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Preview Image',
                    style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Image preview
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(ctx).colorScheme.primary.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:      Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset:     const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(imagePath),
                    fit:    BoxFit.cover,
                    width:  MediaQuery.of(context).size.width * 0.7,
                    height: 220,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Do you want to set this as the new class background?',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color:      Theme.of(ctx).colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w400,
                  fontSize:   14,
                ),
              ),

              const SizedBox(height: 24),

              _buildDialogButtons(
                dialogContext: ctx,
                confirmLabel:  'Update',
                confirmIcon:   Icons.check_circle_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Reusable Cancel / Confirm button row used in both dialogs.
  Widget _buildDialogButtons({
    required BuildContext dialogContext,
    required String       confirmLabel,
    required IconData     confirmIcon,
  }) {
    final cs = Theme.of(dialogContext).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, false),
            icon: Icon(Icons.cancel_rounded, size: 20, color: cs.onSurface.withOpacity(0.8)),
            label: Text(
              'Cancel',
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side:    BorderSide(color: cs.outline.withOpacity(0.5)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(confirmIcon, size: 20, color: cs.onPrimary),
            label: Text(
              confirmLabel,
              style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              padding:         const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation:       3,
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────

  /// Shows a floating snackbar with an icon, [message], and [color].
  void _showSnackBar(String message, {required Color color, IconData icon = Icons.info}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: color,
        behavior:        SnackBarBehavior.floating,
        margin:          const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation:       8,
        duration:        const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final classId     = widget.classDetails['id'] ?? widget.classDetails['class_name'];
    final className   = widget.classDetails['class_name'] ?? 'Class';

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight:          200,
            pinned:                  true,
            floating:                false,
            elevation:               0,
            backgroundColor:         colorScheme.primary,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle:  true,
              titlePadding: const EdgeInsets.only(bottom: 12),
              title: Hero(
                tag: 'class-title-$classId',
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    className,
                    style: const TextStyle(
                      fontWeight:   FontWeight.bold,
                      fontSize:     22,
                      color:        Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              background: FutureBuilder<String>(
                future: _getBackgroundUrl(),
                builder: (context, snapshot) {
                  final bgUrl = snapshot.data ?? '';

                  // Determine which image provider to use
                  final ImageProvider backgroundProvider = _previewBackground != null
                      ? FileImage(File(_previewBackground!))
                      : bgUrl.isNotEmpty
                          ? NetworkImage(bgUrl)
                          : const AssetImage('assets/background/classroombg.jpg');

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background image with Hero transition
                      Hero(
                        tag: 'class-bg-${widget.classDetails['id']}',
                        child: Image(
                          image: backgroundProvider,
                          fit:   BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/background/classroombg.jpg',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),

                      // Gradient overlay for readability
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.6),
                              Colors.transparent,
                              Colors.black.withOpacity(0.4),
                            ],
                            begin: Alignment.topCenter,
                            end:   Alignment.bottomCenter,
                          ),
                        ),
                      ),

                      // Upload progress overlay
                      if (_isUploading)
                        Positioned.fill(
                          child: Container(
                            color: Colors.white,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width:  120,
                                    height: 120,
                                    child: Image.asset(
                                      'assets/animation/upload.gif',
                                      width:  100,
                                      height: 100,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Uploading background image...',
                                    style: TextStyle(
                                      fontSize:   16,
                                      fontWeight: FontWeight.w600,
                                      color:      Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Back button
                      Positioned(
                        top:  MediaQuery.of(context).padding.top + 8,
                        left: 8,
                        child: IconButton(
                          icon:      const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),

                      // Camera / upload button
                      Positioned(
                        top:   MediaQuery.of(context).padding.top + 8,
                        right: 8,
                        child: IconButton(
                          icon:      const Icon(Icons.camera_alt, color: Colors.white, size: 28),
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
          controller:    _pageController,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          children: [
            ClassInfoPage(classDetails: widget.classDetails),
            StudentsManagementPage(classId: widget.classDetails['id'].toString()),
            MaterialsPage(classId: widget.classDetails['id'].toString()),
            TasksPage(classId: widget.classDetails['id'].toString()),
            // // Add the 3 new pages here - pass classId to filter content by classroom
            // ReadingRecordingsGradingPage(classId: widget.classDetails['id'].toString()),
            // ViewGradedRecordingsPage(classId: widget.classDetails['id'].toString()),
            TeacherReadingMaterialsPage(classId: widget.classDetails['id'].toString()),
            // Add the new reading progress page
            StudentReadingProgressPage(classId: widget.classDetails['id'].toString()),
            // In ClassDetailsPage, update the ClassAnalyticsPage constructor call:
            // In the ClassAnalyticsPage constructor call:
            ClassAnalyticsPage(
              classId:   widget.classDetails['id'].toString(),
              teacherId: widget.classDetails['teacher_id'].toString(), // If available
            ),
            EssayGradingTabPage(classId: widget.classDetails['id'].toString()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(colorScheme),
    );
  }

  /// Custom scrollable bottom navigation bar — supports more than 5 tabs.
  Widget _buildBottomNavigationBar(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color:  colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outline.withOpacity(0.1), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset:     const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70, // Slightly taller for scrolling
          child: Row(
            children: [
              // Left scroll arrow (only shown when not on first tab)
              if (_currentIndex > 0)
                IconButton(
                  icon:      Icon(Icons.chevron_left, color: colorScheme.primary),
                  onPressed: () => _onTabTapped(_currentIndex - 1),
                ),

              // Horizontally scrollable tab list
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount:       _tabItems.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _currentIndex;
                    final item       = _tabItems[index];

                    return GestureDetector(
                      onTap: () => _onTabTapped(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin:  const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisSize:      MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface.withOpacity(0.6),
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize:   11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color:      isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withOpacity(0.6),
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

              // Right scroll arrow (only shown when not on last tab)
              if (_currentIndex < _tabItems.length - 1)
                IconButton(
                  icon:      Icon(Icons.chevron_right, color: colorScheme.primary),
                  onPressed: () => _onTabTapped(_currentIndex + 1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tab item model
// ─────────────────────────────────────────────

/// Holds the icon, active icon, and label for a single bottom nav tab.
class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String   label;

  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
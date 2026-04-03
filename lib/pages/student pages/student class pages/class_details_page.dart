import 'package:deped_reading_app_laravel/api/reading_materials_service.dart';
import 'package:deped_reading_app_laravel/pages/student%20pages/enhanced_reading_level_page.dart';
import 'package:deped_reading_app_laravel/pages/student%20pages/student%20class%20pages/tabs/materials_page.dart';
import 'package:deped_reading_app_laravel/pages/student%20pages/student%20class%20pages/tabs/student_announcements_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tabs/list_of_quiz_and_lessons.dart';
import 'tabs/student_list_page.dart';
import 'tabs/teacher_info_page.dart';

class ClassDetailsPage extends StatefulWidget {
  final String classId;
  final String className;
  final String backgroundImage;
  final String teacherName;
  final String teacherEmail;
  final String teacherPosition;
  final String? teacherAvatar;

  const ClassDetailsPage({
    super.key,
    required this.classId,
    required this.className,
    required this.backgroundImage,
    required this.teacherName,
    required this.teacherEmail,
    required this.teacherPosition,
    this.teacherAvatar,
  });

  @override
  State<ClassDetailsPage> createState() => _ClassDetailsPageState();
}

class _ClassDetailsPageState extends State<ClassDetailsPage> {
  // Navigation state
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  double _appBarOpacity = 0.0;

  // User data
  final user = Supabase.instance.client.auth.currentUser;

  // Pending tasks state
  int _pendingTasksCount = 0;
  bool _isLoadingPendingCount = true;

  // Pending reading materials state
  int _pendingReadingMaterialsCount = 0;
  bool _isLoadingReadingMaterialsCount = true;

  @override
  void initState() {
    super.initState();
    _initializeScrollListener();
    _loadInitialData();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  /// Initialize scroll listener for app bar opacity
  void _initializeScrollListener() {
    _scrollController.addListener(_handleScroll);
  }

  /// Handle scroll events for app bar opacity
  void _handleScroll() {
    final double offset = _scrollController.offset;
    if (mounted) {
      setState(() {
        _appBarOpacity = (offset / 100).clamp(0.0, 1.0);
      });
    }
  }

  /// Load all initial data
  void _loadInitialData() {
    _loadPendingTasksCount();
    _loadPendingReadingMaterialsCount();
  }

  /// Handle tab tap with refresh for specific tabs
  void _onTabTapped(int index) {
    // Refresh pending counts when tapping on respective tabs
    if (index == 1) {
      _loadPendingTasksCount();
    } else if (index == 2) {
      _loadPendingReadingMaterialsCount();
    }

    if (mounted) {
      setState(() {
        _currentIndex = index;
      });
    }

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Dispose all controllers
  void _disposeControllers() {
    _scrollController.dispose();
    _pageController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarColor = _getAvatarColor(widget.className);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: NestedScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              _buildSliverAppBar(
                context,
                theme,
                avatarColor,
                innerBoxIsScrolled,
              ),
            ],
        body: _buildPageView(),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(theme),
    );
  }

  /// Build sliver app bar
  SliverAppBar _buildSliverAppBar(
    BuildContext context,
    ThemeData theme,
    Color avatarColor,
    bool innerBoxIsScrolled,
  ) {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: theme.colorScheme.primary.withOpacity(_appBarOpacity),
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        centerTitle: true,
        title: _buildAppBarTitle(innerBoxIsScrolled),
        background: _buildAppBarBackground(avatarColor),
      ),
    );
  }

  /// Build app bar title
  Hero _buildAppBarTitle(bool innerBoxIsScrolled) {
    return Hero(
      tag: 'class-title-${widget.className}',
      child: Material(
        color: Colors.transparent,
        child: AnimatedOpacity(
          opacity: innerBoxIsScrolled ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Text(
            widget.className,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              shadows: [
                Shadow(
                  color: Colors.black45,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build app bar background
  Stack _buildAppBarBackground(Color avatarColor) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackgroundImage(avatarColor),
        _buildBackgroundGradient(),
        _buildClassNameOverlay(),
      ],
    );
  }

  /// Build background image with hero animation
  Hero _buildBackgroundImage(Color avatarColor) {
    return Hero(
      tag: 'class-bg-${widget.className}',
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.black.withOpacity(0.3),
          BlendMode.darken,
        ),
        child:
            widget.backgroundImage.startsWith('http')
                ? _buildNetworkImage(avatarColor)
                : _buildAssetImage(avatarColor),
      ),
    );
  }

  /// Build network image with loading and error handling
  Widget _buildNetworkImage(Color avatarColor) {
    return Image.network(
      widget.backgroundImage,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildLoadingPlaceholder(avatarColor, loadingProgress);
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorPlaceholder(avatarColor);
      },
    );
  }

  /// Build asset image with error handling
  Widget _buildAssetImage(Color avatarColor) {
    return Image.asset(
      widget.backgroundImage,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildErrorPlaceholder(avatarColor),
    );
  }

  /// Build loading placeholder
  Widget _buildLoadingPlaceholder(
    Color avatarColor,
    ImageChunkEvent? progress,
  ) {
    return Container(
      color: avatarColor.withOpacity(0.2),
      child: Center(
        child: CircularProgressIndicator(
          value:
              progress?.expectedTotalBytes != null
                  ? progress!.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Build error placeholder
  Widget _buildErrorPlaceholder(Color avatarColor) {
    return Container(
      color: avatarColor.withOpacity(0.2),
      child: const Center(
        child: Icon(Icons.image_not_supported, color: Colors.white54, size: 48),
      ),
    );
  }

  /// Build background gradient overlay
  Container _buildBackgroundGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.5),
            Colors.transparent,
            Colors.black.withOpacity(0.3),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
    );
  }

  /// Build class name overlay
  Positioned _buildClassNameOverlay() {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Text(
            widget.className,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: Colors.black45,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build page view with all tabs
  PageView _buildPageView() {
    return PageView(
      controller: _pageController,
      onPageChanged: (index) {
        if (mounted) {
          setState(() {
            _currentIndex = index;
          });
        }
      },
      children: [
        StudentAnnouncementsScreen(
          classId: widget.classId,
          className: widget.className,
        ),
        ClassContentScreen(classRoomId: widget.classId),
        EnhancedReadingLevelPage(classId: widget.classId),
        MaterialsPage(classId: widget.classId),
        StudentListPage(classId: widget.classId),
        TeacherInfoPage(classId: widget.classId),
      ],
    );
  }

  /// Build bottom navigation bar
  Container _buildBottomNavigationBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: theme.scaffoldBackgroundColor,
          selectedItemColor: theme.colorScheme.primary,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          elevation: 10,
          type: BottomNavigationBarType.fixed,
          items: _buildBottomNavigationItems(theme),
        ),
      ),
    );
  }

  /// Build bottom navigation items
  List<BottomNavigationBarItem> _buildBottomNavigationItems(ThemeData theme) {
    return [
      _buildBottomNavItem(
        0,
        Icons.announcement_outlined,
        "Announcements",
        theme,
      ),
      _buildBottomNavItem(1, Icons.task_outlined, "Tasks", theme),
      _buildBottomNavItem(2, Icons.library_books_outlined, "Reading", theme),
      _buildBottomNavItem(3, Icons.book_outlined, "Materials", theme),
      _buildBottomNavItem(4, Icons.people_outline, "Classmates", theme),
      _buildBottomNavItem(5, Icons.person_outline, "Teacher", theme),
    ];
  }

  /// Build individual bottom navigation item with badge support
  BottomNavigationBarItem _buildBottomNavItem(
    int index,
    IconData icon,
    String label,
    ThemeData theme,
  ) {
    Widget iconWidget;

    if (index == 1 && _pendingTasksCount > 0) {
      iconWidget = _buildBadgedIcon(
        icon,
        _pendingTasksCount,
        _isLoadingPendingCount,
        Colors.red,
        theme,
      );
    } else if (index == 2 && _pendingReadingMaterialsCount > 0) {
      iconWidget = _buildBadgedIcon(
        icon,
        _pendingReadingMaterialsCount,
        _isLoadingReadingMaterialsCount,
        Colors.orange,
        theme,
      );
    } else {
      iconWidget = Icon(icon);
    }

    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color:
              _currentIndex == index
                  ? theme.colorScheme.primary.withOpacity(0.2)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: iconWidget,
      ),
      label: label,
    );
  }

  /// Build icon with badge count
  Widget _buildBadgedIcon(
    IconData icon,
    int count,
    bool isLoading,
    Color badgeColor,
    ThemeData theme,
  ) {
    return Container(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon),
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              padding:
                  count > 9
                      ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                      : const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              constraints: BoxConstraints(
                minWidth: isLoading ? 16 : 18,
                minHeight: isLoading ? 16 : 18,
              ),
              child:
                  isLoading
                      ? SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get avatar color based on class name
  Color _getAvatarColor(String className) {
    final colors = [
      Colors.pink[300]!,
      Colors.blue[300]!,
      Colors.green[300]!,
      Colors.orange[300]!,
      Colors.purple[300]!,
      Colors.teal[300]!,
    ];
    return colors[className.hashCode % colors.length];
  }

  /// Load pending tasks count
  Future<void> _loadPendingTasksCount() async {
    if (!mounted) return;

    setState(() => _isLoadingPendingCount = true);

    try {
      final count = await _getPendingTasksCount();
      if (mounted) {
        setState(() {
          _pendingTasksCount = count;
          _isLoadingPendingCount = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load pending tasks count: $e');
      if (mounted) {
        setState(() => _isLoadingPendingCount = false);
      }
    }
  }

  /// Get pending tasks count from database
  Future<int> _getPendingTasksCount() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      // Get student.id from students table
      final studentRow =
          await supabase
              .from('students')
              .select('id')
              .eq('id', userId)
              .maybeSingle();

      if (studentRow == null) return 0;
      final String studentId = studentRow['id'] as String;

      // Get all classes the student is enrolled in
      final enrollments = await supabase
          .from('student_enrollments')
          .select('class_room_id')
          .eq('student_id', studentId);

      final classIds =
          (enrollments as List)
              .map((e) => e['class_room_id'] as String)
              .toList();

      // Get all assignments for these classes
      List<String> assignedTaskIds = [];
      List<String> assignedQuizIds = [];
      Set<String> tasksWithQuizzes = {};

      if (classIds.isNotEmpty) {
        final assignments = await supabase
            .from('assignments')
            .select('task_id, quiz_id, tasks(id, quizzes(id))')
            .inFilter('class_room_id', classIds);

        for (var assignment in assignments) {
          final directQuizId = assignment['quiz_id'] as String?;
          if (directQuizId != null && !assignedQuizIds.contains(directQuizId)) {
            assignedQuizIds.add(directQuizId);
          }

          final taskId = assignment['task_id'] as String?;
          if (taskId != null) {
            final task = assignment['tasks'] as Map<String, dynamic>?;
            bool taskHasQuiz = false;

            if (task != null) {
              final quizzes = task['quizzes'] as List?;
              if (quizzes != null && quizzes.isNotEmpty) {
                taskHasQuiz = true;
                tasksWithQuizzes.add(taskId);
                for (var quiz in quizzes) {
                  final quizId = quiz['id'] as String?;
                  if (quizId != null && !assignedQuizIds.contains(quizId)) {
                    assignedQuizIds.add(quizId);
                  }
                }
              }
            }

            if (!taskHasQuiz && !assignedTaskIds.contains(taskId)) {
              assignedTaskIds.add(taskId);
            }
          }
        }
      }

      // Get existing progress records
      final response = await supabase
          .from('student_task_progress')
          .select('task_id, completed')
          .eq('student_id', userId);

      Set<String> completedTaskIds = {};
      Set<String> pendingTaskIds = {};

      for (var row in response) {
        final taskId = row['task_id'] as String?;
        if (taskId == null) continue;

        if (row['completed'] == true) {
          completedTaskIds.add(taskId);
        } else {
          pendingTaskIds.add(taskId);
        }
      }

      // Filter out tasks with quizzes
      Set<String> pendingTasksWithoutQuizzes =
          pendingTaskIds.where((id) => !tasksWithQuizzes.contains(id)).toSet();
      Set<String> completedTasksWithoutQuizzes =
          completedTaskIds
              .where((id) => !tasksWithQuizzes.contains(id))
              .toSet();

      // Count newly assigned tasks (without quizzes)
      int newPendingTasks = 0;
      for (var taskId in assignedTaskIds) {
        if (!completedTasksWithoutQuizzes.contains(taskId) &&
            !pendingTasksWithoutQuizzes.contains(taskId)) {
          newPendingTasks++;
        }
      }

      // Get completed quizzes
      final quizSubmissions = await supabase
          .from('student_submissions')
          .select(
            'assignment_id, assignments(id, task_id, quiz_id, tasks(id, quizzes(id)))',
          )
          .eq('student_id', userId);

      Set<String> completedQuizIds = {};
      for (var submission in quizSubmissions) {
        final assignment = submission['assignments'] as Map<String, dynamic>?;
        if (assignment != null) {
          final directQuizId = assignment['quiz_id'] as String?;
          if (directQuizId != null && directQuizId.isNotEmpty) {
            completedQuizIds.add(directQuizId);
          }

          final task = assignment['tasks'] as Map<String, dynamic>?;
          if (task != null) {
            final quizzes = task['quizzes'] as List?;
            if (quizzes != null) {
              for (var quiz in quizzes) {
                final quizId = quiz['id'] as String?;
                if (quizId != null) {
                  completedQuizIds.add(quizId);
                }
              }
            }
          }
        }
      }

      // Count newly assigned quizzes
      int newPendingQuizzes = 0;
      for (var quizId in assignedQuizIds) {
        if (!completedQuizIds.contains(quizId)) {
          newPendingQuizzes++;
        }
      }

      // Total pending count
      return pendingTasksWithoutQuizzes.length +
          newPendingTasks +
          newPendingQuizzes;
    } catch (e) {
      debugPrint('Error getting pending tasks count: $e');
      return 0;
    }
  }

  /// Load pending reading materials count
  Future<void> _loadPendingReadingMaterialsCount() async {
    if (!mounted) return;

    setState(() => _isLoadingReadingMaterialsCount = true);

    try {
      final count = await _getPendingReadingMaterialsCount();
      if (mounted) {
        setState(() {
          _pendingReadingMaterialsCount = count;
          _isLoadingReadingMaterialsCount = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load pending reading materials count: $e');
      if (mounted) {
        setState(() => _isLoadingReadingMaterialsCount = false);
      }
    }
  }

  /// Get pending reading materials count from database
  Future<int> _getPendingReadingMaterialsCount() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return 0;

      // Get student's current reading level
      final studentRes =
          await supabase
              .from('students')
              .select('id, current_reading_level_id')
              .eq('id', user.id)
              .maybeSingle();

      if (studentRes == null ||
          studentRes['current_reading_level_id'] == null) {
        return 0;
      }

      final studentId = studentRes['id'];
      final levelId = studentRes['current_reading_level_id'];

      // Get reading materials for this level
      final materialsData =
          await ReadingMaterialsService.getReadingMaterialsByLevelForStudent(
            levelId,
            studentId,
            classRoomId: widget.classId,
          );

      // Sort materials by creation date
      materialsData.sort((a, b) {
        final materialA = a['material'] as ReadingMaterial;
        final materialB = b['material'] as ReadingMaterial;
        return materialA.createdAt.compareTo(materialB.createdAt);
      });

      // Filter materials that are accessible (not locked by prerequisites)
      final accessibleMaterials =
          materialsData.where((data) => data['is_accessible'] as bool).toList();

      if (accessibleMaterials.isEmpty) return 0;

      // Get material IDs
      final materialIds =
          accessibleMaterials
              .map((data) => (data['material'] as ReadingMaterial).id)
              .whereType<String>()
              .toList();

      // Get submitted materials
      final submissionsRes = await supabase
          .from('student_recordings')
          .select('material_id')
          .eq('student_id', studentId)
          .inFilter('material_id', materialIds)
          .isFilter('task_id', null);

      Set<String> submittedMaterialIds = {};
      for (final s in submissionsRes) {
        final materialId = s['material_id'] as String?;
        if (materialId != null) {
          submittedMaterialIds.add(materialId);
        }
      }

      // Pending count = total accessible materials - submitted materials
      final pendingCount =
          accessibleMaterials.length - submittedMaterialIds.length;
      return pendingCount > 0 ? pendingCount : 0;
    } catch (e) {
      debugPrint('Error getting pending reading materials count: $e');
      return 0;
    }
  }
}

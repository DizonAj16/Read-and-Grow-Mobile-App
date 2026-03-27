import 'package:deped_reading_app_laravel/api/supabase_auth_service.dart';
import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:deped_reading_app_laravel/api/prefs_service.dart';
import 'package:deped_reading_app_laravel/api/user_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes%20section/class_details_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/pupil_management_page.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20dashboard/create%20student%20and%20classes/create_class_or_student_dialog.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20dashboard/manage%20classes/delete_class_modal.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20dashboard/manage%20classes/edit_class_modal.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20dashboard/students_list/teacher_student_list_modal.dart';
import 'package:deped_reading_app_laravel/widgets/navigation/page_transition.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../../../widgets/ui_states.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'cards/horizontal_card.dart';
import 'cards/class_card.dart';
import '../../../models/student_model.dart';
import '../../../models/teacher_model.dart';
import '../../../models/classroom_model.dart';

/// Teacher Dashboard Page - Main dashboard for teachers to manage classes and students
class TeacherDashboardPage extends StatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  // ===========================================================================
  // STATE VARIABLES
  // ===========================================================================

  // Future variables for async data loading
  Future<List<Student>> _studentsFuture = Future.value([]);
  Future<Teacher> _teacherFuture = Future.value(
    Teacher(id: 0, userId: 0, name: 'Loading...', profilePicture: null),
  );
  Future<int> _classCountFuture = Future.value(0);
  Future<List<Classroom>> _classesFuture = Future.value([]);

  // Constants and configuration
  static const List<int> _pageSizes = [2, 5, 10, 20, 50];
  final int _pageSize = 10;
  List<Student> _allStudents = [];

  // Loading states
  bool _isLoading = true;
  bool _isRefreshing = false;
  DateTime? _loadingStartTime;

  // ===========================================================================
  // LIFECYCLE METHODS
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    // Initial load with minimum 2-second delay for better UX
    Future.wait([
      _loadInitialData(),
      Future.delayed(const Duration(seconds: 2)),
    ]).then((_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  // ===========================================================================
  // DATA LOADING METHODS
  // ===========================================================================

  /// Loads all initial data for the dashboard with minimum loading time
  Future<void> _loadInitialData() async {
    _loadingStartTime = DateTime.now();
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadTeacherData(),
        _loadStudentData(),
        _loadClassData(),
      ]);
    } catch (e) {
      debugPrint("Initial data loading error: $e");
    } finally {
      await _ensureMinimumLoadingTime();
    }
  }

  /// Loads teacher data with fallback mechanism (API → Local Storage)
  Future<void> _loadTeacherData() async {
    try {
      // ✅ Try fetching from Supabase first
      final profileResponse = await SupabaseAuthService.getAuthProfile();

      // Extract both user and profile data safely
      final userData = profileResponse?['user'] ?? {};
      final profileData = profileResponse?['profile'] ?? {};

      // ✅ Merge into Teacher model
      final teacher = Teacher.fromJson({
        ...userData,
        ...profileData,
        'id': userData['id'],      // Preserve user ID
        'teacher_id': profileData['id'], // Preserve teacher ID
      });

      // ✅ Save to prefs for offline use
      await teacher.saveToPrefs();

      if (mounted) {
        setState(() {
          _teacherFuture = Future.value(teacher);
        });
      }
    } catch (e) {
      debugPrint("⚠️ API failed, loading teacher from prefs instead: $e");

      try {
        // ✅ Fallback to prefs
        final teacher = await Teacher.fromPrefs();
        if (mounted) {
          setState(() {
            _teacherFuture = Future.value(teacher);
          });
        }
      } catch (prefsError) {
        debugPrint("❌ Failed to load teacher from prefs: $prefsError");

        if (mounted) {
          setState(() {
            _teacherFuture = Future.error(
              "Unable to load teacher data. Please check connection and try again.",
            );
          });
        }
      }
    }
  }

  /// Loads student data with caching mechanism
  Future<void> _loadStudentData() async {
    _studentsFuture = _loadStudents().then((students) {
      _allStudents = students;
      return students;
    });
    await _studentsFuture;
  }

  /// Loads class data and updates count
  Future<void> _loadClassData() async {
    _classesFuture = _loadClassesAndCount().then((classes) {
      _classCountFuture = Future.value(classes.length);
      return classes;
    });
    await _classesFuture;
  }

  /// Ensures a minimum loading time of 2 seconds for better UX
  Future<void> _ensureMinimumLoadingTime() async {
    if (_loadingStartTime != null) {
      final elapsed = DateTime.now().difference(_loadingStartTime!);
      final remaining = const Duration(seconds: 2) - elapsed;
      if (remaining > Duration.zero) await Future.delayed(remaining);
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  /// Handles pull-to-refresh functionality
  Future<void> _handleRefresh() async {
    if (!mounted) return;

    setState(() {
      _isRefreshing = true;
      _isLoading = true; // Show shimmer immediately
    });

    try {
      await _loadInitialData();
    } catch (e) {
      debugPrint("Refresh error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _isLoading = false;
        });
      }
    }
  }

  /// Loads students from API with local storage fallback
  Future<List<Student>> _loadStudents() async {
    try {
      final apiList = await UserService.fetchAllStudents();
      await PrefsService.storeStudentsToPrefs(apiList);
    } catch (_) {
      debugPrint(
        "Failed to fetch students from API, loading from local storage.",
      );
    }
    return await PrefsService.getStudentsFromPrefs();
  }

  /// Loads classes and stores them in local storage
  Future<List<Classroom>> _loadClassesAndCount() async {
    final classes = await ClassroomService.fetchTeacherClasses();
    await PrefsService.storeTeacherClassesToPrefs(classes);
    return classes;
  }

  // ===========================================================================
  // DATA REFRESH METHODS
  // ===========================================================================

  /// Refreshes student count data
  void _refreshStudentCount() {
    setState(() => _studentsFuture = _loadStudents());
  }

  /// Refreshes class data
  void _refreshClasses() {
    setState(() {
      _classesFuture = _loadClassesAndCount();
      _classCountFuture = _classesFuture.then((list) => list.length);
    });
  }

  // ===========================================================================
  // DIALOG AND MODAL METHODS
  // ===========================================================================

  /// Shows the create class/student dialog
  void _showCreateClassOrStudentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => CreateClassOrStudentDialog(
            onStudentAdded: _refreshStudentCount,
            onClassAdded: _refreshClasses,
          ),
    );
  }

  /// Shows a loading dialog with a Lottie animation and text
  void showLoadingDialog(String lottieAsset, String loadingText) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 75,
                    height: 75,
                    child: Lottie.asset(lottieAsset),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loadingText,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// Shows the student list modal bottom sheet
  Future<void> _showStudentListModal(BuildContext context) async {
    if (_allStudents.isEmpty) {
      await _studentsFuture;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.99, // Increased from 0.85
            minChildSize: 0.6, // Slightly higher minimum
            maxChildSize: 1,
            builder:
                (context, scrollController) => Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TeacherStudentListModal(
                      allStudents: _allStudents,
                      pageSizes: _pageSizes,
                      initialPageSize: _pageSize,
                      onDataChanged: () {
                        setState(() {
                          _studentsFuture = _loadStudents(); // REFRESH DATA
                        });
                      },
                    ),
                  ),
                ),
          ),
    );
  }

  // ===========================================================================
  // CLASS MANAGEMENT METHODS
  // ===========================================================================

  /// Navigates to the class details page for a given class ID
  void _viewClassDetails(BuildContext context, String classId) async {
    try {
      final details = await ClassroomService.getClassDetails(classId);
      if (!context.mounted) return;

      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(PageTransition(page: ClassDetailsPage(classDetails: details)));

      // ✅ Refresh after returning from ClassDetailsPage
      _refreshClasses();
    } catch (e) {
      print("Failed to load class details: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to load class details.")),
      );
    }
  }

  /// Opens a dialog to edit a class's details
  void _editClass(BuildContext context, Classroom classroom) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => EditClassBottomModal(
            classroom: classroom,
            onClassUpdated: _refreshClasses,
          ),
    );
  }

  /// Deletes a class after confirmation
  void _deleteClass(BuildContext context, String classId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DeleteClassBottomModal(
            classId: classId,
            onClassDeleted: _refreshClasses,
          ),
    );
  }

  // ===========================================================================
  // UI BUILDING METHODS
  // ===========================================================================

  /// Builds the shimmer loading effect for initial loading
  Widget _buildShimmerLoading() {
    return Stack(
      children: [
        // Main shimmer content
        Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Shimmer for welcome card
              Container(
                height: 100,
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 20),
              // Shimmer for statistics cards
              SizedBox(
                height: 180,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    Container(
                      width: 160,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Shimmer for classes section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 150, height: 30, color: Colors.white),
                  const SizedBox(height: 10),
                  ...List.generate(
                    1,
                    (index) => Container(
                      height: 150,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // FAB shimmer overlay (always fixed at bottom right)
        Positioned(
          bottom: 16,
          right: 16,
          child: Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Main build method for the dashboard page
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton:
          _isLoading || _isRefreshing
              ? null
              : FloatingActionButton(
                onPressed: () => _showCreateClassOrStudentDialog(context),
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.add, color: Colors.white),
              ),
      body: Stack(
        children: [
          // Main content (hidden when loading)
          if (!_isLoading && !_isRefreshing)
            RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildWelcomeMessage(),
                  const SizedBox(height: 20),
                  _buildStatisticsCards(),
                  const SizedBox(height: 20),
                  _buildMyClassesSection(),
                ],
              ),
            ),

          // Shimmer loading overlay
          if (_isLoading || _isRefreshing) _buildShimmerLoading(),
        ],
      ),
    );
  }

  /// Builds the welcome message section with teacher info
  Widget _buildWelcomeMessage() {
    return FutureBuilder<Teacher>(
      future: _teacherFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorWidget("Failed to load teacher data");
        }

        final teacher = snapshot.data ?? Teacher.empty();

        // Extract data with fallbacks
        final username = teacher.username ?? teacher.name;
        final userId = teacher.userId ?? teacher.id;
        final teacherId = teacher.teacherId;

        final initials =
            teacher.name.isNotEmpty
                ? teacher.name
                    .trim()
                    .split(' ')
                    .map((word) => word[0])
                    .take(2)
                    .join()
                    .toUpperCase()
                : 'T';

        final hasProfile = teacher.profilePicture?.isNotEmpty ?? false;

        // Build the welcome container with IDs displayed
        Widget welcomeWidget = _buildWelcomeContainer(
          username,
          initials,
          null,
          userId: userId,
          teacherId: teacherId,
        );

        if (!hasProfile) {
          return welcomeWidget;
        }

        // Build profile picture URL using Supabase storage
        String? avatarUrl;
        try {
          final profilePicture = teacher.profilePicture!;
          
          // If already a full URL (starts with http/https), use it as is
          if (profilePicture.startsWith('http://') || profilePicture.startsWith('https://')) {
            debugPrint('🖼️ Teacher profile picture is already a full URL');
            avatarUrl = profilePicture;
          } else {
            // Get public URL from Supabase storage 'materials' bucket (matches UserService.uploadProfilePicture)
            final supabase = Supabase.instance.client;
            avatarUrl = supabase.storage
                .from('materials')
                .getPublicUrl(profilePicture);
            debugPrint('🖼️ Normalized teacher profile picture URL: $avatarUrl');
          }
          
          // Add cache buster for network images to force refresh
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          if (avatarUrl.contains('?')) {
            avatarUrl = avatarUrl.split('?').first + '?t=$timestamp';
          } else {
            avatarUrl = '$avatarUrl?t=$timestamp';
          }
        } catch (e) {
          debugPrint('⚠️ Error building teacher profile picture URL: $e');
          avatarUrl = null;
        }

        return _buildWelcomeContainer(
          username,
          initials,
          avatarUrl,
          userId: userId,
          teacherId: teacherId,
        );
      },
    );
  }

  /// Builds the welcome container with teacher avatar and greeting
  Widget _buildWelcomeContainer(
    String username,
    String initials,
    String? avatarUrl, {
    int? userId,
    int? teacherId,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.15),
            Theme.of(context).colorScheme.secondary.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Avatar section with decorative ring
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                avatarUrl != null
                    ? ClipOval(
                      child: FadeInImage(
                        placeholder: AssetImage(
                          'assets/placeholder/avatar_placeholder.jpg',
                        ), // Add this asset
                        image: NetworkImage(avatarUrl),
                        imageErrorBuilder: (context, error, stackTrace) {
                          debugPrint('Failed to load avatar image: $error');
                          return CircleAvatar(
                            radius: 32,
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                        fit: BoxFit.cover,
                        width: 64,
                        height: 64,
                        fadeInDuration: const Duration(milliseconds: 500),
                        fadeInCurve: Curves.easeInOut,
                        placeholderFit: BoxFit.cover,
                      ),
                    )
                    : CircleAvatar(
                      radius: 32,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
          ),

          const SizedBox(width: 20),

          // Welcome text and IDs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Teacher,',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  username,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // ID badges
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (userId != null)
                      _buildIdBadge(
                        context,
                        'User ID: $userId',
                        Icons.person_outline,
                      ),
                    if (teacherId != null)
                      _buildIdBadge(
                        context,
                        'Teacher ID: $teacherId',
                        Icons.school_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Decorative icon
          Icon(
            Icons.waving_hand,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
        ],
      ),
    );
  }

  /// Helper widget for ID badges
  Widget _buildIdBadge(BuildContext context, String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Error widget with better styling
  Widget _buildErrorWidget(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[600], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  /// Builds statistics cards section
  Widget _buildStatisticsCards() {
    return FutureBuilder<List<Student>>(
      future: _studentsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorWidget("Failed to load student data");
        }

        final studentCount = snapshot.hasData ? snapshot.data!.length : 0;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return SizedBox(
          height: 180,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              TeacherDashboardHorizontalCard(
                title: "Students",
                value: studentCount.toString(),
                gradientColors: [
                  colorScheme.primary,
                  colorScheme.primaryContainer,
                ],
                icon: Icons.people_outline,
                onPressed: () {
                  // Navigator.push(
                  //   context,
                  //   MaterialPageRoute(
                  //     builder: (_) => const PupilManagementPage(),
                  //   ),
                  // );
                },
              ),
              const SizedBox(width: 16),
              FutureBuilder<int>(
                future: _classCountFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return TeacherDashboardHorizontalCard(
                      title: "My Classes",
                      value: "0",
                      gradientColors: [
                        colorScheme.primary,
                        colorScheme.primaryContainer,
                      ],
                      icon: Icons.class_outlined,
                    );
                  }
                  final myClassCount = snapshot.data ?? 0;
                  return TeacherDashboardHorizontalCard(
                    title: "My Classes",
                    value: myClassCount.toString(),
                    gradientColors: [
                      colorScheme.primary,
                      colorScheme.primaryContainer,
                    ],
                    icon: Icons.class_outlined,
                  );
                },
              ),
              const SizedBox(width: 16),
            ],
          ),
        );
      },
    );
  }

  /// Builds the "My Classes" section
  Widget _buildMyClassesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "My Classes",
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<Classroom>>(
          future: _classesFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const ErrorState(message: "Failed to load class data");
            }

            final classrooms = snapshot.data ?? [];

            if (classrooms.isEmpty) {
              return const EmptyState(
                title: "No Classrooms Yet! 🏫",
                subtitle: 'Tap the "+" button to get started! 👇',
              );
            }

            return Column(
              children:
                  classrooms
                      .map(
                        (classroom) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
child: TeacherDashboardClassCard(
  classId: classroom.id!,
  className: classroom.className,
  section: "${classroom.gradeLevel} - ${classroom.section}",
  studentCount: classroom.studentCount,
  teacherName: classroom.teacherName ?? "Unknown",
  backgroundImage: classroom.backgroundImage, // ← ADD this
  onView: () => _viewClassDetails(context, classroom.id!),
  onEdit: () => _editClass(context, classroom),
  onDelete: () => _deleteClass(context, classroom.id!),
),
                        ),
                      )
                      .toList(),
            );
          },
        ),
      ],
    );
  }
}

import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:flutter/material.dart';
import 'package:deped_reading_app_laravel/pages/student%20pages/student%20class%20pages/widgets/student_view_page.dart';
import 'package:deped_reading_app_laravel/models/student_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_custom_clippers/flutter_custom_clippers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentListPage extends StatefulWidget {
  final String classId;
  const StudentListPage({super.key, required this.classId});

  @override
  State<StudentListPage> createState() => _StudentListPageState();
}

class _StudentListPageState extends State<StudentListPage> {
  List<Student> _students = [];
  bool _isLoading = true;
  bool _hasError = false;
  int _currentPage = 0;
  final int _studentsPerPage = 6;
  final PageController _pageController = PageController();
  String? _baseUrl;
  String? _currentStudentId; // Changed to String for UUID
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _getCurrentStudentId(); // Get current student ID first
    await _fetchStudents();
  }

  // NEW: Query current student from Supabase using the authenticated user
  Future<void> _getCurrentStudentId() async {
    try {
      // Get the current authenticated user from Supabase
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;

      if (currentUser == null) {
        debugPrint('No authenticated user found');
        await _getCurrentStudentIdFromPrefs();
        return;
      }

      debugPrint('Authenticated user ID: ${currentUser.id}');

      // Query the students table to get the student record for this user
      final response =
          await supabase
              .from('students')
              .select('id, student_name')
              .eq('id', currentUser.id)
              .maybeSingle();

      if (response != null) {
        _currentStudentId = response['id'] as String;
        debugPrint('Current student ID from Supabase: $_currentStudentId');
        debugPrint('Current student name: ${response['student_name']}');
      } else {
        debugPrint('No student record found for user ${currentUser.id}');
        await _getCurrentStudentIdFromPrefs();
      }
    } catch (e) {
      debugPrint('Error getting current student from Supabase: $e');
      // Fallback to SharedPreferences
      await _getCurrentStudentIdFromPrefs();
    }
  }

  // Fallback method: Try to get from SharedPreferences
  Future<void> _getCurrentStudentIdFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Try common keys for student ID (UUID as string)
      final possibleKeys = [
        'student_id',
        'id',
        'userId',
        'studentId',
        'user_id',
      ];

      for (final key in possibleKeys) {
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) {
          _currentStudentId = value;
          debugPrint(
            'Found student ID from SharedPreferences ($key): $_currentStudentId',
          );
          return;
        }
      }

      debugPrint('No student ID found in SharedPreferences');
    } catch (e) {
      debugPrint('Error getting student ID from SharedPreferences: $e');
    }
  }

  Future<void> _fetchStudents() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Use class-specific method to get only classmates in this class
      final fetchedStudents = await ClassroomService.getStudentsByClass(
        widget.classId,
      );

      if (!mounted) return;

      // Sort students with current student first
      _sortAndSetStudents(fetchedStudents);
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      _showErrorSnackbar("Oops! Couldn't load classmates");
    }
  }

  // UPDATED METHOD: Sort with current student always first
  void _sortAndSetStudents(List<Student> students) {
    // Make sure we have the current student ID before sorting
    if (_currentStudentId == null) {
      debugPrint('No current student ID found, sorting alphabetically');
      // Sort alphabetically if no current student ID
      students.sort(
        (a, b) =>
            a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase()),
      );
      setState(() {
        _students = students;
        _isLoading = false;
      });
      return;
    }

    // Sort the list: current student first, then others alphabetically by name
    students.sort((a, b) {
      final bool aIsCurrent = a.id == _currentStudentId;
      final bool bIsCurrent = b.id == _currentStudentId;

      // If a is current student, it should come first
      if (aIsCurrent && !bIsCurrent) return -1;
      // If b is current student, it should come first
      if (!aIsCurrent && bIsCurrent) return 1;

      // If neither or both are current student, sort alphabetically by name
      return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
    });

    setState(() {
      _students = students;
      _isLoading = false;
    });
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      body: Column(
        children: [
          _StudentListHeader(studentCount: _students.length),
          Expanded(
            child: RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: _fetchStudents,
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.white,
              child: _StudentListContent(
                isLoading: _isLoading,
                hasError: _hasError,
                students: _students,
                currentPage: _currentPage,
                pageController: _pageController,
                studentsPerPage: _studentsPerPage,
                currentStudentId: _currentStudentId,
                baseUrl: _baseUrl,
                onRetry: _fetchStudents,
                onPageChanged: (index) => setState(() => _currentPage = index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentListHeader extends StatelessWidget {
  final int studentCount;

  const _StudentListHeader({required this.studentCount});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: WaveClipperOne(reverse: false),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Color(0xFFB71C1C)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Text(
              "$studentCount Students",
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'ComicNeue',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentListContent extends StatelessWidget {
  final bool isLoading;
  final bool hasError;
  final List<Student> students;
  final int currentPage;
  final PageController pageController;
  final int studentsPerPage;
  final String? currentStudentId;
  final String? baseUrl;
  final VoidCallback onRetry;
  final Function(int) onPageChanged;

  const _StudentListContent({
    required this.isLoading,
    required this.hasError,
    required this.students,
    required this.currentPage,
    required this.pageController,
    required this.studentsPerPage,
    required this.currentStudentId,
    required this.baseUrl,
    required this.onRetry,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const _LoadingView();
    if (hasError) return _ErrorView(onRetry: onRetry);
    if (students.isEmpty) return const _EmptyView();

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: constraints.maxHeight * 1.0,
                  child: _StudentGridView(
                    students: students,
                    currentPage: currentPage,
                    pageController: pageController,
                    studentsPerPage: studentsPerPage,
                    currentStudentId: currentStudentId,
                    baseUrl: baseUrl,
                    onPageChanged: onPageChanged,
                  ),
                ),
                _PageIndicators(
                  itemCount: (students.length / studentsPerPage).ceil(),
                  currentPage: currentPage,
                  onDotTap: (index) {
                    pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/animation/loading_rainbow.json',
            width: 90,
            height: 90,
          ),
          const SizedBox(height: 20),
          Text(
            "Loading Students...",
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/animations/error.json', width: 150, height: 150),
          const SizedBox(height: 20),
          Text(
            "Failed to load students",
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/animations/empty.json', width: 250, height: 250),
          const SizedBox(height: 20),
          Text(
            "No classmates yet!",
            style: TextStyle(
              fontSize: 22,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentGridView extends StatelessWidget {
  final List<Student> students;
  final int currentPage;
  final PageController pageController;
  final int studentsPerPage;
  final String? currentStudentId;
  final String? baseUrl;
  final Function(int) onPageChanged;

  const _StudentGridView({
    required this.students,
    required this.currentPage,
    required this.pageController,
    required this.studentsPerPage,
    required this.currentStudentId,
    required this.baseUrl,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      onPageChanged: onPageChanged,
      itemCount: (students.length / studentsPerPage).ceil(),
      itemBuilder: (context, pageIndex) {
        final studentsToShow =
            students
                .skip(pageIndex * studentsPerPage)
                .take(studentsPerPage)
                .toList();

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          physics: const BouncingScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16.0,
            mainAxisSpacing: 16.0,
            childAspectRatio: 0.8,
          ),
          itemCount: studentsToShow.length,
          itemBuilder: (context, index) {
            return _StudentCard(
              student: studentsToShow[index],
              index: index,
              currentStudentId: currentStudentId,
              baseUrl: baseUrl,
            );
          },
        );
      },
    );
  }
}

class _StudentCard extends StatelessWidget {
  final Student student;
  final int index;
  final String? currentStudentId;
  final String? baseUrl;

  const _StudentCard({
    required this.student,
    required this.index,
    required this.currentStudentId,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrentUser =
        currentStudentId != null && student.id == currentStudentId;
    final displayName =
        isCurrentUser ? '${student.studentName} (You)' : student.studentName;
    final profileUrl = _getProfileUrl(student);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 400 + (index * 100)),
      tween: Tween(begin: 0.8, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: StudentCard(
            name: displayName,
            avatarLetter: student.avatarLetter,
            profileUrl: profileUrl,
            isCurrentUser: isCurrentUser,
            onTap:
                () => _navigateToStudentProfile(
                  context,
                  displayName,
                  student.avatarLetter,
                  profileUrl,
                ),
          ),
        );
      },
    );
  }

  String? _getProfileUrl(Student student) {
    if (student.profilePicture != null && student.profilePicture!.isNotEmpty) {
      final url = student.profilePicture!;
      debugPrint('Profile URL for ${student.studentName}: $url');
      return url;
    }
    debugPrint('No profile picture for ${student.studentName}');
    return null; // fallback to avatar initials
  }

  // In the _StudentCard class, update the _navigateToStudentProfile method:

  void _navigateToStudentProfile(
    BuildContext context,
    String name,
    String avatarLetter,
    String? profileUrl,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => StudentProfilePage(
              name: name,
              avatarLetter: avatarLetter,
              avatarColor: Theme.of(context).colorScheme.primary,
              profileUrl: profileUrl,
              studentId: student.id,
            ),
      ),
    );
  }
}

class _PageIndicators extends StatelessWidget {
  final int itemCount;
  final int currentPage;
  final Function(int) onDotTap;

  const _PageIndicators({
    required this.itemCount,
    required this.currentPage,
    required this.onDotTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(itemCount, (index) {
          return GestureDetector(
            onTap: () => onDotTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              width: currentPage == index ? 18.0 : 8.0,
              height: 8.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color:
                    currentPage == index
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.primary.withOpacity(0.3),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class StudentCard extends StatelessWidget {
  final String name;
  final String avatarLetter;
  final String? profileUrl;
  final bool isCurrentUser;
  final VoidCallback onTap;

  const StudentCard({
    super.key,
    required this.name,
    required this.avatarLetter,
    this.profileUrl,
    required this.isCurrentUser,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
        ),
        child: Stack(
          children: [
            if (isCurrentUser) _buildCurrentUserBadge(context),
            _buildStudentContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentUserBadge(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          "YOU",
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStudentContent(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            _buildAvatar(context),
            const SizedBox(height: 8),
            _buildStudentName(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: ClipOval(
        child:
            (profileUrl != null && profileUrl!.isNotEmpty)
                ? FadeInImage.assetNetwork(
                  placeholder: 'assets/placeholder/avatar_placeholder.jpg',
                  image: profileUrl!,
                  fit: BoxFit.cover,
                  imageErrorBuilder: (_, __, ___) => _buildAvatarFallback(context),
                )
                : _buildAvatarFallback(context),
      ),
    );
  }

  Widget _buildAvatarFallback(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary,
      alignment: Alignment.center,
      child: Text(
        avatarLetter.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.bold,
          fontFamily: 'ComicNeue',
        ),
      ),
    );
  }

  Widget _buildStudentName() {
    return Text(
      name.split(' ')[0],
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.black87,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
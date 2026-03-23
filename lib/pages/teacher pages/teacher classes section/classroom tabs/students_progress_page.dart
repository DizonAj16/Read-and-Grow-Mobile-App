import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:flutter/material.dart';
import 'package:deped_reading_app_laravel/models/student_model.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentsProgressPage extends StatefulWidget {
  final String classId;

  const StudentsProgressPage({super.key, required this.classId});

  @override
  State<StudentsProgressPage> createState() => _StudentsProgressPageState();
}

class _StudentsProgressPageState extends State<StudentsProgressPage> {
  List<Student> assignedStudents = [];
  bool isLoading = true;
  bool isRefreshing = false;
  bool isInitialLoad = true; // Track if it's the first load

  bool showShimmer = true; // New state variable for controlling shimmer

  String? baseUrl;

  final Map<int, List<int>> gradeTaskMap = {
    1: [1, 2],
    2: [3],
    3: [4],
    4: [5, 6, 7, 8, 9],
    5: [10, 11, 12, 13],
  };

  @override
  void initState() {
    super.initState();
    _initBaseUrl();
    // Initial load with minimum delay
    Future.wait([
      _loadAssignedStudents(),
      Future.delayed(const Duration(seconds: 2)), // Minimum loading time
    ]).then((_) {
      if (mounted) {
        setState(() => isInitialLoad = false);
      }
    });
  }

  Future<void> _initBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBaseUrl =
        prefs.getString('base_url') ?? 'http://10.0.2.2:8000/api';
    final uri = Uri.parse(savedBaseUrl);
    setState(() {
      baseUrl = '${uri.scheme}://${uri.authority}';
    });
  }

  Future<void> _loadAssignedStudents() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      // 1️⃣ Get assigned student IDs scoped to this class
      final assignedIds = await ClassroomService.getAssignedStudentIdsForClass(widget.classId); // returns Set<String>
      debugPrint("📊 Found ${assignedIds.length} assigned student IDs for class ${widget.classId}");

      // 2️⃣ Get all students
      final allStudents = await ClassroomService.getAllStudents();
      debugPrint("📊 Total students in system: ${allStudents.length}");

      // 3️⃣ Filter only assigned students
      final students = allStudents
          .where((student) => assignedIds.contains(student.id))
          .map((s) => s.copyWith(classRoomId: widget.classId))
          .toList();

      debugPrint("📊 Filtered to ${students.length} assigned students");

      if (mounted) {
        setState(() {
          assignedStudents = students;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error loading assigned students: $e");
      if (mounted) {
        setState(() {
          assignedStudents = [];
          isLoading = false;
        });
      }
    }
  }


  int _extractGradeLevel(dynamic grade) {
    if (grade == null) return 1;

    final gradeString = grade.toString();

    if (int.tryParse(gradeString) != null) {
      return int.parse(gradeString).clamp(1, 5);
    }

    final match = RegExp(r'(\d+)').firstMatch(gradeString);
    if (match != null) {
      final number = int.parse(match.group(0)!);
      return number.clamp(1, 5);
    }

    return 1;
  }

  Widget _buildProgressCard(Student student) {
    final int gradeLevel = _extractGradeLevel(student.studentGrade);
    final int totalTasks = gradeTaskMap[gradeLevel]?.length ?? 0;
    final int completedTasks = student.completedTasks;
    final double progress =
        totalTasks > 0 ? (completedTasks / totalTasks).clamp(0, 1) : 0;

    final String? profileUrl =
        (baseUrl != null &&
                student.profilePicture != null &&
                student.profilePicture!.isNotEmpty)
            ? "$baseUrl/${student.profilePicture}"
            : null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child:
                  profileUrl != null
                      ? FadeInImage.assetNetwork(
                        placeholder:
                            'assets/placeholder/avatar_placeholder.jpg',
                        image: profileUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 400),
                        fadeInCurve: Curves.easeIn,
                        imageErrorBuilder:
                            (_, __, ___) => _buildFallbackAvatar(student),
                      )
                      : _buildFallbackAvatar(student),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.studentName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Grade $gradeLevel • ${student.studentSection ?? ''}",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(
                      progress >= 1 ? Colors.green : Colors.deepPurple,
                    ),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$completedTasks / $totalTasks Tasks Completed",
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          progress >= 1
                              ? Colors.green.shade700
                              : Colors.deepPurple,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackAvatar(Student student) {
    return CircleAvatar(
      radius: 25,
      backgroundColor: Colors.deepPurple.shade100,
      child: Text(
        student.avatarLetter,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple.shade700,
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard() {
    return Center(
      child: Card(
        elevation: 6,
        shadowColor: Colors.deepPurple.withOpacity(0.2),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.deepPurple.withOpacity(0.1),
                child: Icon(
                  Icons.person_off_rounded,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "No Students Yet",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Students have not been assigned to this class.\nPlease check again later.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerProgressCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      period: const Duration(milliseconds: 1500), // Slower shimmer animation

      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 20,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 4),
                    Container(width: 120, height: 12, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(width: 100, height: 12, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4, // Number of shimmer cards to show
      itemBuilder: (context, index) => _buildShimmerProgressCard(),
    );
  }

  Future<void> _handleRefresh() async {
    if (!mounted) return;

    setState(() {
      isRefreshing = true;
      isLoading = true; // Add this to trigger shimmer
    });

    try {
      await _loadAssignedStudents();
    } finally {
      if (mounted) {
        setState(() {
          isRefreshing = false;
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show shimmer during initial load OR while baseUrl is loading
    if (isInitialLoad || isLoading || baseUrl == null) {
      return Scaffold(body: _buildShimmerLoading());
    }

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _handleRefresh,
            child:
                assignedStudents.isEmpty
                    ? ListView(children: [_buildEmptyStateCard()])
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: assignedStudents.length,
                      itemBuilder:
                          (context, index) =>
                              _buildProgressCard(assignedStudents[index]),
                    ),
          ),
          if (isRefreshing)
            const Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

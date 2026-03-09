import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:deped_reading_app_laravel/models/student_model.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';


class StudentsManagementPage extends StatefulWidget {
  final String classId;

  const StudentsManagementPage({super.key, required this.classId});

  @override
  State<StudentsManagementPage> createState() => _StudentsManagementPageState();
}

class _StudentsManagementPageState extends State<StudentsManagementPage> {
  List<Student> allStudents = [];
  List<Student> assignedStudents = [];
  List<Student> filteredUnassigned = [];
  List<Student> filteredAssigned = [];
  bool loading = true;
  int currentAssignedPage = 0;
  int currentUnassignedPage = 0;
  int studentsPerPage = 10;
  final double avatarSize = 55;
  int _refreshCounter = 0;
  bool isRefreshing = false;
  bool isInitialLoad = true;
  final TextEditingController _searchController = TextEditingController();
  final List<int> _pageSizeOptions = [5, 10, 20, 50, 100];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Future.wait([
      _loadStudents(),
      Future.delayed(const Duration(seconds: 2)),
    ]).then((_) {
      if (mounted) {
        setState(() => isInitialLoad = false);
      }
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    // Filter unassigned students
    filteredUnassigned =
        allStudents.where((student) {
          if (_searchQuery.isEmpty) return true;

          final fullName = student.studentName.toLowerCase();
          final username = student.username?.toLowerCase() ?? '';
          final lrn = student.studentLrn?.toLowerCase() ?? '';

          return fullName.contains(_searchQuery) ||
              username.contains(_searchQuery) ||
              lrn.contains(_searchQuery);
        }).toList();

    // Filter assigned students
    filteredAssigned =
        assignedStudents.where((student) {
          if (_searchQuery.isEmpty) return true;

          final fullName = student.studentName.toLowerCase();
          final username = student.username?.toLowerCase() ?? '';
          final lrn = student.studentLrn?.toLowerCase() ?? '';

          return fullName.contains(_searchQuery) ||
              username.contains(_searchQuery) ||
              lrn.contains(_searchQuery);
        }).toList();

    // Reset pagination when filters change
    currentUnassignedPage = 0;
    currentAssignedPage = 0;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor:
            isError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      _refreshCounter++;
      allStudents = [];
      assignedStudents = [];
    });

    try {
      final allStudentsList = await ClassroomService.getAllStudents();
      final assignedIds = await ClassroomService.getAssignedStudentIdsForClass(
        widget.classId,
      );
      final globallyAssignedIds =
          await ClassroomService.getGloballyAssignedStudentIds();

      final assignedList = <Student>[];
      final unassignedList = <Student>[];

      for (var student in allStudentsList) {
        if (assignedIds.contains(student.id)) {
          assignedList.add(student.copyWith(classRoomId: widget.classId));
        } else if (!globallyAssignedIds.contains(student.id)) {
          unassignedList.add(student.copyWith(classRoomId: null));
        }
      }

      if (!mounted) return;

      setState(() {
        assignedStudents = assignedList;
        allStudents = unassignedList;
        _applyFilters();
      });
    } catch (e, stackTrace) {
      print('Error in _loadStudents: $e');
      print(stackTrace);
      if (mounted) {
        _showSnackBar("Failed to load students: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _handleRefresh() async {
    if (!mounted) return;

    setState(() {
      isRefreshing = true;
      loading = true;
    });

    try {
      await _loadStudents();
    } finally {
      if (mounted) {
        setState(() => isRefreshing = false);
      }
    }
  }

  Future<void> _assignStudent(Student student) async {
    final res = await ClassroomService.assignStudent(
      studentId: student.id,
      classRoomId: widget.classId,
    );

    if (res == null) {
      _showSnackBar("Failed to assign student", isError: true);
      return;
    }

    if (res.containsKey('error')) {
      final errorMessage =
          res['error'] as String? ?? 'Failed to assign student';
      _showSnackBar(errorMessage, isError: true);
      return;
    }

    await _loadStudents();
    currentUnassignedPage = 0;
    currentAssignedPage = 0;
    _showSnackBar("Student assigned successfully");
  }

  Future<void> _unassignStudent(Student student) async {
    final res = await ClassroomService.unassignStudent(
      studentId: student.id,
      classRoomId: widget.classId,
    );

    if (res.statusCode == 200) {
      await _loadStudents();
      _showSnackBar("Student unassigned successfully");
    } else {
      _showSnackBar("Failed to unassign student: ${res.body}", isError: true);
    }
  }

  // Generate initials from first letter of each word in full name
  String _generateInitials(String fullName) {
    if (fullName.isEmpty) return "S";

    final nameParts =
        fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();

    if (nameParts.isEmpty) return "S";

    if (nameParts.length == 1) {
      return nameParts[0][0].toUpperCase();
    } else {
      return '${nameParts.first[0]}${nameParts.last[0]}'.toUpperCase();
    }
  }

  Widget _buildStudentAvatar(Student student, bool isAssigned) {
    if (student.profilePicture == null || student.profilePicture!.isEmpty) {
      return _buildAvatarFallback(student, isAssigned);
    }

    final profileUrl = student.profilePicture!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(avatarSize / 2),
      child: FadeInImage.assetNetwork(
        placeholder: 'assets/placeholder/avatar_placeholder.jpg',
        image: profileUrl,
        fit: BoxFit.cover,
        width: avatarSize,
        height: avatarSize,
        fadeInDuration: const Duration(milliseconds: 800),
        fadeInCurve: Curves.easeInOut,
        imageErrorBuilder:
            (_, __, ___) => _buildAvatarFallback(student, isAssigned),
        placeholderErrorBuilder:
            (_, __, ___) => _buildAvatarFallback(student, isAssigned),
      ),
    );
  }

  Widget _buildAvatarFallback(Student student, bool isAssigned) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initials = _generateInitials(student.studentName);

    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
            fontSize: avatarSize * 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildStudentCard(Student student, {bool isAssigned = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      borderRadius: BorderRadius.circular(16),
      color: colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showStudentActionSheet(student, isAssigned),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.surface, width: 2),
                    ),
                    child: _buildStudentAvatar(student, isAssigned),
                  ),

                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.studentName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (student.username != null &&
                            student.username!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withOpacity(
                                0.7,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.secondaryContainer
                                    .withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              "@${student.username!}",
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(
                              0.7,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.primaryContainer.withOpacity(
                                0.3,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            "${student.studentGrade ?? 'N/A'}${student.studentSection != null && student.studentSection!.isNotEmpty ? ' - ${student.studentSection!}' : ''}",
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                isAssigned ? Icons.person : Icons.person_add_alt,
                color: isAssigned ? colorScheme.primary : colorScheme.secondary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerTabBar() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: kToolbarHeight,
        color: Colors.white,
        child: Row(
          children: List.generate(
            2,
            (index) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerStudentCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 20,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 6),
                  Container(width: 100, height: 16, color: Colors.white),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerSectionHeader() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: 200,
        height: 24,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  void _showStudentActionSheet(Student student, bool isAssigned) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _buildStudentAvatar(student, isAssigned),
                  title: Text(
                    student.studentName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    isAssigned ? "Currently assigned" : "Available to assign",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
                const Divider(height: 24),
                _buildActionTile(
                  context,
                  icon: isAssigned ? Icons.person_remove : Icons.person_add,
                  label: isAssigned ? "Unassign Student" : "Assign Student",
                  color:
                      isAssigned
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                  onTap: () {
                    Navigator.pop(context);
                    _showConfirmationBottomSheet(student, isAssigned);
                  },
                ),
                const SizedBox(height: 8),
                _buildActionTile(
                  context,
                  icon: Icons.close,
                  label: "Cancel",
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _showConfirmationBottomSheet(Student student, bool isAssigned) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isAssigned ? Icons.warning : Icons.person_add_alt_1,
                  color: isAssigned ? colorScheme.error : colorScheme.primary,
                ),
                title: Text(
                  isAssigned ? "Confirm Unassignment" : "Confirm Assignment",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  isAssigned
                      ? "Are you sure you want to unassign ${student.studentName} from this class?"
                      : "Are you sure you want to assign ${student.studentName} to this class?",
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isAssigned ? colorScheme.error : colorScheme.primary,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      if (isAssigned) {
                        _unassignStudent(student);
                      } else {
                        _assignStudent(student);
                      }
                    },
                    child: Text(
                      isAssigned ? "Unassign" : "Assign",
                      style: TextStyle(color: colorScheme.onPrimary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Student> get paginatedUnassigned {
    final start = currentUnassignedPage * studentsPerPage;
    final end = (start + studentsPerPage).clamp(0, filteredUnassigned.length);
    return filteredUnassigned.sublist(start, end);
  }

  List<Student> get paginatedAssigned {
    final start = currentAssignedPage * studentsPerPage;
    final end = (start + studentsPerPage).clamp(0, filteredAssigned.length);
    return filteredAssigned.sublist(start, end);
  }

  Widget _buildShimmerTabContent() {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShimmerSectionHeader(),
            const SizedBox(height: 12),
            Column(
              children: List.generate(3, (index) => _buildShimmerStudentCard()),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surface,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: "Search by name, username, or LRN...",
          prefixIcon: Icon(Icons.search, color: colorScheme.primary),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                    icon: Icon(Icons.clear, color: colorScheme.primary),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                  : null,
          filled: true,
          fillColor: colorScheme.primaryContainer.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPageSizeSelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Items per page:",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          DropdownButton<int>(
            value: studentsPerPage,
            icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
            elevation: 4,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
            underline: Container(height: 2, color: colorScheme.primary),
            onChanged: (int? newValue) {
              if (newValue != null) {
                setState(() {
                  studentsPerPage = newValue;
                  currentUnassignedPage = 0;
                  currentAssignedPage = 0;
                });
              }
            },
            items:
                _pageSizeOptions.map<DropdownMenuItem<int>>((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text(value.toString()),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInitialLoad || loading) {
      return Scaffold(
        body: Column(
          children: [
            _buildShimmerTabBar(),
            Expanded(child: _buildShimmerTabContent()),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 100),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const TabBar(
                  dividerHeight: 0,
                  tabs: [
                    Tab(text: "Available Students"),
                    Tab(text: "Class List"),
                  ],
                ),
                _buildSearchBar(),
                _buildPageSizeSelector(),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildStudentList(
              students: paginatedUnassigned,
              isAssigned: false,
              currentPage: currentUnassignedPage,
              totalItems: filteredUnassigned.length,
              totalCount: filteredUnassigned.length,
              onNextPage: () => setState(() => currentUnassignedPage++),
              onPrevPage: () => setState(() => currentUnassignedPage--),
            ),
            _buildStudentList(
              students: paginatedAssigned,
              isAssigned: true,
              currentPage: currentAssignedPage,
              totalItems: filteredAssigned.length,
              totalCount: filteredAssigned.length,
              onNextPage: () => setState(() => currentAssignedPage++),
              onPrevPage: () => setState(() => currentAssignedPage--),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentList({
    required List<Student> students,
    required bool isAssigned,
    required int currentPage,
    required int totalItems,
    required int totalCount,
    required VoidCallback onNextPage,
    required VoidCallback onPrevPage,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalPages = (totalItems / studentsPerPage).ceil();

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAssigned
                  ? "Class List ($totalCount Assigned)"
                  : "Available Students ($totalCount)",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            if (_searchQuery.isNotEmpty && totalCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "No students found for '$_searchQuery'",
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              )
            else if (students.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(
                      isAssigned
                          ? Icons.people_outline
                          : Icons.person_add_disabled,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isAssigned
                          ? "There are no students assigned to this class yet."
                          : "There are currently no available students to assign.",
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              ...students.map(
                (student) => _buildStudentCard(student, isAssigned: isAssigned),
              ),
              if (totalPages > 1)
                _buildPaginationControls(
                  currentPage: currentPage,
                  totalPages: totalPages,
                  totalItems: totalItems,
                  onNext: onNextPage,
                  onPrevious: onPrevPage,
                  onPageSelect: (page) {
                    setState(() {
                      if (isAssigned) {
                        currentAssignedPage = page;
                      } else {
                        currentUnassignedPage = page;
                      }
                    });
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationControls({
    required int currentPage,
    required int totalPages,
    required int totalItems,
    required VoidCallback onNext,
    required VoidCallback onPrevious,
    required Function(int) onPageSelect,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final startItem = (currentPage * studentsPerPage) + 1;
    final endItem = ((currentPage + 1) * studentsPerPage).clamp(1, totalItems);

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "Showing $startItem-$endItem of $totalItems",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: currentPage > 0 ? onPrevious : null,
                color:
                    currentPage > 0
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.3),
              ),
              const SizedBox(width: 8),
              // Use a scrollable container for page numbers
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(totalPages, (index) {
                      final isCurrent = index == currentPage;
                      return GestureDetector(
                        onTap: () => onPageSelect(index),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                isCurrent
                                    ? colorScheme.primary
                                    : colorScheme.primaryContainer.withOpacity(
                                      0.2,
                                    ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  isCurrent
                                      ? colorScheme.primary
                                      : colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            (index + 1).toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  isCurrent
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                              fontWeight:
                                  isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentPage < totalPages - 1 ? onNext : null,
                color:
                    currentPage < totalPages - 1
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Page:",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${currentPage + 1}",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                "/ $totalPages",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

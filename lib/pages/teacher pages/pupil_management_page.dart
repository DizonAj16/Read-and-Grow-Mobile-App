import 'package:flutter/material.dart';
import 'teacher dashboard/create student and classes/create_class_or_student_dialog.dart';
import '../../models/student_model.dart';
import '../../api/classroom_service.dart';
import 'edit_student_profile_teacher_page.dart';

class PupilManagementPage extends StatefulWidget {
  const PupilManagementPage({super.key});

  @override
  State<PupilManagementPage> createState() => _PupilManagementPageState();
}

class _PupilManagementPageState extends State<PupilManagementPage> {
  List<Student> _allPupils = [];
  List<Student> _filteredPupils = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedGradeFilter;
  String? _selectedSectionFilter;

  @override
  void initState() {
    super.initState();
    _loadPupils();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPupils() async {
    setState(() => _isLoading = true);

    try {
      final pupils = await ClassroomService.getAllStudents();

      setState(() {
        _allPupils = pupils;
        _filteredPupils = pupils;
      });
    } catch (e) {
      debugPrint('Error loading pupils: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading pupils: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredPupils =
          _allPupils.where((pupil) {
            final matchesSearch =
                _searchQuery.isEmpty ||
                pupil.studentName.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                (pupil.studentLrn?.toLowerCase() ?? '').contains(
                  _searchQuery.toLowerCase(),
                ) ||
                (pupil.username?.toLowerCase() ?? '').contains(
                  _searchQuery.toLowerCase(),
                );

            final matchesGrade =
                _selectedGradeFilter == null ||
                _selectedGradeFilter!.isEmpty ||
                pupil.studentGrade == _selectedGradeFilter;

            final matchesSection =
                _selectedSectionFilter == null ||
                _selectedSectionFilter!.isEmpty ||
                pupil.studentSection == _selectedSectionFilter;

            return matchesSearch && matchesGrade && matchesSection;
          }).toList();
    });
  }

  void _showAddPupilDialog() {
    showDialog(
      context: context,
      builder:
          (context) => CreateClassOrStudentDialog(
            initialTab:
                1, // Start with Student form (1) instead of Class form (0)
            onStudentAdded: () {
              _loadPupils();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Pupil added successfully!'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
    );
  }

  Future<void> _refreshPupils() async {
    await _loadPupils();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Pupil list refreshed'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPupilOptions(BuildContext context, Student pupil) {
    final screenHeight = MediaQuery.of(context).size.height;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.7, // Maximum 70% of screen height
        minHeight: 300, // Minimum height
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SingleChildScrollView(
              // Makes content scrollable if needed
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with pupil info
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildAvatar(
                          pupil.profilePicture,
                          pupil.studentName.isNotEmpty
                              ? pupil.studentName.substring(0, 1).toUpperCase()
                              : '?',
                          radius: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pupil.studentName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Grade ${pupil.studentGrade ?? 'N/A'} - ${pupil.studentSection ?? 'N/A'}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (pupil.studentLrn != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'LRN: ${pupil.studentLrn!}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildActionButton(
                          icon: Icons.visibility_outlined,
                          title: 'View Details',
                          subtitle: 'See complete pupil information',
                          color: Theme.of(context).colorScheme.primary,
                          onTap: () {
                            Navigator.pop(context);
                            _showPupilDetails(context, pupil);
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildActionButton(
                          icon: Icons.edit_outlined,
                          title: 'Edit Profile',
                          subtitle: 'Edit profile & assign reading level',
                          color: Colors.green,
                          onTap: () async {
                            Navigator.pop(context);
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => EditStudentProfileTeacherPage(
                                      studentId: pupil.id,
                                    ),
                              ),
                            );
                            if (result == true) {
                              _loadPupils();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '✅ Student profile updated successfully!',
                                  ),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildActionButton(
                          icon: Icons.assignment_outlined,
                          title: 'Assign to Class',
                          subtitle: 'Manage class assignments',
                          color: Theme.of(context).colorScheme.secondary,
                          onTap: () {
                            Navigator.pop(context);
                            // Add your assign to class logic here
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: Colors.grey[400],
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _showPupilDetails(BuildContext context, Student pupil) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildAvatar(
                          pupil.profilePicture,
                          pupil.studentName.isNotEmpty
                              ? pupil.studentName.substring(0, 1).toUpperCase()
                              : '?',
                          radius: 40,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          pupil.studentName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (pupil.studentGrade != null ||
                            pupil.studentSection != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Grade ${pupil.studentGrade ?? 'N/A'} - ${pupil.studentSection ?? 'N/A'}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Details
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildDetailItem(
                            icon: Icons.person_outline,
                            title: 'Full Name',
                            value: pupil.studentName,
                          ),
                          if (pupil.studentLrn != null)
                            _buildDetailItem(
                              icon: Icons.badge_outlined,
                              title: 'LRN',
                              value: pupil.studentLrn!,
                            ),
                          if (pupil.username != null)
                            _buildDetailItem(
                              icon: Icons.account_circle_outlined,
                              title: 'Username',
                              value: pupil.username!,
                            ),
                          if (pupil.studentGrade != null)
                            _buildDetailItem(
                              icon: Icons.school_outlined,
                              title: 'Grade Level',
                              value: 'Grade ${pupil.studentGrade!}',
                            ),
                          if (pupil.studentSection != null)
                            _buildDetailItem(
                              icon: Icons.group_outlined,
                              title: 'Section',
                              value: pupil.studentSection!,
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Close button
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> get _availableGrades {
    final grades =
        _allPupils
            .map((p) => p.studentGrade)
            .whereType<String>()
            .toSet()
            .toList();
    grades.sort();
    return grades;
  }

  List<String> get _availableSections {
    final sections =
        _allPupils
            .map((p) => p.studentSection)
            .whereType<String>()
            .toSet()
            .toList();
    sections.sort();
    return sections;
  }

  Widget _buildSearchAndFilters() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Section
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name, LRN, or username...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey[500]),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                      _applyFilters();
                    },
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear, color: Colors.grey[500]),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                      _applyFilters();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Filters Section
          Text(
            'FILTERS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildFilterChip(
                title: 'Grade',
                value: _selectedGradeFilter,
                items: _availableGrades,
                onChanged: (value) {
                  setState(() {
                    _selectedGradeFilter = value;
                  });
                  _applyFilters();
                },
              ),
              _buildFilterChip(
                title: 'Section',
                value: _selectedSectionFilter,
                items: _availableSections,
                onChanged: (value) {
                  setState(() {
                    _selectedSectionFilter = value;
                  });
                  _applyFilters();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String title,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: DropdownButton<String>(
        value: value,
        hint: Text(title, style: TextStyle(color: Colors.grey[600],)),
        items:
            [null, ...items].map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(
                  item ?? 'All $title' + (title == 'Grade' ? 's' : 's'),
                  style: TextStyle(
                    color:
                        item == null
                            ? Colors.grey[500]
                            : Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                  ),
                ),
              );
            }).toList(),
        onChanged: onChanged,
        underline: const SizedBox(),
        icon: Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).colorScheme.primary,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildPupilCard(Student pupil) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        color: Colors.white,
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: _buildAvatar(
            pupil.profilePicture,
            pupil.studentName.isNotEmpty
                ? pupil.studentName.substring(0, 1).toUpperCase()
                : '?',
            radius: 28,
          ),
          title: Text(
            pupil.studentName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pupil.studentLrn != null)
                Text(
                  'LRN: ${pupil.studentLrn}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              if (pupil.studentGrade != null)
                Text(
                  'Grade ${pupil.studentGrade}${pupil.studentSection != null ? ' - ${pupil.studentSection}' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.more_vert,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
          ),
          onTap: () => _showPupilOptions(context, pupil),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  CircleAvatar _buildAvatar(
    String? url,
    String fallbackLetter, {
    double radius = 28,
  }) {
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        child: Text(
          fallbackLetter,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.7,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      child: ClipOval(
        child: FadeInImage.assetNetwork(
          placeholder: 'assets/placeholder/avatar_placeholder.jpg',
          image: url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          imageErrorBuilder:
              (_, __, ___) => CircleAvatar(
                radius: radius,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.2),
                child: Text(
                  fallbackLetter,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: radius * 0.7,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body:
          _isLoading
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFE53935)),
                    SizedBox(height: 16),
                    Text(
                      'Loading Pupils...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
              : Column(
                children: [
                  _buildSearchAndFilters(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.refresh, size: 24),
                        tooltip: 'Refresh',
                        onPressed: _refreshPupils,
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadPupils,
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: Colors.white,
                      child:
                          _filteredPupils.isEmpty
                              ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_search,
                                      size: 80,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'No pupils yet'
                                          : 'No pupils found',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'Add your first pupil to get started'
                                          : 'Try adjusting your search or filters',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (_searchQuery.isEmpty) ...[
                                      const SizedBox(height: 20),
                                      ElevatedButton.icon(
                                        onPressed: _showAddPupilDialog,
                                        icon: const Icon(
                                          Icons.person_add,
                                          size: 20,
                                        ),
                                        label: const Text('Add First Pupil'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: 2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                              : ListView.builder(
                                itemCount: _filteredPupils.length,
                                itemBuilder:
                                    (context, index) =>
                                        _buildPupilCard(_filteredPupils[index]),
                              ),
                    ),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPupilDialog,
        icon: const Icon(Icons.person_add_alt_1, size: 24),
        label: const Text(
          'Add Pupil',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

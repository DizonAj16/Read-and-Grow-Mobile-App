import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class StudentReadingProgressPage extends StatefulWidget {
  final String classId;

  const StudentReadingProgressPage({super.key, required this.classId});

  @override
  State<StudentReadingProgressPage> createState() =>
      _StudentReadingProgressPageState();
}

class _StudentReadingProgressPageState
    extends State<StudentReadingProgressPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;

  List<Map<String, dynamic>> students = [];
  Map<String, Map<String, dynamic>> readingLevels = {};

  // Filter states
  String? selectedReadingLevel;
  bool showFilters = false;
  String? selectedGrade;
  String? selectedSection;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;

  // Graph states
  bool _showGraph = true;
  int? _hoveredStudentIndex;
  double _zoomLevel = 1.0;
  final double _minZoom = 0.5;
  final double _maxZoom = 2.0;
  bool _isFullScreen = false;

  // Responsive layout values
  bool _isMobile = false;
  bool _isTablet = false;
  bool _isDesktop = false;

  // Timer for filter debouncing
  Timer? _filterDebounceTimer;

  // Track selected students for highlighting
  final Set<int> _selectedStudents = {};

  @override
  void initState() {
    super.initState();
    _loadReadingLevels();
    _loadStudents();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateResponsiveValues();
  }

  void _updateResponsiveValues() {
    final screenWidth = MediaQuery.of(context).size.width;
    setState(() {
      _isMobile = screenWidth < 600;
      _isTablet = screenWidth >= 600 && screenWidth < 1024;
      _isDesktop = screenWidth >= 1024;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    _filterDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _loadStudents();
    });
  }

  Future<void> _loadReadingLevels() async {
    try {
      final levelsRes = await supabase
          .from('reading_levels')
          .select('*')
          .order('level_number', ascending: true);

      for (var level in levelsRes) {
        final lid = level['id']?.toString();
        if (lid != null) {
          readingLevels[lid] = Map<String, dynamic>.from(level);
        }
      }
    } catch (e) {
      debugPrint('Error loading reading levels: $e');
    }
  }

  Future<void> _loadStudents() async {
    setState(() => isLoading = true);

    try {
      // First get enrolled student IDs for this class
      final enrollmentsRes = await supabase
          .from('student_enrollments')
          .select('student_id')
          .eq('class_room_id', widget.classId);

      final enrolledStudentIds =
          enrollmentsRes
              .map((e) => e['student_id']?.toString())
              .whereType<String>()
              .toList();

      if (enrolledStudentIds.isEmpty) {
        if (mounted) {
          setState(() {
            isLoading = false;
            students = [];
          });
        }
        return;
      }

      // Now get student details with reading levels
      var query = supabase
          .from('students')
          .select('*, reading_levels!left(*)')
          .inFilter('id', enrolledStudentIds);

      // Apply filters
      if (selectedReadingLevel != null) {
        query = query.eq('current_reading_level_id', selectedReadingLevel!);
      }

      if (selectedGrade != null) {
        query = query.eq('student_grade', selectedGrade!);
      }

      if (selectedSection != null) {
        query = query.eq('student_section', selectedSection!);
      }

      final searchTerm = _searchController.text.trim();
      if (searchTerm.isNotEmpty) {
        query = query.or(
          'student_name.ilike.%$searchTerm%,student_lrn.ilike.%$searchTerm%',
        );
      }

      final studentsRes = await query.order('student_name', ascending: true);

      final newStudents = List<Map<String, dynamic>>.from(studentsRes);

      if (mounted) {
        setState(() {
          students = newStudents;
          isLoading = false;
          _selectedStudents.clear();
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading students: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _clearFilters() {
    setState(() {
      selectedReadingLevel = null;
      selectedGrade = null;
      selectedSection = null;
      _searchController.clear();
    });
    _loadStudents();
  }

  // Get initials from student name
  String _getInitials(String name) {
    if (name.isEmpty) return '??';

    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.length == 1) {
      return parts[0].length >= 2
          ? parts[0].substring(0, 2).toUpperCase()
          : parts[0].toUpperCase();
    }
    return '??';
  }

  // Get color for avatar based on student ID (consistent color per student)
  Color _getAvatarColor(String? studentId, int levelNumber) {
    if (studentId == null) {
      // Fallback to level-based color
      return _getLevelColor(levelNumber);
    }

    // Generate consistent color from student ID hash
    final hash = studentId.hashCode;
    final hue = (hash % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.7, 0.85).toColor();
  }

  Color _getLevelColor(int levelNumber) {
    final colors = [
      const Color(0xFFEF5350), // Level 1 - Red
      const Color(0xFFFF9800), // Level 2 - Orange
      const Color(0xFFFFEB3B), // Level 3 - Yellow
      const Color(0xFF4CAF50), // Level 4 - Green
      const Color(0xFF2196F3), // Level 5 - Blue
      const Color(0xFF3F51B5), // Level 6 - Indigo
      const Color(0xFF9C27B0), // Level 7 - Purple
      const Color(0xFFE91E63), // Level 8 - Pink
    ];
    final index = (levelNumber - 1) % colors.length;
    return index >= 0 ? colors[index] : colors[0];
  }

  // Prepare data for Syncfusion chart

  // Prepare data for Syncfusion chart - Add profile picture
  List<ChartData> _getChartData() {
    // Sort students by level and then name for better visualization
    final sortedStudents = List<Map<String, dynamic>>.from(students)
      ..sort((a, b) {
        final levelA = readingLevels[a['current_reading_level_id']?.toString()];
        final levelB = readingLevels[b['current_reading_level_id']?.toString()];
        final levelNumA = levelA?['level_number'] ?? 0;
        final levelNumB = levelB?['level_number'] ?? 0;
        if (levelNumA != levelNumB) {
          return levelNumA.compareTo(levelNumB);
        }
        return (a['student_name'] ?? '').compareTo(b['student_name'] ?? '');
      });

    return sortedStudents.asMap().entries.map((entry) {
      final index = entry.key;
      final student = entry.value;
      final studentName = student['student_name'] ?? 'Unknown';
      final levelId = student['current_reading_level_id']?.toString();
      final readingLevel = levelId != null ? readingLevels[levelId] : null;
      final levelNumber = readingLevel?['level_number'] ?? 0;
      final studentId = student['id']?.toString();
      final profilePicture = student['profile_picture']; // Get profile picture

      return ChartData(
        studentName: studentName,
        level: levelNumber,
        studentIndex: index,
        color: _getAvatarColor(studentId, levelNumber),
        levelName: readingLevel?['title'] ?? 'Level $levelNumber',
        initials: _getInitials(studentName),
        profilePicture: profilePicture, // Add profile picture
        isSelected: _selectedStudents.contains(index),
      );
    }).toList();
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        _updateResponsiveValues();
      }
    });
  }

  void _toggleStudentSelection(int index) {
    setState(() {
      if (_selectedStudents.contains(index)) {
        _selectedStudents.remove(index);
      } else {
        _selectedStudents.add(index);
      }
    });
  }

  void _clearAllSelections() {
    setState(() {
      _selectedStudents.clear();
    });
  }

  void _selectAllStudents() {
    setState(() {
      _selectedStudents.clear();
      for (int i = 0; i < students.length; i++) {
        _selectedStudents.add(i);
      }
    });
  }

  Widget _buildSyncfusionChart() {
    final chartData = _getChartData();
    if (chartData.isEmpty) {
      return Container(
        height: _isFullScreen ? double.infinity : 400,
        margin:
            _isFullScreen
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding:
            _isFullScreen ? const EdgeInsets.all(32) : const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              _isFullScreen ? BorderRadius.zero : BorderRadius.circular(20),
          boxShadow:
              _isFullScreen
                  ? []
                  : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.bar_chart,
                size: _isFullScreen ? 120 : 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No data available for graph',
                style: TextStyle(
                  fontSize: _isFullScreen ? 24 : 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxLevel = readingLevels.values.fold<int>(0, (max, level) {
      final levelNum = level['level_number'] ?? 0;
      return levelNum > max ? levelNum : max;
    });

    return Container(
      margin:
          _isFullScreen
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(
                horizontal: _isMobile ? 8 : 16,
                vertical: 12,
              ),
      padding:
          _isFullScreen
              ? const EdgeInsets.all(24)
              : EdgeInsets.all(_isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            _isFullScreen ? BorderRadius.zero : BorderRadius.circular(20),
        boxShadow:
            _isFullScreen
                ? []
                : [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate available height
          final availableHeight = constraints.maxHeight;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - Responsive layout
              if (!_isFullScreen) ...[
                _isMobile
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.trending_up_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Reading Progress Chart',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: _showGraph ? 'Hide Chart' : 'Show Chart',
                              child: IconButton(
                                icon: Icon(
                                  _showGraph
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showGraph = !_showGraph;
                                  });
                                },
                              ),
                            ),
                            // Tooltip(
                            //   message: 'Full Screen',
                            //   child: IconButton(
                            //     icon: Icon(
                            //       Icons.fullscreen,
                            //       color: Theme.of(context).colorScheme.primary,
                            //       size: 20,
                            //     ),
                            //     onPressed: _toggleFullScreen,
                            //   ),
                            // ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${students.length} Students • ${maxLevel} Levels',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Selection controls for mobile
                        if (chartData.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Tooltip(
                                  message: 'Select All',
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.select_all,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      size: 18,
                                    ),
                                    onPressed: _selectAllStudents,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Theme.of(context).colorScheme.primary,
                                        Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.8),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_selectedStudents.length} selected',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Clear Selection',
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.clear_all,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      size: 18,
                                    ),
                                    onPressed: _clearAllSelections,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                    : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.trending_up_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Reading Progress Dashboard',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${students.length} Students • ${maxLevel} Reading Levels',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            // Selection controls
                            if (chartData.isNotEmpty) ...[
                              Tooltip(
                                message: 'Select All',
                                child: IconButton(
                                  icon: Icon(
                                    Icons.select_all,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  onPressed: _selectAllStudents,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context).colorScheme.primary,
                                      Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.8),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_selectedStudents.length} selected',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: 'Clear Selection',
                                child: IconButton(
                                  icon: Icon(
                                    Icons.clear_all,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  onPressed: _clearAllSelections,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Tooltip(
                              message: _showGraph ? 'Hide Chart' : 'Show Chart',
                              child: IconButton(
                                icon: Icon(
                                  _showGraph
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showGraph = !_showGraph;
                                  });
                                },
                              ),
                            ),
                            Tooltip(
                              message: 'Full Screen',
                              child: IconButton(
                                icon: Icon(
                                  Icons.fullscreen,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: _toggleFullScreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                const SizedBox(height: 16),
              ] else ...[
                // Full screen header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.arrow_back,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: _toggleFullScreen,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Full Screen Progress Chart',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (chartData.isNotEmpty) ...[
                            Tooltip(
                              message: 'Select All',
                              child: IconButton(
                                icon: Icon(
                                  Icons.select_all,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: _selectAllStudents,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_selectedStudents.length} selected',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Clear Selection',
                              child: IconButton(
                                icon: Icon(
                                  Icons.clear_all,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: _clearAllSelections,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Tooltip(
                            message: 'Exit Full Screen',
                            child: IconButton(
                              icon: Icon(
                                Icons.fullscreen_exit,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              onPressed: _toggleFullScreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Main content area - Make it scrollable if needed
              Expanded(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: availableHeight * 0.6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Chart area
                        SizedBox(
                          height:
                              _isFullScreen
                                  ? availableHeight * 0.7
                                  : (_isMobile
                                      ? availableHeight * 0.4
                                      : availableHeight * 0.5),
                          child: _buildChartWidget(
                            chartData,
                            maxLevel,
                            availableHeight,
                          ),
                        ),

                        // Additional statistics
                        if (!_isFullScreen && chartData.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: EdgeInsets.all(_isMobile ? 12 : 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Statistics',
                                  style: TextStyle(
                                    fontSize: _isMobile ? 11 : 12,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _isMobile
                                    ? Column(
                                      children: [
                                        _buildStatRow(
                                          'Average Level',
                                          '${_calculateAverageLevel(chartData).toStringAsFixed(1)}',
                                          Icons.abc_rounded,
                                        ),
                                        const SizedBox(height: 6),
                                        _buildStatRow(
                                          'Highest Level',
                                          '${_getHighestLevel(chartData)}',
                                          Icons.trending_up,
                                        ),
                                        const SizedBox(height: 6),
                                        _buildStatRow(
                                          'Lowest Level',
                                          '${_getLowestLevel(chartData)}',
                                          Icons.trending_down,
                                        ),
                                      ],
                                    )
                                    : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _buildStatColumn(
                                          'Average Level',
                                          '${_calculateAverageLevel(chartData).toStringAsFixed(1)}',
                                          Icons.abc_rounded,
                                        ),
                                        _buildStatColumn(
                                          'Highest Level',
                                          '${_getHighestLevel(chartData)}',
                                          Icons.trending_up,
                                        ),
                                        _buildStatColumn(
                                          'Lowest Level',
                                          '${_getLowestLevel(chartData)}',
                                          Icons.trending_down,
                                        ),
                                        _buildStatColumn(
                                          'Progress Range',
                                          '${_getLevelRange(chartData)}',
                                          Icons.bar_chart,
                                        ),
                                      ],
                                    ),
                              ],
                            ),
                          ),
                        ],

                        // Student list for selection
                        if (!_isFullScreen && chartData.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: EdgeInsets.all(_isMobile ? 12 : 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Students (${chartData.length})',
                                      style: TextStyle(
                                        fontSize: _isMobile ? 12 : 14,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Tooltip(
                                          message: 'List View',
                                          child: Icon(
                                            Icons.list,
                                            size: _isMobile ? 16 : 18,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Tap to highlight',
                                          style: TextStyle(
                                            fontSize: _isMobile ? 10 : 11,
                                            color: Colors.grey[600],
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: _isMobile ? 100 : 120,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: chartData.length,
                                    itemBuilder: (context, index) {
                                      final student = chartData[index];
                                      final isSelected = _selectedStudents
                                          .contains(index);

                                      return GestureDetector(
                                        onTap:
                                            () =>
                                                _toggleStudentSelection(index),
                                        child: Container(
                                          width: _isMobile ? 80 : 90,
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color:
                                                isSelected
                                                    ? student.color.withOpacity(
                                                      0.1,
                                                    )
                                                    : Colors.grey[50],
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color:
                                                  isSelected
                                                      ? student.color
                                                      : Colors.grey[300]!,
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              // In the student list section, update the CircleAvatar to show profile picture
                                              CircleAvatar(
                                                backgroundColor: student.color,
                                                radius: _isMobile ? 18 : 22,
                                                backgroundImage:
                                                    student.profilePicture !=
                                                                null &&
                                                            student
                                                                .profilePicture!
                                                                .isNotEmpty
                                                        ? CachedNetworkImageProvider(
                                                              student
                                                                  .profilePicture!,
                                                            )
                                                            as ImageProvider<
                                                              Object
                                                            >?
                                                        : null,
                                                child:
                                                    student.profilePicture !=
                                                                null &&
                                                            student
                                                                .profilePicture!
                                                                .isNotEmpty
                                                        ? null // No child when we have an image
                                                        : Text(
                                                          student.initials,
                                                          style: TextStyle(
                                                            fontSize:
                                                                _isMobile
                                                                    ? 11
                                                                    : 13,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                student.studentName
                                                    .split(' ')
                                                    .first,
                                                style: TextStyle(
                                                  fontSize: _isMobile ? 9 : 10,
                                                  fontWeight:
                                                      isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                  color:
                                                      isSelected
                                                          ? Theme.of(
                                                            context,
                                                          ).colorScheme.primary
                                                          : Colors.grey[700],
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: student.color,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'L${student.level}',
                                                  style: TextStyle(
                                                    fontSize: _isMobile ? 8 : 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  double _calculateAverageLevel(List<ChartData> data) {
    if (data.isEmpty) return 0;
    final total = data.fold(0, (sum, item) => sum + item.level);
    return total / data.length;
  }

  int _getHighestLevel(List<ChartData> data) {
    if (data.isEmpty) return 0;
    return data.fold(0, (max, item) => math.max(max, item.level));
  }

  int _getLowestLevel(List<ChartData> data) {
    if (data.isEmpty) return 0;
    return data.fold(
      data.first.level,
      (min, item) => math.min(min, item.level),
    );
  }

  int _getLevelRange(List<ChartData> data) {
    if (data.isEmpty) return 0;
    final highest = _getHighestLevel(data);
    final lowest = _getLowestLevel(data);
    return highest - lowest;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final screenWidth = MediaQuery.of(context).size.width;

    // Determine screen size for responsive design
    final isMobile = screenWidth < 600;

    // If in full screen mode, show only the chart
    if (_isFullScreen) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child:
              _showGraph
                  ? _buildSyncfusionChart()
                  : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bar_chart_outlined,
                            size: 80,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Chart is Hidden',
                          style: TextStyle(
                            fontSize: 28,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Tap the eye icon to show the reading progress chart',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _showGraph = true;
                            });
                          },
                          icon: const Icon(Icons.visibility),
                          label: const Text('Show Progress Chart'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      );
    }

    // Normal view
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Reading Progress',
          style: TextStyle(
            fontSize: isMobile ? 18 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryColor),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child:
            isLoading
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Loading student progress...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
                : students.isEmpty
                ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: isMobile ? 80 : 100,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No Students Found',
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 20 : 40,
                          ),
                          child: Text(
                            'Try adjusting your filters or check if students are assigned to this class.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isMobile ? 14 : 16,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                : _showGraph
                ? _buildSyncfusionChart()
                : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: isMobile ? 100 : 120,
                          height: isMobile ? 100 : 120,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bar_chart_outlined,
                            size: isMobile ? 50 : 60,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Progress Chart is Hidden',
                          style: TextStyle(
                            fontSize: isMobile ? 18 : 20,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 20 : 40,
                          ),
                          child: Text(
                            'Tap the eye icon to show the reading progress chart',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isMobile ? 14 : 16,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _showGraph = true;
                            });
                          },
                          icon: const Icon(Icons.visibility),
                          label: Text(
                            'Show Progress Chart',
                            style: TextStyle(fontSize: isMobile ? 14 : 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 20 : 24,
                              vertical: isMobile ? 12 : 12,
                            ),
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  // Separate method to build the chart widget
  Widget _buildChartWidget(
    List<ChartData> chartData,
    int maxLevel,
    double availableHeight,
  ) {
    if (_isFullScreen || !_isMobile) {
      return SfCartesianChart(
        margin: EdgeInsets.zero,
        plotAreaBorderWidth: 0,
        primaryXAxis: CategoryAxis(
          majorGridLines: const MajorGridLines(width: 0),
          axisLine: const AxisLine(width: 2, color: Colors.grey),
          labelStyle: TextStyle(
            fontSize: _isFullScreen ? 14 : (_isMobile ? 10 : 12),
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
          majorTickLines: const MajorTickLines(size: 0),
          labelRotation: _isMobile ? 45 : 0,
        ),
        primaryYAxis: NumericAxis(
          minimum: 0,
          maximum: maxLevel.toDouble() + 1,
          interval: 1,
          majorGridLines: const MajorGridLines(width: 0),
          axisLine: const AxisLine(width: 2, color: Colors.grey),
          labelStyle: TextStyle(
            fontSize: _isFullScreen ? 14 : (_isMobile ? 10 : 12),
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
          majorTickLines: const MajorTickLines(size: 0),
          labelFormat: '{value}',
        ),
        title: ChartTitle(
          text: 'Reading Levels Distribution',
          textStyle: TextStyle(
            fontSize: _isFullScreen ? 20 : (_isMobile ? 14 : 16),
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
          alignment: ChartAlignment.near,
        ),
        tooltipBehavior: TooltipBehavior(
          enable: true,
          header: '',
          format: 'point.y • point.series.name',
          textStyle: TextStyle(
            fontSize: _isFullScreen ? 14 : 12,
            fontWeight: FontWeight.w600,
          ),
          color: Colors.white,
          borderColor: Colors.grey[300]!,
          borderWidth: 1,
        ),
        series: <CartesianSeries<ChartData, String>>[
          ScatterSeries<ChartData, String>(
            dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.studentName,
            yValueMapper: (ChartData data, _) => data.level.toDouble(),
            pointColorMapper: (ChartData data, _) => data.color,
            name: 'Reading Level',
            markerSettings: MarkerSettings(
              isVisible: true,
              shape: DataMarkerType.circle,
              borderWidth: 2,
              borderColor: Colors.white,
              height: _isFullScreen ? 24 : (_isMobile ? 16 : 20),
              width: _isFullScreen ? 24 : (_isMobile ? 16 : 20),
            ),
            dataLabelSettings: DataLabelSettings(
              isVisible: true,
              textStyle: TextStyle(
                fontSize: _isFullScreen ? 12 : (_isMobile ? 8 : 10),
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              labelAlignment: ChartDataLabelAlignment.top,
            ),
          ),
          if (_selectedStudents.isNotEmpty)
            ScatterSeries<ChartData, String>(
              dataSource: chartData.where((data) => data.isSelected).toList(),
              xValueMapper: (ChartData data, _) => data.studentName,
              yValueMapper: (ChartData data, _) => data.level.toDouble(),
              pointColorMapper: (ChartData data, _) => data.color,
              name: 'Selected',
              markerSettings: MarkerSettings(
                isVisible: true,
                shape: DataMarkerType.diamond,
                borderWidth: 3,
                borderColor: Theme.of(context).colorScheme.primary,
                height: _isFullScreen ? 32 : (_isMobile ? 20 : 26),
                width: _isFullScreen ? 32 : (_isMobile ? 20 : 26),
              ),
            ),
        ],
        legend: Legend(
          isVisible: true,
          position: LegendPosition.bottom,
          overflowMode: LegendItemOverflowMode.wrap,
          textStyle: TextStyle(
            fontSize: _isFullScreen ? 14 : (_isMobile ? 10 : 12),
            fontWeight: FontWeight.w500,
          ),
        ),
        trackballBehavior: TrackballBehavior(
          enable: true,
          activationMode: ActivationMode.singleTap,
          tooltipSettings: InteractiveTooltip(
            format: 'Reading Level: point.y',
            textStyle: TextStyle(
              fontSize: _isFullScreen ? 14 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          lineType: TrackballLineType.vertical,
          lineWidth: 1,
          lineColor: Colors.grey[400]!,
          markerSettings: TrackballMarkerSettings(
            markerVisibility: TrackballVisibilityMode.visible,
            height: _isFullScreen ? 16 : 12,
            width: _isFullScreen ? 16 : 12,
            borderWidth: 2,
            borderColor: Colors.white,
          ),
        ),
        zoomPanBehavior: ZoomPanBehavior(
          enablePinching: true,
          enablePanning: true,
          enableDoubleTapZooming: true,
          zoomMode: ZoomMode.xy,
          maximumZoomLevel: 5,
        ),
      );
    } else {
      // Mobile version without title, legend, and zoom
      return SfCartesianChart(
        margin: EdgeInsets.zero,
        plotAreaBorderWidth: 0,
        primaryXAxis: CategoryAxis(
          majorGridLines: const MajorGridLines(width: 0),
          axisLine: const AxisLine(width: 2, color: Colors.grey),
          labelStyle: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
          majorTickLines: const MajorTickLines(size: 0),
          labelRotation: 45,
        ),
        primaryYAxis: NumericAxis(
          minimum: 0,
          maximum: maxLevel.toDouble() + 1,
          interval: 1,
          majorGridLines: const MajorGridLines(width: 0),
          axisLine: const AxisLine(width: 2, color: Colors.grey),
          labelStyle: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
          majorTickLines: const MajorTickLines(size: 0),
          labelFormat: '{value}',
        ),
        tooltipBehavior: TooltipBehavior(
          enable: true,
          header: '',
          format: 'point.y • point.series.name',
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          color: Colors.white,
          borderColor: Colors.grey[300]!,
          borderWidth: 1,
        ),
        series: <CartesianSeries<ChartData, String>>[
          ScatterSeries<ChartData, String>(
            dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.studentName,
            yValueMapper: (ChartData data, _) => data.level.toDouble(),
            pointColorMapper: (ChartData data, _) => data.color,
            name: 'Reading Level',
            markerSettings: MarkerSettings(
              isVisible: true,
              shape: DataMarkerType.circle,
              borderWidth: 2,
              borderColor: Colors.white,
              height: 16,
              width: 16,
            ),
            dataLabelSettings: const DataLabelSettings(isVisible: false),
          ),
          if (_selectedStudents.isNotEmpty)
            ScatterSeries<ChartData, String>(
              dataSource: chartData.where((data) => data.isSelected).toList(),
              xValueMapper: (ChartData data, _) => data.studentName,
              yValueMapper: (ChartData data, _) => data.level.toDouble(),
              pointColorMapper: (ChartData data, _) => data.color,
              name: 'Selected',
              markerSettings: MarkerSettings(
                isVisible: true,
                shape: DataMarkerType.diamond,
                borderWidth: 3,
                borderColor: Theme.of(context).colorScheme.primary,
                height: 20,
                width: 20,
              ),
            ),
        ],
        legend: const Legend(isVisible: false),
        trackballBehavior: TrackballBehavior(
          enable: true,
          activationMode: ActivationMode.singleTap,
          tooltipSettings: InteractiveTooltip(
            format: 'Reading Level: point.y',
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          lineType: TrackballLineType.vertical,
          lineWidth: 1,
          lineColor: Colors.grey[400]!,
          markerSettings: TrackballMarkerSettings(
            markerVisibility: TrackballVisibilityMode.visible,
            height: 12,
            width: 12,
            borderWidth: 2,
            borderColor: Colors.white,
          ),
        ),
      );
    }
  }
}

// Data model for chart - Update the constructor and add profilePicture field
class ChartData {
  final String studentName;
  final int level;
  final int studentIndex;
  final Color color;
  final String levelName;
  final String initials;
  final String? profilePicture; // Add this
  final bool isSelected;

  ChartData({
    required this.studentName,
    required this.level,
    required this.studentIndex,
    required this.color,
    required this.levelName,
    required this.initials,
    this.profilePicture, // Add this
    this.isSelected = false,
  });
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'enhanced_reading_material_page.dart';
import '../../api/reading_materials_service.dart';

class EnhancedReadingLevelPage extends StatefulWidget {
  final String? classId; // Add optional classId parameter for class context

  const EnhancedReadingLevelPage({super.key, this.classId});

  @override
  State<EnhancedReadingLevelPage> createState() =>
      _EnhancedReadingLevelPageState();
}

class _EnhancedReadingLevelPageState extends State<EnhancedReadingLevelPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? currentLevel;
  List<Map<String, dynamic>> materials = [];
  List<Map<String, dynamic>> filteredMaterials =
      []; // Materials with prerequisite status
  Map<String, dynamic> submissionMap =
      {}; // Maps material_id to submission record
  bool isLoading = true;
  late TabController _tabController;
  int _currentTabIndex = 0; // 0 = All, 1 = Completed
  late ColorScheme _colorScheme;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
    _loadReadingLevel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = Theme.of(context).colorScheme;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getPrimaryColor([double opacity = 1.0]) {
    return _colorScheme.primary.withOpacity(opacity);
  }

  Color _getOnPrimaryColor([double opacity = 1.0]) {
    return _colorScheme.onPrimary.withOpacity(opacity);
  }

  Color _getSurfaceVariantColor([double opacity = 1.0]) {
    return _colorScheme.surfaceVariant.withOpacity(opacity);
  }

  Future<void> _loadReadingLevel() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // 🔹 Fetch student's record
      final studentRes =
          await supabase
              .from('students')
              .select('id, current_reading_level_id')
              .eq('id', user.id)
              .maybeSingle();

      if (studentRes == null ||
          studentRes['current_reading_level_id'] == null) {
        if (mounted) {
          setState(() => isLoading = false);
        }
        return;
      }

      final studentId = studentRes['id'];
      final levelId = studentRes['current_reading_level_id'];

      // 🔹 Get level details
      final levelRes =
          await supabase
              .from('reading_levels')
              .select('*')
              .eq('id', levelId)
              .maybeSingle();

      // 🔹 Get reading materials with prerequisite status
      final materialsData =
          await ReadingMaterialsService.getReadingMaterialsByLevelForStudent(
            levelId,
            studentId,
            classRoomId: widget.classId,
          );
      // Sort the materialsData by material.createdAt before mapping
      materialsData.sort((a, b) {
        final materialA = a['material'] as ReadingMaterial;
        final materialB = b['material'] as ReadingMaterial;
        return materialA.createdAt.compareTo(
          materialB.createdAt,
        ); // Ascending order
      });
      // Convert to our format
      final materialsList =
          materialsData.map((data) {
            final material = data['material'] as ReadingMaterial;
            final isAccessible = data['is_accessible'] as bool;
            final hasCompletedPrerequisite =
                data['has_completed_prerequisite'] as bool;
            final hasCompletedMaterial = data['has_completed_material'] as bool;
            final prerequisiteTitle = data['prerequisite_title'] as String?;

            return {
              'material': material,
              'is_accessible': isAccessible,
              'has_completed_prerequisite': hasCompletedPrerequisite,
              'has_completed_material': hasCompletedMaterial,
              'prerequisite_title': prerequisiteTitle,
              'id': material.id,
              'title': material.title,
              'description': material.description,
              'file_url': material.fileUrl,
              'audio_url': material.audioUrl, 

              'created_at': material.createdAt.toIso8601String(),
              'class_room_id': material.classRoomId,
              'level_id': material.levelId,
              'level_number': material.levelNumber,
              'level_title': material.levelTitle,
              'has_prerequisite': material.hasPrerequisite,
              'prerequisite_id': material.prerequisiteId,
              'prerequisite_title': material.prerequisiteTitle,
            };
          }).toList();

      // 🔹 Get student's submission records for these materials
      final materialIds =
          materialsList
              .map((m) => m['id'].toString())
              .whereType<String>()
              .toList();

      if (materialIds.isNotEmpty) {
        final submissionsRes = await supabase
            .from('student_recordings')
            .select(
              'id, teacher_comments, recorded_at, needs_grading, score, file_url, is_retake_requested, material_id',
            )
            .eq('student_id', studentId)
            .inFilter('material_id', materialIds)
            .isFilter('task_id', null); // task_id is NULL for materials

        final Map<String, dynamic> submissions = {};
        for (final s in submissionsRes) {
          final materialId = s['material_id'] as String?;
          if (materialId != null && materialIds.contains(materialId)) {
            submissions[materialId] = s;
          }
        }

        if (mounted) {
          setState(() {
            currentLevel = levelRes;
            materials = materialsList;
            submissionMap = submissions;
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            currentLevel = levelRes;
            materials = materialsList;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading reading level: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      isLoading = true;
    });
    await _loadReadingLevel();
  }

  bool _isMaterialSubmitted(dynamic materialId) {
    return submissionMap.containsKey(materialId.toString());
  }

  bool _isRetakeRequested(dynamic materialId) {
    final recording = submissionMap[materialId.toString()];
    return recording != null && recording['is_retake_requested'] == true;
  }

  bool _isGraded(dynamic materialId) {
    final recording = submissionMap[materialId.toString()];
    return recording != null && recording['needs_grading'] == false;
  }

  /// Check if material has prerequisite and if student can access it
  bool _isMaterialAccessible(Map<String, dynamic> material) {
    return material['is_accessible'] as bool? ?? true;
  }

  /// Check if material has prerequisite
  bool _hasPrerequisite(Map<String, dynamic> material) {
    return material['has_prerequisite'] as bool? ?? false;
  }

  /// Get prerequisite title
  String? _getPrerequisiteTitle(Map<String, dynamic> material) {
    return material['prerequisite_title'] as String?;
  }

  /// Get filtered materials based on current tab
  List<Map<String, dynamic>> _getFilteredMaterials() {
    final allMaterials = materials;

    if (_currentTabIndex == 0) {
      // All materials
      return allMaterials;
    } else {
      // Submitted materials only
      return allMaterials.where((material) {
        final materialId = material['id']?.toString();
        return materialId != null && _isMaterialSubmitted(materialId);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor();
    final onPrimaryColor = _getOnPrimaryColor();
    final primaryLight = _getPrimaryColor(0.1);
    final primaryMedium = _getPrimaryColor(0.3);

    // Check if we're in class context
    final isClassContext = widget.classId != null && widget.classId!.isNotEmpty;

    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 16),
              Text(
                isClassContext
                    ? 'Loading Class Reading Materials...'
                    : 'Loading Reading Level...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (currentLevel == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: RefreshIndicator(
          key: _refreshIndicatorKey,
          color: primaryColor,
          backgroundColor: Colors.white,
          onRefresh: _refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 100,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isClassContext
                            ? 'No Reading Level for this Class'
                            : 'No Reading Level Assigned',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isClassContext
                            ? 'Your teacher has not assigned reading materials to your level for this class yet.'
                            : 'Your teacher has not assigned a reading level yet. Please ask your teacher to assign you a reading level to get started.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _refreshData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: onPrimaryColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final accessibleMaterials =
        materials.where((m) => _isMaterialAccessible(m)).toList();
    final inaccessibleMaterials =
        materials.where((m) => !_isMaterialAccessible(m)).toList();
    final submittedCount = submissionMap.length;
    final progressPercent =
        materials.isNotEmpty ? submittedCount / materials.length : 0.0;

    // Determine if we're in class context to show appropriate title
    final pageTitle =
        isClassContext ? 'Class Reading Level' : 'My Reading Level';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        color: primaryColor,
        backgroundColor: Colors.white,
        onRefresh: _refreshData,
        child: Column(
          children: [
            // Progress Header with Gradient
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primaryColor.withOpacity(0.9),
                    primaryColor.withOpacity(0.7),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Level Title
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: onPrimaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Level ${currentLevel!['title']}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: onPrimaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: onPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: onPrimaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Progress Info Text
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isClassContext
                                  ? 'Reading Progress'
                                  : 'Reading Progress',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: onPrimaryColor.withOpacity(0.9),
                              ),
                            ),
                            Text(
                              '${(progressPercent * 100).toInt()}% Complete',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: onPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Progress Bar
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                            value: progressPercent,
                            backgroundColor: onPrimaryColor.withOpacity(0.1),
                            color: onPrimaryColor,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),

                        // Progress Stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildProgressStat(
                              'Total',
                              '${materials.length}',
                              Icons.library_books_outlined,
                              onPrimaryColor,
                            ),
                            _buildProgressStat(
                              'Submitted',
                              '$submittedCount',
                              Icons.check_circle_outline,
                              onPrimaryColor,
                            ),
                            _buildProgressStat(
                              'Pending',
                              '${materials.length - submittedCount}',
                              Icons.access_time_outlined,
                              onPrimaryColor,
                            ),
                            if (inaccessibleMaterials.isNotEmpty)
                              _buildProgressStat(
                                'Locked',
                                '${inaccessibleMaterials.length}',
                                Icons.lock_outline,
                                Colors.amber,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tabs
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: primaryColor,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(
                    text: 'All Materials',
                    icon: Icon(Icons.library_books_outlined),
                  ),
                  Tab(
                    text: 'Submitted',
                    icon: Icon(Icons.check_circle_outline),
                  ),
                ],
                onTap: (index) {
                  setState(() {
                    _currentTabIndex = index;
                  });
                },
              ),
            ),

            // Materials List
            Expanded(
              child: Builder(
                builder: (context) {
                  final filteredMaterials = _getFilteredMaterials();

                  if (filteredMaterials.isEmpty) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _currentTabIndex == 0
                                      ? Icons.library_books_outlined
                                      : Icons.check_circle_outline,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _currentTabIndex == 0
                                      ? isClassContext
                                          ? 'No Reading Materials in this Class'
                                          : 'No Reading Materials Available'
                                      : isClassContext
                                      ? 'No Class Materials Submitted'
                                      : 'No Materials Submitted',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _currentTabIndex == 0
                                      ? isClassContext
                                          ? 'Your teacher will add reading materials for this class soon.'
                                          : 'Check back later for new reading materials'
                                      : isClassContext
                                      ? 'Submit recordings for this class to see them here'
                                      : 'Submit recordings to see them here',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: _refreshData,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: onPrimaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredMaterials.length,
                    itemBuilder: (context, index) {
                      final material = filteredMaterials[index];
                      final materialId = material['id'];
                      final originalIndex = materials.indexWhere(
                        (m) => m['id'] == materialId,
                      );
                      final submitted = _isMaterialSubmitted(materialId);
                      final isRetakeRequested = _isRetakeRequested(materialId);
                      final isGraded = _isGraded(materialId);
                      final isAccessible = _isMaterialAccessible(material);
                      final hasPrerequisite = _hasPrerequisite(material);
                      final prerequisiteTitle = _getPrerequisiteTitle(material);

                      // Check if material belongs to current class (when in class context)
                      final materialClassId = material['class_room_id'];
                      final isClassMaterial =
                          isClassContext
                              ? materialClassId == widget.classId
                              : true;

                      return _buildMaterialCard(
                        material: material,
                        index: originalIndex != -1 ? originalIndex : index,
                        submitted: submitted,
                        isRetakeRequested: isRetakeRequested,
                        isGraded: isGraded,
                        isAccessible: isAccessible,
                        hasPrerequisite: hasPrerequisite,
                        prerequisiteTitle: prerequisiteTitle,
                        isClassMaterial: isClassMaterial,
                        primaryColor: primaryColor,
                        onPrimaryColor: onPrimaryColor,
                        primaryLight: primaryLight,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStat(
    String label,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: iconColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: iconColor.withOpacity(0.8)),
        ),
      ],
    );
  }

  Widget _buildMaterialCard({
    required Map<String, dynamic> material,
    required int index,
    required bool submitted,
    required bool isRetakeRequested,
    required bool isGraded,
    required bool isAccessible,
    required bool hasPrerequisite,
    required String? prerequisiteTitle,
    required bool isClassMaterial,
    required Color primaryColor,
    required Color onPrimaryColor,
    required Color primaryLight,
  }) {
    final materialNumber = index + 1;
    final isSubmitted = submitted;

    // Determine card colors based on accessibility and status
    Color statusColor;
    Color statusLightColor;
    IconData statusIcon;
    String statusText;
    String actionText;
    bool isDisabled = !isAccessible;

    if (!isAccessible) {
      statusColor = Colors.grey;
      statusLightColor = Colors.grey.withOpacity(0.1);
      statusIcon = Icons.lock_outline;
      statusText = 'Locked';
      actionText = 'Complete Prerequisite';
    } else if (isRetakeRequested) {
      statusColor = Colors.orange;
      statusLightColor = Colors.orange.withOpacity(0.1);
      statusIcon = Icons.replay;
      statusText = 'Retake Requested';
      actionText = 'Record Retake';
    } else if (isSubmitted) {
      statusColor = isGraded ? Colors.green : Colors.blue;
      statusLightColor =
          isGraded
              ? Colors.green.withOpacity(0.1)
              : Colors.blue.withOpacity(0.1);
      statusIcon = isGraded ? Icons.check_circle : Icons.hourglass_top;
      statusText = isGraded ? 'Graded' : 'Submitted';
      actionText = 'View';
    } else {
      statusColor = primaryColor;
      statusLightColor = primaryLight;
      statusIcon = Icons.play_circle_outline;
      statusText = 'Start Reading';
      actionText = 'Read Now';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap:
              isDisabled
                  ? null
                  : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => EnhancedReadingMaterialPage(
                              material: material,
                              classId: widget.classId,
                            ),
                      ),
                    ).then((_) {
                      if (mounted) {
                        _refreshData();
                      }
                    });
                  },
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    // Material Number Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusLightColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isClassMaterial
                                ? Icons.class_
                                : Icons.library_books,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isClassMaterial
                                ? 'Class Material $materialNumber'
                                : 'Material $materialNumber',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Status Indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusLightColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Material Title
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        material['title'] ?? 'Untitled Material',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDisabled ? Colors.grey : Colors.blueGrey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasPrerequisite && isAccessible)
                      Tooltip(
                        message: 'Has prerequisite: $prerequisiteTitle',
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.amber[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.lock_open,
                            size: 14,
                            color: Colors.amber[800],
                          ),
                        ),
                      ),
                    if (!isAccessible)
                      Tooltip(
                        message: 'Complete "$prerequisiteTitle" first',
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.lock,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                  ],
                ),

                // Material Description
                if (material['description'] != null &&
                    material['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    material['description'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Prerequisite Warning (if locked)
                if (!isAccessible && prerequisiteTitle != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Complete "$prerequisiteTitle" first',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Footer Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Action Button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isDisabled
                                ? Colors.grey.withOpacity(0.1)
                                : isRetakeRequested
                                ? Colors.orange.withOpacity(0.1)
                                : isSubmitted
                                ? (isGraded
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.blue.withOpacity(0.1))
                                : primaryLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isDisabled
                                  ? Colors.grey.withOpacity(0.3)
                                  : isRetakeRequested
                                  ? Colors.orange.withOpacity(0.3)
                                  : isSubmitted
                                  ? (isGraded
                                      ? Colors.green.withOpacity(0.3)
                                      : Colors.blue.withOpacity(0.3))
                                  : primaryColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDisabled
                                ? Icons.lock
                                : isRetakeRequested
                                ? Icons.replay
                                : isSubmitted
                                ? Icons.visibility
                                : Icons.play_arrow,
                            size: 16,
                            color:
                                isDisabled
                                    ? Colors.grey
                                    : isRetakeRequested
                                    ? Colors.orange
                                    : isSubmitted
                                    ? (isGraded ? Colors.green : Colors.blue)
                                    : primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isDisabled ? 'Locked' : actionText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDisabled
                                      ? Colors.grey
                                      : isRetakeRequested
                                      ? Colors.orange
                                      : isSubmitted
                                      ? (isGraded ? Colors.green : Colors.blue)
                                      : primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Additional indicators
                    if (!isDisabled && isRetakeRequested)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber,
                            size: 18,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Retake Needed',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    else if (!isDisabled && isSubmitted)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.audio_file, size: 18, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Recording Available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                    // Arrow Indicator
                    if (!isDisabled)
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: primaryColor.withOpacity(0.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

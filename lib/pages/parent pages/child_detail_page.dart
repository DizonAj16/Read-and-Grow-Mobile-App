import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../api/parent_service.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Philippine Time offset (UTC+8).
const _kPhOffset = Duration(hours: 8);

/// Tab count for the detail page.
const _kTabCount = 4;

/// Maximum reading score used throughout the page.
const _kMaxReadingScore = 5.0;

// ---------------------------------------------------------------------------
// Score helpers (pure functions – easy to unit-test)
// ---------------------------------------------------------------------------

/// Returns a [Color] based on a 0–1 [percent] value.
Color _percentColor(double percent) {
  if (percent >= 0.8) return Colors.green.shade600;
  if (percent >= 0.6) return Colors.orange.shade600;
  return Colors.red.shade600;
}

/// Returns a [Color] for a reading score on a 0–5 scale.
Color _readingScoreColor(double score) {
  if (score >= 4) return Colors.green.shade600;
  if (score >= 3) return Colors.orange.shade600;
  if (score >= 2) return Colors.orange.shade400;
  return Colors.red.shade600;
}

/// Returns a human-readable label for a reading score.
String _readingScoreLabel(double score) {
  if (score >= 4) return 'Excellent';
  if (score >= 3) return 'Good';
  if (score >= 2) return 'Fair';
  return 'Needs Improvement';
}

/// Returns a human-readable label for a quiz average (0–100).
String _quizAverageLabel(double avg) {
  if (avg >= 90) return 'Excellent';
  if (avg >= 75) return 'Good';
  if (avg >= 60) return 'Fair';
  return 'Needs Improvement';
}

/// Converts a UTC ISO-8601 string to Philippine Time and formats it.
///
/// Returns `'Unknown'` for null/empty input and `'Invalid date'` if parsing
/// fails.
String _formatDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return 'Unknown';
  final utc = DateTime.tryParse(raw);
  if (utc == null) return 'Invalid date';
  final ph = utc.add(_kPhOffset);
  return DateFormat('MMMM d, y h:mm a').format(ph);
}

// ---------------------------------------------------------------------------
// Data model helpers
// ---------------------------------------------------------------------------

/// Enriches a raw quiz-submission map with parsed/formatted date fields.
Map<String, dynamic> _enrichSubmission(Map<String, dynamic> raw) {
  final data = Map<String, dynamic>.from(raw);

  data['quiz_title'] = (data['quiz_title'] as String?) ?? 'Quiz';

  final submittedAtStr = data['submitted_at'] as String?;
  if (submittedAtStr != null) {
    final utc = DateTime.tryParse(submittedAtStr);
    if (utc != null) {
      data['submitted_at_datetime'] = utc.add(_kPhOffset);
      data['submitted_at_formatted'] = _formatDateTime(submittedAtStr);
    }
  }

  return data;
}

/// Sorts submissions by [submitted_at_datetime] descending (latest first).
int _compareSubmissionsDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = a['submitted_at_datetime'] as DateTime? ?? DateTime.now();
  final bDate = b['submitted_at_datetime'] as DateTime? ?? DateTime.now();
  return bDate.compareTo(aDate);
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class ChildDetailPage extends StatefulWidget {
  const ChildDetailPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  final String studentId;
  final String studentName;

  @override
  State<ChildDetailPage> createState() => _ChildDetailPageState();
}

class _ChildDetailPageState extends State<ChildDetailPage>
    with SingleTickerProviderStateMixin {
  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  late final TabController _tabController;
  bool _isLoading = true;

  // — Progress —
  String _readingLevel = 'Not Set';
  int _totalTasks = 0;
  int _completedTasks = 0;
  int _pendingTasks = 0;
  int _totalCorrect = 0;
  int _totalWrong = 0;
  double _averageScore = 0;

  // — Quizzes —
  int _totalQuizzes = 0;
  int _completedQuizzes = 0;
  double _quizAverage = 0;
  List<Map<String, dynamic>> _quizSubmissions = [];
  List<Map<String, dynamic>> _recentSubmissions = [];

  // — Reading grades —
  List<Map<String, dynamic>> readingGrades = [];

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kTabCount, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Data loading
  // -------------------------------------------------------------------------

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _fetchAndApplyData();
    } catch (e, stack) {
      debugPrint('❌ [ChildDetailPage] Error loading data: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAndApplyData() async {
    final service = ParentService();

    final progressData = await service.getChildProgress(widget.studentId);
    readingGrades = await service.getReadingGrades(widget.studentId);

    if (progressData != null) {
      _applyProgressData(progressData);
    }

    _debugLog();
  }

  void _applyProgressData(Map<String, dynamic> data) {
    // General
    _readingLevel = (data['readingLevel'] as String?) ?? 'Not Set';
    _completedTasks = (data['completedTasks'] as int?) ?? 0;
    _pendingTasks = (data['pendingTasks'] as int?) ?? 0;
    _totalTasks = _completedTasks + _pendingTasks;
    _totalCorrect = (data['totalCorrect'] as int?) ?? 0;
    _totalWrong = (data['totalWrong'] as int?) ?? 0;
    _averageScore = (data['averageScore'] as double?) ?? 0.0;

    // Quizzes
    _totalQuizzes = (data['totalQuizzes'] as int?) ?? 0;
    _completedQuizzes = (data['completedQuizzes'] as int?) ?? 0;
    _quizAverage = (data['quizAverage'] as double?) ?? 0.0;

    // Submissions
    final rawList = (data['quizSubmissions'] as List<dynamic>?) ?? [];
    _quizSubmissions =
        rawList
            .map((e) => _enrichSubmission(Map<String, dynamic>.from(e)))
            .toList()
          ..sort(_compareSubmissionsDesc);

    _recentSubmissions = _quizSubmissions.take(5).toList();
  }

  void _debugLog() {
    // Serialize DateTimes to strings before encoding to avoid JSON errors.
    debugPrint(
      '📋 [ChildDetailPage] Quiz submissions:\n'
      '${const JsonEncoder.withIndent('  ').convert(_quizSubmissions.map((e) {
        final copy = Map<String, dynamic>.from(e);
        final dt = copy['submitted_at_datetime'];
        if (dt is DateTime) copy['submitted_at_datetime'] = dt.toIso8601String();
        return copy;
      }).toList())}',
    );

    debugPrint(
      '📚 [ChildDetailPage] Reading grades:\n'
      '${const JsonEncoder.withIndent('  ').convert(readingGrades)}',
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(cs),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primary.withOpacity(0.05), cs.background],
          ),
        ),
        child: _isLoading ? _buildLoadingIndicator(cs) : _buildTabBarView(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    return AppBar(
      title: Text(
        widget.studentName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
      ),
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 0,
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: cs.onPrimary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: cs.onPrimary,
        unselectedLabelColor: cs.onPrimary.withOpacity(0.7),
        labelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: const [
          Tab(icon: Icon(Icons.trending_up, size: 20), text: 'Progress'),
          Tab(icon: Icon(Icons.quiz, size: 20), text: 'Quiz Scores'),
          Tab(icon: Icon(Icons.book, size: 20), text: 'Reading Grades'),
          Tab(icon: Icon(Icons.assessment, size: 20), text: 'Reports'),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 22),
          onPressed: _loadData,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading Student Data...',
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.6),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildProgressTab(),
        _buildQuizScoresTab(),
        _buildReadingGradesTab(),
        _buildReportsTab(),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Tab: Progress
  // -------------------------------------------------------------------------

  Widget _buildProgressTab() {
    final cs = Theme.of(context).colorScheme;
    final completionPercent =
        _totalTasks > 0 ? (_completedTasks / _totalTasks).clamp(0.0, 1.0) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadingLevelCard(readingLevel: _readingLevel),
          const SizedBox(height: 24),

          _buildSectionTitle('Reading Task Progress'),
          const SizedBox(height: 16),
          _TaskCompletionCard(
            completedTasks: _completedTasks,
            totalTasks: _totalTasks,
            pendingTasks: _pendingTasks,
            completionPercent: completionPercent,
          ),
          const SizedBox(height: 24),

          _buildSectionTitle('Reading Performance'),
          const SizedBox(height: 16),
          _buildReadingPerformanceGrid(cs),
          const SizedBox(height: 12),
          _buildAccuracyGrid(cs),

          if (_totalQuizzes > 0) ...[
            const SizedBox(height: 32),
            _buildSectionTitle('Quiz Progress'),
            const SizedBox(height: 16),
            _QuizProgressCard(
              totalQuizzes: _totalQuizzes,
              completedQuizzes: _completedQuizzes,
              quizAverage: _quizAverage,
            ),
          ],

          const SizedBox(height: 32),
          _buildSectionTitle('Progress Summary'),
          const SizedBox(height: 16),
          _ProgressSummaryCard(
            readingLevel: _readingLevel,
            completionPercent: completionPercent,
            totalQuizzes: _totalQuizzes,
            quizAverage: _quizAverage,
          ),

          if (_totalTasks == 0 && _totalQuizzes == 0) ...[
            const SizedBox(height: 32),
            _EmptyStateCard(
              icon: Icons.timeline,
              title: 'No progress data yet',
              subtitle: 'Complete reading tasks to track progress',
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Row _buildReadingPerformanceGrid(ColorScheme cs) {
    final accuracy =
        _totalCorrect + _totalWrong > 0
            ? '${((_totalCorrect / (_totalCorrect + _totalWrong)) * 100).toInt()}%'
            : '0%';

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Accuracy',
            accuracy,
            Icons.flag,
            Colors.blue.shade600,
            Colors.blue.shade50,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Tasks',
            '$_totalTasks',
            Icons.book,
            cs.primary,
            cs.primary.withOpacity(0.05),
          ),
        ),
      ],
    );
  }

  Row _buildAccuracyGrid(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Correct',
            '$_totalCorrect',
            Icons.check_circle,
            Colors.green.shade600,
            Colors.green.shade50,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Needs Review',
            '$_totalWrong',
            Icons.warning,
            Colors.orange.shade600,
            Colors.orange.shade50,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Tab: Quiz Scores
  // -------------------------------------------------------------------------

  Widget _buildQuizScoresTab() {
    if (_quizSubmissions.isEmpty) {
      return _EmptyStateCard.centered(
        icon: Icons.quiz_outlined,
        title: 'No quiz submissions yet',
        subtitle: 'Completed quizzes will appear here',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        itemCount: _quizSubmissions.length,
        itemBuilder:
            (_, i) => _QuizSubmissionTile(submission: _quizSubmissions[i]),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab: Reading Grades
  // -------------------------------------------------------------------------

  Widget _buildReadingGradesTab() {
    if (readingGrades.isEmpty) {
      return _EmptyStateCard.centered(
        icon: Icons.book_outlined,
        title: 'No reading grades yet',
        subtitle: 'Reading task grades will appear here',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        itemCount: readingGrades.length,
        itemBuilder: (_, i) => _ReadingGradeTile(grade: readingGrades[i]),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab: Reports
  // -------------------------------------------------------------------------

  Widget _buildReportsTab() {
    final cs = Theme.of(context).colorScheme;

    final totalReadingGrades = readingGrades.length;
    final readingAvg =
        totalReadingGrades > 0
            ? readingGrades.fold<double>(
                  0,
                  (sum, g) => sum + ((g['score'] ?? 0) as num).toDouble(),
                ) /
                totalReadingGrades
            : 0.0;

    final readingColor = _readingScoreColor(readingAvg);
    final quizColor = _percentColor(_quizAverage / 100);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PerformanceSummaryCard(
            icon: Icons.book,
            title: 'Reading Performance',
            scoreDisplay:
                readingAvg > 0 ? readingAvg.toStringAsFixed(1) : 'N/A',
            subtitle: 'out of 5',
            gradeLabel:
                readingAvg > 0
                    ? _readingScoreLabel(readingAvg)
                    : 'No Grades Yet',
            detail: 'Based on $totalReadingGrades reading assessments',
            color: readingColor,
          ),
          const SizedBox(height: 24),

          _PerformanceSummaryCard(
            icon: Icons.quiz,
            title: 'Quiz Performance',
            scoreDisplay:
                _quizAverage > 0
                    ? '${_quizAverage.toStringAsFixed(1)}%'
                    : 'N/A',
            gradeLabel:
                _quizAverage > 0
                    ? _quizAverageLabel(_quizAverage)
                    : 'No Quizzes Yet',
            detail:
                'Based on $_completedQuizzes/$_totalQuizzes completed quizzes',
            color: quizColor,
          ),
          const SizedBox(height: 24),

          _buildSectionTitle('Overall Performance Summary'),
          const SizedBox(height: 16),
          _buildReportStatsWrap(cs, totalReadingGrades, readingAvg),
          const SizedBox(height: 32),

          _buildSectionTitle('Recent Reading Assessments'),
          const SizedBox(height: 16),
          if (readingGrades.isNotEmpty)
            ...readingGrades
                .take(3)
                .map((g) => _RecentGradeListTile(grade: g, isQuiz: false))
          else
            _EmptyStateCard(
              icon: Icons.book_outlined,
              title: 'No reading assessments yet',
              subtitle: 'Graded reading tasks will appear here',
            ),
          const SizedBox(height: 32),

          _buildSectionTitle('Recent Quiz Activity'),
          const SizedBox(height: 16),
          if (_recentSubmissions.isNotEmpty)
            ..._recentSubmissions
                .take(3)
                .map((s) => _RecentGradeListTile(grade: s, isQuiz: true))
          else
            _EmptyStateCard(
              icon: Icons.quiz_outlined,
              title: 'No quiz activities yet',
              subtitle: 'Completed quizzes will appear here',
            ),

          if (readingGrades.isEmpty && _quizSubmissions.isEmpty) ...[
            const SizedBox(height: 32),
            _EmptyStateCard.centered(
              icon: Icons.assessment,
              title: 'No performance data yet',
              subtitle:
                  'Complete reading tasks and quizzes to see performance reports',
            ),
          ],
        ],
      ),
    );
  }

  Wrap _buildReportStatsWrap(
    ColorScheme cs,
    int totalReadingGrades,
    double readingAvg,
  ) {
    final accuracyStr =
        _totalCorrect + _totalWrong > 0
            ? '${((_totalCorrect / (_totalCorrect + _totalWrong)) * 100).toStringAsFixed(1)}%'
            : '0%';

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (totalReadingGrades > 0) ...[
          _reportStatCard(
            'Reading Assessments',
            '$totalReadingGrades',
            Icons.book,
            cs.primary,
          ),
          _reportStatCard(
            'Avg. Reading Score',
            '${readingAvg.toStringAsFixed(1)}/5',
            Icons.star,
            cs.primary.withOpacity(0.8),
          ),
        ] else
          _reportStatCard('Reading Assessments', '0', Icons.book, cs.outline),

        if (_totalQuizzes > 0) ...[
          _reportStatCard(
            'Total Quizzes',
            '$_totalQuizzes',
            Icons.quiz,
            cs.tertiary,
          ),
          _reportStatCard(
            'Completed Quizzes',
            '$_completedQuizzes',
            Icons.assignment_turned_in,
            cs.tertiary.withOpacity(0.8),
          ),
          _reportStatCard(
            'Quiz Average',
            '${_quizAverage.toStringAsFixed(1)}%',
            Icons.star,
            cs.secondary,
          ),
        ] else
          _reportStatCard('Total Quizzes', '0', Icons.quiz, cs.outline),

        _reportStatCard(
          'Correct Answers',
          '$_totalCorrect',
          Icons.check_circle,
          Colors.green.shade600,
        ),
        _reportStatCard(
          'Wrong Answers',
          '$_totalWrong',
          Icons.cancel,
          Colors.red.shade600,
        ),
        _reportStatCard(
          'Accuracy Rate',
          accuracyStr,
          Icons.trending_up,
          cs.primary,
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Shared UI helpers
  // -------------------------------------------------------------------------

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  /// Generic card with a gradient background.
  static Widget buildGradientCard({
    required List<Color> colors,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    Color backgroundColor,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            _CircleIcon(icon: icon, color: color, iconSize: 24, padding: 12),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            children: [
              _CircleIcon(icon: icon, color: color, iconSize: 20, padding: 8),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Private sub-widgets (each encapsulates one concern)
// ===========================================================================

/// Reusable circular icon container.
class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    required this.icon,
    required this.color,
    required this.iconSize,
    required this.padding,
  });

  final IconData icon;
  final Color color;
  final double iconSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

// ---------------------------------------------------------------------------

/// Displays the child's current reading level prominently.
class _ReadingLevelCard extends StatelessWidget {
  const _ReadingLevelCard({required this.readingLevel});

  final String readingLevel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _ChildDetailPageState.buildGradientCard(
      colors: [
        cs.primary.withOpacity(0.1),
        cs.primaryContainer.withOpacity(0.1),
      ],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.school, size: 32, color: cs.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Reading Level',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    readingLevel,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  if (readingLevel != 'Not Set') ...[
                    const SizedBox(height: 8),
                    Text(
                      'Based on reading assessments and performance',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Shows task completion with a progress bar.
class _TaskCompletionCard extends StatelessWidget {
  const _TaskCompletionCard({
    required this.completedTasks,
    required this.totalTasks,
    required this.pendingTasks,
    required this.completionPercent,
  });

  final int completedTasks;
  final int totalTasks;
  final int pendingTasks;
  final double completionPercent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Task Completion',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  '$completedTasks/$totalTasks',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearPercentIndicator(
              lineHeight: 8.0,
              percent: completionPercent,
              backgroundColor: cs.outline.withOpacity(0.2),
              progressColor: cs.primary,
              barRadius: const Radius.circular(4),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(completionPercent * 100).toInt()}% Complete',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
                Text(
                  '$pendingTasks Pending',
                  style: TextStyle(fontSize: 14, color: Colors.orange.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Shows quiz completion progress bar.
class _QuizProgressCard extends StatelessWidget {
  const _QuizProgressCard({
    required this.totalQuizzes,
    required this.completedQuizzes,
    required this.quizAverage,
  });

  final int totalQuizzes;
  final int completedQuizzes;
  final double quizAverage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                _CircleIcon(
                  icon: Icons.quiz,
                  color: cs.tertiary,
                  iconSize: 20,
                  padding: 8,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quiz Completion',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '$completedQuizzes/$totalQuizzes completed',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${quizAverage.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: cs.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearPercentIndicator(
              lineHeight: 6.0,
              percent: (completedQuizzes / totalQuizzes).clamp(0.0, 1.0),
              backgroundColor: cs.outline.withOpacity(0.2),
              progressColor: cs.tertiary,
              barRadius: const Radius.circular(3),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Key-insights summary card shown at the bottom of the Progress tab.
class _ProgressSummaryCard extends StatelessWidget {
  const _ProgressSummaryCard({
    required this.readingLevel,
    required this.completionPercent,
    required this.totalQuizzes,
    required this.quizAverage,
  });

  final String readingLevel;
  final double completionPercent;
  final int totalQuizzes;
  final double quizAverage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.insights, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Key Insights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InsightItem(
            label: 'Reading Level',
            value: readingLevel,
            icon: readingLevel != 'Not Set' ? Icons.check_circle : Icons.info,
            color: readingLevel != 'Not Set' ? Colors.green : Colors.blue,
          ),
          const SizedBox(height: 12),
          _InsightItem(
            label: 'Task Completion',
            value: '${(completionPercent * 100).toInt()}%',
            icon:
                completionPercent >= 0.7
                    ? Icons.trending_up
                    : completionPercent >= 0.3
                    ? Icons.trending_flat
                    : Icons.trending_down,
            color:
                completionPercent >= 0.7
                    ? Colors.green
                    : completionPercent >= 0.3
                    ? Colors.orange
                    : Colors.red,
          ),
          if (totalQuizzes > 0) ...[
            const SizedBox(height: 12),
            _InsightItem(
              label: 'Quiz Performance',
              value: '${quizAverage.toStringAsFixed(0)}%',
              icon:
                  quizAverage >= 75
                      ? Icons.star
                      : quizAverage >= 50
                      ? Icons.check_circle
                      : Icons.warning,
              color:
                  quizAverage >= 75
                      ? Colors.green
                      : quizAverage >= 50
                      ? Colors.orange
                      : Colors.red,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// A single row in the Key Insights section.
class _InsightItem extends StatelessWidget {
  const _InsightItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        _CircleIcon(icon: icon, color: color, iconSize: 16, padding: 6),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withOpacity(0.8),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Large summary card (reading or quiz performance) shown in the Reports tab.
class _PerformanceSummaryCard extends StatelessWidget {
  const _PerformanceSummaryCard({
    required this.icon,
    required this.title,
    required this.scoreDisplay,
    this.subtitle,
    required this.gradeLabel,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String scoreDisplay;
  final String? subtitle;
  final String gradeLabel;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _ChildDetailPageState.buildGradientCard(
      colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              scoreDisplay,
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 16,
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                gradeLabel,
                style: TextStyle(
                  fontSize: 18,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Expandable tile for a single quiz submission in the Quiz Scores tab.
class _QuizSubmissionTile extends StatelessWidget {
  const _QuizSubmissionTile({required this.submission});

  final Map<String, dynamic> submission;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final quizTitle = submission['quiz_title'] as String? ?? 'Quiz';
    final score = (submission['score'] ?? 0).toDouble();
    final maxScore = (submission['max_score'] ?? 0).toDouble();
    final scorePercent = maxScore > 0 ? score / maxScore : 0.0;
    final scoreColor = _percentColor(scorePercent);
    final scoreIcon =
        scorePercent >= 0.8
            ? Icons.star
            : scorePercent >= 0.6
            ? Icons.check_circle
            : Icons.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          childrenPadding: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16,
          ),
          leading: _CircleIcon(
            icon: scoreIcon,
            color: scoreColor,
            iconSize: 22,
            padding: 10,
          ),
          title: Text(
            quizTitle,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: cs.onSurface,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              LinearPercentIndicator(
                lineHeight: 6.0,
                percent: scorePercent.clamp(0.0, 1.0),
                backgroundColor: cs.outline.withOpacity(0.2),
                progressColor: scoreColor,
                barRadius: const Radius.circular(3),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              Text(
                '${(scorePercent * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${score.toInt()}/${maxScore.toInt()}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: scoreColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.expand_more, color: cs.outline),
            ],
          ),
          children: [
            if (submission['submitted_at'] != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: cs.outline),
                    const SizedBox(width: 8),
                    Text(
                      'Submitted: ${_formatDateTime(submission['submitted_at'] as String?)}',
                      style: TextStyle(
                        color: cs.outline,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
}

// ---------------------------------------------------------------------------

/// Expandable tile for a single reading grade in the Reading Grades tab.
class _ReadingGradeTile extends StatefulWidget {
  const _ReadingGradeTile({required this.grade});

  final Map<String, dynamic> grade;

  @override
  State<_ReadingGradeTile> createState() => _ReadingGradeTileState();
}

class _ReadingGradeTileState extends State<_ReadingGradeTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grade = widget.grade;

    final title = (grade['title'] as String?) ?? 'Reading Task';
    final description = (grade['description'] as String?) ?? '';
    final score = ((grade['score'] ?? 0) as num).toDouble();
    final percent = (score / _kMaxReadingScore).clamp(0.0, 1.0);
    final gradedBy = (grade['graded_by_name'] as String?) ?? 'Teacher';
    final gradedAtStr = grade['graded_at'] as String?;
    final teacherComments = (grade['teacher_comments'] as String?) ?? '';
    final gradedAt =
        gradedAtStr != null ? DateTime.tryParse(gradedAtStr)?.toLocal() : null;

    final fullStars = score.floor();
    final hasHalfStar = (score - fullStars) >= 0.5;

    final color = _readingScoreColor(score);
    final icon =
        score >= 4
            ? Icons.star
            : score >= 3
            ? Icons.check_circle
            : score >= 2
            ? Icons.info
            : Icons.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
          onExpansionChanged: (v) => setState(() => _isExpanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          childrenPadding: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16,
          ),
          leading: _CircleIcon(
            icon: icon,
            color: color,
            iconSize: 22,
            padding: 10,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: cs.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  gradedBy != 'N/A'
                      ? _StarRatingBadge(
                        score: score,
                        fullStars: fullStars,
                        hasHalfStar: hasHalfStar,
                        color: color,
                      )
                      : _NotGradedBadge(),
                ],
              ),
              const SizedBox(height: 8),
              if (gradedBy != 'N/A')
                LinearPercentIndicator(
                  lineHeight: 6.0,
                  percent: percent,
                  backgroundColor: cs.outline.withOpacity(0.2),
                  progressColor: color,
                  barRadius: const Radius.circular(3),
                  padding: EdgeInsets.zero,
                )
              else
                const SizedBox(height: 6),
            ],
          ),
          trailing: Icon(
            _isExpanded ? Icons.expand_less : Icons.expand_more,
            size: 24,
            color: cs.outline,
          ),
          children: [
            _ReadingGradeExpandedContent(
              score: score,
              percent: percent,
              fullStars: fullStars,
              hasHalfStar: hasHalfStar,
              description: description,
              gradedBy: gradedBy,
              gradedAt: gradedAt,
              gradedAtStr: gradedAtStr,
              teacherComments: teacherComments,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Star-rating badge used in the reading grade tile header.
class _StarRatingBadge extends StatelessWidget {
  const _StarRatingBadge({
    required this.score,
    required this.fullStars,
    required this.hasHalfStar,
    required this.color,
  });

  final double score;
  final int fullStars;
  final bool hasHalfStar;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(5, (i) {
            if (i < fullStars) return Icon(Icons.star, size: 16, color: color);
            if (i == fullStars && hasHalfStar)
              return Icon(Icons.star_half, size: 16, color: color);
            return Icon(
              Icons.star_border,
              size: 16,
              color: cs.outline.withOpacity(0.4),
            );
          }),
          const SizedBox(width: 4),
          Text(
            '${score.toStringAsFixed(1)}/5',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotGradedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: outline.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Not Yet Graded',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: outline,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// The expanded section inside a reading grade tile.
class _ReadingGradeExpandedContent extends StatelessWidget {
  const _ReadingGradeExpandedContent({
    required this.score,
    required this.percent,
    required this.fullStars,
    required this.hasHalfStar,
    required this.description,
    required this.gradedBy,
    required this.gradedAt,
    required this.gradedAtStr,
    required this.teacherComments,
    required this.color,
  });

  final double score;
  final double percent;
  final int fullStars;
  final bool hasHalfStar;
  final String description;
  final String gradedBy;
  final DateTime? gradedAt;
  final String? gradedAtStr;
  final String teacherComments;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gradedBy != 'N/A')
            _ScoreBreakdownRow(
              score: score,
              percent: percent,
              fullStars: fullStars,
              hasHalfStar: hasHalfStar,
              color: color,
            ),
          if (description.isNotEmpty) ...[
            _DetailLabel('Description:', cs.outline),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
            const SizedBox(height: 12),
          ],
          _IconRow(Icons.person, 'Graded by: $gradedBy', cs.outline),
          const SizedBox(height: 8),
          if (teacherComments.isNotEmpty) ...[
            _IconRow(Icons.comment, 'Comments: $teacherComments', cs.outline),
            const SizedBox(height: 8),
          ],
          if (gradedAt != null && gradedBy != 'N/A')
            _IconRow(
              Icons.access_time,
              'Graded at: ${_formatDateTime(gradedAtStr)}',
              cs.outline,
            ),
        ],
      ),
    );
  }
}

class _ScoreBreakdownRow extends StatelessWidget {
  const _ScoreBreakdownRow({
    required this.score,
    required this.percent,
    required this.fullStars,
    required this.hasHalfStar,
    required this.color,
  });

  final double score;
  final double percent;
  final int fullStars;
  final bool hasHalfStar;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reading Assessment Score',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${score.toStringAsFixed(1)} out of 5',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          Column(
            children: [
              Row(
                children: List.generate(5, (i) {
                  if (i < fullStars)
                    return Icon(Icons.star, size: 20, color: color);
                  if (i == fullStars && hasHalfStar)
                    return Icon(Icons.star_half, size: 20, color: color);
                  return Icon(
                    Icons.star_border,
                    size: 20,
                    color: cs.outline.withOpacity(0.3),
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                '${(percent * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailLabel extends StatelessWidget {
  const _DetailLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
  );
}

class _IconRow extends StatelessWidget {
  const _IconRow(this.icon, this.text, this.color);

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------

/// Compact list tile used in the Reports tab for recent items.
class _RecentGradeListTile extends StatelessWidget {
  const _RecentGradeListTile({required this.grade, required this.isQuiz});

  final Map<String, dynamic> grade;
  final bool isQuiz;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final title =
        (grade[isQuiz ? 'quiz_title' : 'title'] as String?) ??
        (isQuiz ? 'Quiz Submission' : 'Reading Assessment');
    final dateStr = grade[isQuiz ? 'submitted_at' : 'graded_at'] as String?;
    final iconColor = isQuiz ? cs.tertiary : cs.primary;

    String trailingLabel;
    Color trailingColor;

    if (isQuiz) {
      final pct =
          ((grade['score'] ?? 0) as num).toDouble() /
          ((grade['max_score'] ?? 1) as num).toDouble();
      trailingLabel = '${(pct * 100).toInt()}%';
      trailingColor = _percentColor(pct);
    } else {
      final score = ((grade['score'] ?? 0) as num).toDouble();
      trailingLabel = '$score/5';
      trailingColor = _readingScoreColor(score);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          leading: _CircleIcon(
            icon: isQuiz ? Icons.quiz : Icons.book,
            color: iconColor,
            iconSize: 20,
            padding: 10,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          subtitle:
              dateStr != null
                  ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatDateTime(dateStr),
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  )
                  : null,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: trailingColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              trailingLabel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: trailingColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Generic empty-state placeholder card.
class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  /// Wraps the card in a [Center] for full-screen empty states.
  static Widget centered({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: _EmptyStateCard(icon: icon, title: title, subtitle: subtitle),
    );
  }

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: cs.outline.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.6),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: cs.outline, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

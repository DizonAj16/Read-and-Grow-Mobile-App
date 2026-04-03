import 'package:deped_reading_app_laravel/api/supabase_auth_service.dart';
import 'package:deped_reading_app_laravel/models/student_model.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:fl_chart/fl_chart.dart';
import 'student page widgets/horizontal_card.dart';
import 'student page widgets/activity_tile.dart';
import 'student_badges_page.dart';
import 'my_grades_page.dart';

class StudentDashboardPage extends StatefulWidget {
  const StudentDashboardPage({super.key});

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  String? username;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  bool _isLoading = false;
  bool _minimumLoadingTimeElapsed = false;
  bool _dataLoaded = false;

  // Progress data
  double _averageScore = 0;
  int _completedTasks = 0;
  int _pendingTasks = 0;
  int _totalCorrect = 0;
  int _totalWrong = 0;
  DateTime? _lastUpdated;
  List<double> _recentScores = [];
  int _badgesCount = 0;
  String _levelDisplay = 'N/A';
  String _levelNumber = 'N/A';

  // Theme colors - will be updated in didChangeDependencies
  late ColorScheme _colorScheme;
  Color get _primaryColor => _colorScheme.primary;
  Color get _onPrimaryColor => _colorScheme.onPrimary;
  Color get _primaryContainer => _colorScheme.primaryContainer;
  Color get _onPrimaryContainer => _colorScheme.onPrimaryContainer;
  Color get _secondaryColor => _colorScheme.secondary;
  Color get _surfaceVariant => _colorScheme.surfaceVariant;
  Color get _surface => _colorScheme.surface;
  Color get _errorColor => _colorScheme.error;
  Color get _onSurface => _colorScheme.onSurface;
  Color get _onSurfaceVariant => _colorScheme.onSurfaceVariant;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startMinimumLoadingTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = Theme.of(context).colorScheme;
  }

  void _startMinimumLoadingTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _minimumLoadingTimeElapsed = true;
          _updateLoadingState();
        });
      }
    });
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await SupabaseAuthService.getAuthProfile();
      final profileJson = (response?['profile'] ?? {}) as Map<String, dynamic>;
      final student = Student.fromJson(profileJson);
      await student.saveToPrefs();

      if (mounted && student.username != null && student.username!.isNotEmpty) {
        setState(() => username = student.username);
      }

      await _loadProgressData();
      await _loadAssignedBadgesAndLevel();
    } catch (e) {
      debugPrint('API fetch failed: $e');
      final fallbackStudent = await Student.fromPrefs();
      if (mounted) {
        setState(() => username = fallbackStudent.username ?? '');
      }
      await _loadAssignedBadgesAndLevel();
    } finally {
      if (mounted) {
        setState(() {
          _dataLoaded = true;
          _updateLoadingState();
        });
      }
    }
  }

  Future<void> _loadProgressData() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Get student.id from students table
      final studentRow =
          await supabase
              .from('students')
              .select('id')
              .eq('id', userId)
              .maybeSingle();

      if (studentRow == null) return;
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

      final response = await supabase
          .from('student_task_progress')
          .select(
            'task_id, score, max_score, correct_answers, wrong_answers, completed, updated_at',
          )
          .eq('student_id', userId)
          .order('updated_at', ascending: false);

      if (response.isEmpty &&
          assignedTaskIds.isEmpty &&
          assignedQuizIds.isEmpty) {
        setState(() {
          _averageScore = 0;
          _completedTasks = 0;
          _pendingTasks = 0;
          _totalCorrect = 0;
          _totalWrong = 0;
          _lastUpdated = null;
          _recentScores = [];
        });
        return;
      }

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

      double totalScore = 0;
      double totalMax = 0;
      int correct = 0;
      int wrong = 0;
      DateTime? latest;

      List<double> scores = [];
      Set<String> completedTaskIds = {};
      Set<String> pendingTaskIds = {};

      for (var row in response) {
        final taskId = row['task_id'] as String?;
        if (taskId == null) continue;

        double score = (row['score'] ?? 0).toDouble();
        double maxScore = (row['max_score'] ?? 0).toDouble();

        totalScore += score;
        totalMax += maxScore;
        correct += (row['correct_answers'] ?? 0) as int;
        wrong += (row['wrong_answers'] ?? 0) as int;

        final updated = DateTime.tryParse(row['updated_at'] ?? '');
        if (updated != null) {
          if (latest == null || updated.isAfter(latest)) latest = updated;
        }

        if (maxScore > 0) scores.add(score / maxScore);

        if (row['completed'] == true) {
          completedTaskIds.add(taskId);
        } else {
          pendingTaskIds.add(taskId);
        }
      }

      Set<String> pendingTasksWithoutQuizzes =
          pendingTaskIds.where((id) => !tasksWithQuizzes.contains(id)).toSet();
      Set<String> completedTasksWithoutQuizzes =
          completedTaskIds
              .where((id) => !tasksWithQuizzes.contains(id))
              .toSet();

      int newPendingTasks = 0;
      for (var taskId in assignedTaskIds) {
        if (!completedTasksWithoutQuizzes.contains(taskId) &&
            !pendingTasksWithoutQuizzes.contains(taskId)) {
          newPendingTasks++;
        }
      }

      int newPendingQuizzes = 0;
      for (var quizId in assignedQuizIds) {
        if (!completedQuizIds.contains(quizId)) {
          newPendingQuizzes++;
        }
      }

      int totalPendingCount =
          pendingTasksWithoutQuizzes.length +
          newPendingTasks +
          newPendingQuizzes;

      int totalCompletedCount =
          completedTasksWithoutQuizzes.length + completedQuizIds.length;

      scores = scores.take(5).toList().reversed.toList();

      setState(() {
        _averageScore = totalMax > 0 ? totalScore / totalMax : 0;
        _completedTasks = totalCompletedCount;
        _pendingTasks = totalPendingCount;
        _totalCorrect = correct;
        _totalWrong = wrong;
        _lastUpdated = latest;
        _recentScores = scores;
      });
    } catch (e) {
      debugPrint('⚠️ Failed to load progress: $e');
    }
  }

  Future<void> _loadAssignedBadgesAndLevel() async {
    try {
      final supabase = Supabase.instance.client;
      final authUserId = supabase.auth.currentUser?.id;
      if (authUserId == null) return;

      final studentRow =
          await supabase
              .from('students')
              .select('id, current_reading_level_id')
              .eq('id', authUserId)
              .maybeSingle();

      if (studentRow == null) return;

      final submissions = await supabase
          .from('student_submissions')
          .select('score, max_score')
          .eq('student_id', authUserId);

      int badges = 0;
      for (final row in (submissions as List)) {
        final int score = (row['score'] ?? 0) as int;
        final int maxScore = (row['max_score'] ?? 0) as int;
        if (maxScore > 0 && score / maxScore >= 0.8) {
          badges += 1;
        }
      }

      String levelText = 'N/A';
      String levelNumberDisplay = 'N/A';
      final levelId = studentRow['current_reading_level_id'] as String?;
      if (levelId != null) {
        final levelRow =
            await supabase
                .from('reading_levels')
                .select('level_number, title')
                .eq('id', levelId)
                .maybeSingle();
        if (levelRow != null) {
          final num = levelRow['level_number'];
          final title = levelRow['title'];
          levelText =
              (num != null ? 'Level $num' : '') +
              (title != null ? ' - $title' : '');
          levelText = levelText.isEmpty ? 'N/A' : levelText;
          levelNumberDisplay = num != null ? '$num' : 'N/A';
        }
      }

      if (mounted) {
        setState(() {
          _badgesCount = badges;
          _levelDisplay = levelText;
          _levelNumber = levelNumberDisplay;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load assigned/badges/level: $e');
    }
  }

  void _updateLoadingState() {
    if (_dataLoaded && _minimumLoadingTimeElapsed) {
      _isLoading = false;
    }
  }

  Future<void> _handleRefresh() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _minimumLoadingTimeElapsed = false;
        _dataLoaded = false;
      });
    }

    _startMinimumLoadingTimer();
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final showLoading = _isLoading || !_minimumLoadingTimeElapsed;

    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child:
            showLoading
                ? Center(
                  child: Lottie.asset(
                    'assets/animation/loading_rainbow.json',
                    width: 90,
                    height: 90,
                  ),
                )
                : RefreshIndicator(
                  key: _refreshIndicatorKey,
                  onRefresh: _handleRefresh,
                  color: _primaryColor,
                  backgroundColor: _surface,
                  strokeWidth: 3.0,
                  displacement: 40.0,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20.0),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildWelcomeSection(context),
                                const SizedBox(height: 20),
                                _buildStatisticsCards(),
                                const SizedBox(height: 30),
                                _buildProgressSection(),
                                const SizedBox(height: 30),
                                _buildMyGradesCard(context),
                                const SizedBox(height: 30),
                                _buildRecentActivitiesSection(context),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      ),
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryColor.withOpacity(0.08),
            _primaryColor.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryColor.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: _primaryColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Lottie.asset(
              'assets/animation/waving_hello.json',
              height: 80,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome back,",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _primaryColor.withOpacity(0.8),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  username ?? 'Student',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Ready for today's learning adventure?",
                  style: TextStyle(
                    fontSize: 14,
                    color: _primaryColor.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.school_outlined, color: _primaryColor, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return SizedBox(
      height: 140,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          const SizedBox(width: 4),
          StudentDashboardHorizontalCard(
            title: "Completed",
            value: _completedTasks.toString(),
            gradientColors: [
              _primaryColor.withOpacity(0.9),
              _secondaryColor.withOpacity(0.8),
            ],
            icon: Icons.check_circle_outline,
            iconColor: _onPrimaryColor,
            textColor: _onPrimaryColor,
          ),
          const SizedBox(width: 16),
          StudentDashboardHorizontalCard(
            title: "Pending",
            value: _pendingTasks.toString(),
            gradientColors: [
              _primaryColor.withOpacity(0.7),
              _primaryColor.withOpacity(0.4),
            ],
            icon: Icons.pending_actions,
            iconColor: _onPrimaryColor,
            textColor: _onPrimaryColor,
          ),
          const SizedBox(width: 16),
          StudentDashboardHorizontalCard(
            title: "Badges",
            value: _badgesCount.toString(),
            gradientColors: [_secondaryColor, _secondaryColor.withOpacity(0.6)],
            icon: Icons.emoji_events_outlined,
            iconColor: _onPrimaryColor,
            textColor: _onPrimaryColor,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StudentBadgesPage()),
              );
            },
          ),
          const SizedBox(width: 16),
          StudentDashboardHorizontalCard(
            title: "Level",
            value: _levelNumber,
            gradientColors: [
              _primaryColor.withOpacity(0.6),
              _secondaryColor.withOpacity(0.4),
            ],
            icon: Icons.star_border,
            iconColor: _onPrimaryColor,
            textColor: _onPrimaryColor,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final percent = _averageScore.clamp(0, 1);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _surfaceVariant.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: _primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "Progress Overview",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Column(
                children: [
                  CircularPercentIndicator(
                    radius: 65,
                    lineWidth: 12,
                    percent: percent.toDouble(),
                    animation: true,
                    animationDuration: 1500,
                    circularStrokeCap: CircularStrokeCap.round,
                    center: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "${(percent * 100).toStringAsFixed(1)}%",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: _primaryColor,
                          ),
                        ),
                        Text(
                          "Score",
                          style: TextStyle(
                            fontSize: 12,
                            color: _primaryColor.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    progressColor: _primaryColor,
                    backgroundColor: _primaryColor.withOpacity(0.1),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          percent >= 0.7
                              ? Colors.green.withOpacity(0.1)
                              : percent >= 0.4
                              ? Colors.orange.withOpacity(0.1)
                              : _errorColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      percent >= 0.7
                          ? "Excellent! 🎯"
                          : percent >= 0.4
                          ? "Good Work ✨"
                          : "Keep Going! 💪",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            percent >= 0.7
                                ? Colors.green
                                : percent >= 0.4
                                ? Colors.orange
                                : _errorColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Performance Trend",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _primaryColor.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(height: 140, child: _buildTrendChart()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _progressStat(
                  Icons.check_circle,
                  "Completed",
                  _completedTasks.toString(),
                  Colors.green,
                ),
                _progressStat(
                  Icons.check,
                  "Correct",
                  _totalCorrect.toString(),
                  Colors.green,
                ),
                _progressStat(
                  Icons.close,
                  "Wrong",
                  _totalWrong.toString(),
                  _errorColor,
                ),
                _progressStat(
                  Icons.timer,
                  "Pending",
                  _pendingTasks.toString(),
                  Colors.orange,
                ),
              ],
            ),
          ),

          if (_lastUpdated != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.update,
                    size: 16,
                    color: _primaryColor.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Updated ${_lastUpdated!.toLocal().toString().split(' ')[0]}",
                    style: TextStyle(
                      fontSize: 12,
                      color: _primaryColor.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progressStat(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: _onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    if (_recentScores.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _primaryColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.show_chart,
                color: _primaryColor.withOpacity(0.4),
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                "No recent scores yet",
                style: TextStyle(
                  fontSize: 12,
                  color: _primaryColor.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.2,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: _primaryColor.withOpacity(0.1),
              strokeWidth: 1,
              dashArray: [3, 3],
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 0.2,
              getTitlesWidget: (value, meta) {
                if (value == 0 ||
                    value == 0.2 ||
                    value == 0.4 ||
                    value == 0.6 ||
                    value == 0.8 ||
                    value == 1.0) {
                  return Text(
                    '${(value * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: _primaryColor.withOpacity(0.6),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value >= 0 && value < _recentScores.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${value.toInt() + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        color: _primaryColor.withOpacity(0.6),
                      ),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 20,
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: _primaryColor.withOpacity(0.2), width: 1),
        ),
        lineBarsData: [
          LineChartBarData(
            spots:
                _recentScores
                    .asMap()
                    .entries
                    .map((e) => FlSpot(e.key.toDouble(), e.value))
                    .toList(),
            isCurved: true,
            color: _primaryColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: _onPrimaryColor,
                  strokeWidth: 2,
                  strokeColor: _primaryColor,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  _primaryColor.withOpacity(0.3),
                  _primaryColor.withOpacity(0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            gradient: LinearGradient(
              colors: [_primaryColor, _secondaryColor],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ],
        minY: 0,
        maxY: 1,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  'Score: ${(spot.y * 100).toStringAsFixed(1)}%',
                  TextStyle(color: _onPrimaryColor),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMyGradesCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _secondaryColor.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyGradesPage()),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_secondaryColor, _secondaryColor.withOpacity(0.7)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _onPrimaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grades & Analytics',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _onPrimaryColor,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'View detailed scores, quiz results, and performance analytics',
                          style: TextStyle(
                            fontSize: 14,
                            color: _onPrimaryColor.withOpacity(0.9),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _onPrimaryColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivitiesSection(BuildContext context) {
    final List activities = [];

    if (activities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _surfaceVariant.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.emoji_objects_outlined,
                size: 48,
                color: _primaryColor.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Learning Journey Awaits",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "Complete reading materials and quizzes to see your activities here.",
              style: TextStyle(
                fontSize: 14,
                color: _onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.history_rounded,
                color: _primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "Recent Activities",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _surface,
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children:
                activities.map((activity) {
                  return StudentDashboardActivityTile(
                    title: activity.title,
                    subtitle: activity.subtitle,
                    icon: activity.icon,
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }
}
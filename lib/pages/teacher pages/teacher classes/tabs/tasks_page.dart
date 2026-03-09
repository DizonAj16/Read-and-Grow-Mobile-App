import 'dart:async';
import 'package:deped_reading_app_laravel/api/task_service.dart';
import 'package:deped_reading_app_laravel/models/quiz_questions.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/add_quiz_screen.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/tabs/view_quiz_screen.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/tabs/essay_grading_screen.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TasksPage extends StatefulWidget {
  final String classId;

  const TasksPage({super.key, required this.classId});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage>
    with SingleTickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _allTasksFuture;
  late TabController _tabController;
  final supabase = Supabase.instance.client;
  RealtimeChannel? _quizChannel;
  RealtimeChannel? _assignmentChannel;
  RealtimeChannel? _essayChannel;

  // Sorting state
  SortOrder _currentSortOrder = SortOrder.newestFirst;
  Map<TaskType, SortOrder> _tabSortOrders = {
    TaskType.all: SortOrder.newestFirst,
    TaskType.quiz: SortOrder.newestFirst,
    TaskType.essay: SortOrder.newestFirst,
  };

  // Tab types
  final List<TaskType> _taskTypes = [
    TaskType.all,
    TaskType.quiz,
    TaskType.essay
  ];
  final List<String> _tabLabels = ['All Tasks', 'Quizzes', 'Essays'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _allTasksFuture = _fetchAllTasks();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quizChannel?.unsubscribe();
    _assignmentChannel?.unsubscribe();
    _essayChannel?.unsubscribe();
    super.dispose();
  }

  // Enhanced fetch to include both quizzes and essays
  Future<List<Map<String, dynamic>>> _fetchAllTasks() async {
    try {
      // Fetch regular quiz tasks WITH assignments
      final quizTasks = await TaskService.fetchTasksForClass(widget.classId);

      // Process quiz tasks to include assignment data
      final quizTasksWithAssignmentId = quizTasks.map((task) {
        final assignments = task['assignments'];
        final assignment = assignments is List
            ? (assignments.isNotEmpty ? assignments.first : null)
            : assignments;

        return {
          ...task,
          'assignment_id': assignment?['id'],
          'assignment_data': assignment,
          'due_date': assignment?['due_date'],
          'assignment_type': 'quiz',
          'sort_date': assignment?['assigned_date'] ?? task['tasks']?['created_at'],
        };
      }).toList();

      // Fetch essay assignments
      final essayResponse = await supabase
          .from('essay_assignments')
          .select('''
          *,
          assignments!inner(id, task_id, due_date, class_room_id, quiz_id, assignment_type, assigned_date),
          tasks!inner(title, description, created_at)
        ''')
          .eq('class_room_id', widget.classId)
          .order('created_at', ascending: false);

      final essayTasks = (essayResponse as List).map((essay) {
        return {
          'id': essay['id'],
          'title': essay['title'],
          'assignment_id': essay['assignment_id'],
          'assignment_data': essay['assignments'],
          'task_id': essay['task_id'],
          'class_room_id': essay['class_room_id'],
          'due_date': essay['assignments']?['due_date'],
          'tasks': essay['tasks'],
          'assignment_type': 'essay',
          'created_at': essay['created_at'],
          'sort_date': essay['assignments']?['created_at'] ?? essay['created_at'],
        };
      }).toList();

      // Combine all tasks
      final allTasks = [...quizTasksWithAssignmentId, ...essayTasks];
      return _sortTasks(allTasks, _currentSortOrder);
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      return [];
    }
  }

  // Sort tasks by date
  List<Map<String, dynamic>> _sortTasks(
      List<Map<String, dynamic>> tasks, SortOrder order) {
    tasks.sort((a, b) {
      final dateA = DateTime.tryParse(a['sort_date']?.toString() ?? '');
      final dateB = DateTime.tryParse(b['sort_date']?.toString() ?? '');
      
      if (dateA == null || dateB == null) return 0;
      
      if (order == SortOrder.newestFirst) {
        return dateB.compareTo(dateA);
      } else {
        return dateA.compareTo(dateB);
      }
    });
    
    return tasks;
  }

  // Filter tasks by type
  List<Map<String, dynamic>> _filterTasksByType(
      List<Map<String, dynamic>> allTasks, TaskType type) {
    if (type == TaskType.all) return allTasks;
    
    final String filterType = type == TaskType.quiz ? 'quiz' : 'essay';
    return allTasks.where((task) => task['assignment_type'] == filterType).toList();
  }

  void _setupRealtimeSubscription() {
    try {
      // Subscribe to quiz changes
      _quizChannel = supabase
          .channel(
              'quizzes_changes_${widget.classId}_${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'quizzes',
            callback: (payload) {
              debugPrint('📡 [REALTIME] Quiz deleted: ${payload.oldRecord}');
              if (mounted) _refreshTasks();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'quizzes',
            callback: (payload) {
              debugPrint('📡 [REALTIME] Quiz added: ${payload.newRecord}');
              if (mounted) _refreshTasks();
            },
          )
          .subscribe();

      // Subscribe to essay assignment changes
      _essayChannel = supabase
          .channel(
              'essays_changes_${widget.classId}_${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'essay_assignments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'class_room_id',
              value: widget.classId,
            ),
            callback: (payload) {
              debugPrint(
                  '📡 [REALTIME] Essay assignment changed: ${payload.newRecord ?? payload.oldRecord}');
              if (mounted) _refreshTasks();
            },
          )
          .subscribe();

      // Subscribe to assignment changes
      _assignmentChannel = supabase
          .channel(
              'assignments_changes_${widget.classId}_${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'assignments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'class_room_id',
              value: widget.classId,
            ),
            callback: (payload) {
              debugPrint(
                  '📡 [REALTIME] Assignment deleted: ${payload.oldRecord}');
              if (mounted) _refreshTasks();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('⚠️ [REALTIME] Error setting up subscriptions: $e');
    }
  }

  Future<void> _refreshTasks() async {
    if (mounted) {
      setState(() {
        _allTasksFuture = _fetchAllTasks();
      });
    }
  }

  // Toggle sort order
  void _toggleSortOrder() {
    setState(() {
      final currentTabType = _taskTypes[_tabController.index];
      final currentSortOrder = _tabSortOrders[currentTabType]!;
      
      // Toggle order
      final newSortOrder = currentSortOrder == SortOrder.newestFirst
          ? SortOrder.oldestFirst
          : SortOrder.newestFirst;
      
      // Update for current tab
      _tabSortOrders[currentTabType] = newSortOrder;
      _currentSortOrder = newSortOrder;
      
      // Refresh tasks with new sort order
      _allTasksFuture = _allTasksFuture.then((tasks) {
        return _sortTasks(tasks, newSortOrder);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // Header section with title and sort button
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Class Tasks',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _allTasksFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return Row(
                      children: [
                        Text(
                          _currentSortOrder == SortOrder.newestFirst
                              ? 'Newest First'
                              : 'Oldest First',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            _currentSortOrder == SortOrder.newestFirst
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: primaryColor,
                            size: 20,
                          ),
                          onPressed: _toggleSortOrder,
                          tooltip: _currentSortOrder == SortOrder.newestFirst
                              ? 'Switch to Oldest First'
                              : 'Switch to Newest First',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ],
                    );
                  }
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),

        // Tab Bar
        Material(
          color: primaryColor,
          child: TabBar(
            controller: _tabController,
            tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 13,
            ),
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            onTap: (index) {
              // Update sort order for the selected tab
              setState(() {
                _currentSortOrder = _tabSortOrders[_taskTypes[index]]!;
              });
            },
          ),
        ),

        // Main content area
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _allTasksFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: primaryColor),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Lottie.asset(
                        'assets/animation/empty.json',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Error loading tasks",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _refreshTasks,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final allTasks = snapshot.data ?? [];
              final currentTabType = _taskTypes[_tabController.index];
              final filteredTasks = _filterTasksByType(allTasks, currentTabType);

              if (filteredTasks.isEmpty) {
                return _buildEmptyView(currentTabType);
              }

              return TabBarView(
                controller: _tabController,
                children: [
                  // All Tasks Tab
                  _buildTasksList(filteredTasks, primaryColor, currentTabType),
                  
                  // Quizzes Tab
                  _buildTasksList(filteredTasks, primaryColor, currentTabType),
                  
                  // Essays Tab
                  _buildTasksList(filteredTasks, primaryColor, currentTabType),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyView(TaskType type) {
    String message = '';
    
    switch (type) {
      case TaskType.all:
        message = 'No Tasks Found';
        break;
      case TaskType.quiz:
        message = 'No Quiz Assignments';
        break;
      case TaskType.essay:
        message = 'No Essay Assignments';
        break;
    }
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/animation/empty.json',
            width: 250,
            height: 250,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            type == TaskType.all
                ? 'Create quizzes or essays to get started'
                : 'Create ${type.name} assignments to get started',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList(
    List<Map<String, dynamic>> tasks,
    Color primaryColor,
    TaskType type,
  ) {
    final primaryLight = Color.alphaBlend(
      primaryColor.withOpacity(0.1),
      Colors.white,
    );

    return RefreshIndicator(
      onRefresh: _refreshTasks,
      color: primaryColor,
      backgroundColor: Colors.white,
      child: ListView.builder(
        itemCount: tasks.length,
        padding: const EdgeInsets.only(bottom: 16),
        itemBuilder: (context, index) {
          final item = tasks[index];
          final assignmentType = item['assignment_type']?.toString() ?? 'quiz';
          final isEssay = assignmentType == 'essay';

          return _buildTaskCard(
            item,
            isEssay,
            primaryColor,
            primaryLight,
          );
        },
      ),
    );
  }

  Widget _buildTaskCard(
    Map<String, dynamic> item,
    bool isEssay,
    Color primaryColor,
    Color primaryLight,
  ) {
    final title = item['title'];
    final taskTitle = item['tasks']?['title'];
    final dueDate = item['due_date'];
    final itemId = item['id'];
    final assignmentId = item['assignment_id']?.toString();
    final assignmentData = item['assignment_data'];
    final sortDate = item['sort_date'];
    
    // Format date for display
    String formattedDate = '';
    if (sortDate != null) {
      try {
        final date = DateTime.parse(sortDate.toString());
        formattedDate = 'Created: ${date.toLocal().toString().split(' ')[0]}';
      } catch (e) {
        formattedDate = '';
      }
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isEssay ? Colors.purple.withOpacity(0.1) : primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isEssay ? Icons.edit_note : Icons.quiz,
            color: isEssay ? Colors.purple : primaryColor,
            size: 24,
          ),
        ),
        title: Text(
          title ?? taskTitle ?? 'Untitled',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // const SizedBox(height: 4),
            // Row(
            //   children: [
            //     Icon(
            //       Icons.calendar_today,
            //       size: 12,
            //       color: Colors.grey[600],
            //     ),
            //     const SizedBox(width: 4),
            //     Expanded(
            //       child: Text(
            //         dueDate != null
            //             ? "Due: ${DateTime.parse(dueDate).toLocal().toString().split(' ')[0]}"
            //             : "No due date",
            //         style: TextStyle(
            //           fontSize: 12,
            //           color: Colors.grey[600],
            //         ),
            //         overflow: TextOverflow.ellipsis,
            //       ),
            //     ),
            //   ],
            // ),
            if (formattedDate.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isEssay ? Colors.purple.withOpacity(0.1) : primaryLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isEssay
                      ? Colors.purple.withOpacity(0.3)
                      : primaryColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                isEssay ? 'Essay' : 'Quiz',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isEssay ? Colors.purple : primaryColor,
                ),
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: isEssay ? Colors.purple : primaryColor,
          ),
          onSelected: (value) {
            if (value == 'view') {
              if (isEssay) {
                _viewEssaySubmissions(assignmentId!, title);
              } else {
                _viewQuiz(itemId, title);
              }
            } else if (value == 'edit' && !isEssay) {
              // Edit only for quizzes (essays don't have edit option)
              _editQuiz(item, title);
            } else if (value == 'delete') {
              if (isEssay) {
                _deleteEssay(item, title);
              } else {
                _deleteQuiz(item, title);
              }
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(
                    isEssay ? Icons.grading : Icons.visibility,
                    color: isEssay ? Colors.purple : primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(isEssay ? 'Grade Essays' : 'View Quiz'),
                ],
              ),
            ),
            if (!isEssay) // Only show edit for quizzes
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: primaryColor, size: 20),
                    const SizedBox(width: 8),
                    const Text('Edit Quiz'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () {
          if (isEssay) {
            _viewEssaySubmissions(assignmentId!, title);
          } else {
            _viewQuiz(itemId, title);
          }
        },
      ),
    );
  }

  Future<void> _viewEssaySubmissions(String assignmentId, String? title) async {
    if (!mounted) return;

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EssayGradingScreen(
            classRoomId: widget.classId,
            assignmentId: assignmentId,
          ),
        ),
      );

      // Refresh after returning
      if (mounted) _refreshTasks();
    } catch (e) {
      debugPrint('Error navigating to essay grading: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening essay grading: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _viewQuiz(String quizId, String? quizTitle) async {
    try {
      // First try to get assignment ID
      String? assignmentId;
      try {
        final assignmentResponse = await supabase
            .from('assignments')
            .select('id')
            .eq('quiz_id', quizId)
            .eq('class_room_id', widget.classId)
            .maybeSingle()
            .catchError((_) => null);

        assignmentId = assignmentResponse?['id'] as String?;
      } catch (e) {
        debugPrint('Error getting assignment for quiz: $e');
      }

      final quizData = await TaskService.fetchQuizWithQuestions(quizId);

      if (quizData == null ||
          quizData['questions'] == null ||
          (quizData['questions'] as List).isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No questions found for this quiz.')),
          );
        }
        return;
      }

      final questions = quizData['questions'] as List<QuizQuestion>;
      final title = quizData['quiz']['title'] as String;

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuizPreviewScreen(title: title, questions: questions),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error viewing quiz: $e");
    }
  }

Future<void> _editQuiz(Map<String, dynamic> item, String? quizTitle) async {
  if (!mounted) return;

  try {
    final quizId = item['id'] as String?;
    if (quizId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Quiz ID not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading quiz data...'),
          ],
        ),
      ),
    );

    // Fetch the complete quiz data with questions using TaskService
    final quizData = await TaskService.fetchQuizWithQuestions(quizId);
    
    if (mounted) {
      Navigator.of(context).pop(); // Close loading dialog
    }
    
    if (quizData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Could not load quiz data'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Debug log to see what data we got
    debugPrint('📝 Edit Quiz Data Loaded:');
    debugPrint('  Quiz Title: ${quizData['quiz']['title']}');
    debugPrint('  Number of Questions: ${quizData['questions'].length}');
    
    // Check if questions are properly loaded
    final questions = quizData['questions'] as List<QuizQuestion>;
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      debugPrint('\nQuestion ${i + 1}:');
      debugPrint('  Text: ${q.questionText}');
      debugPrint('  Type: ${q.type}');
      debugPrint('  Question Image URL: ${q.questionImageUrl}');
      debugPrint('  Options: ${q.options}');
      debugPrint('  Correct Answer: ${q.correctAnswer}');
      if (q.optionImages != null && q.optionImages!.isNotEmpty) {
        debugPrint('  Option Images: ${q.optionImages}');
      }
    }

    // Navigate to edit screen
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddQuizScreen(
          classRoomId: widget.classId,
          quizId: quizId,
          initialQuizData: quizData,
        ),
      ),
    );

    // Refresh the tasks if the quiz was updated
    if (result == true && mounted) {
      _refreshTasks();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quiz updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e, stackTrace) {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(); // Close loading dialog
    }
    
    debugPrint('❌ Error editing quiz: $e');
    debugPrint('Stack trace: $stackTrace');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error editing quiz: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  Future<void> _deleteEssay(Map<String, dynamic> item, String? title) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Delete Essay Assignment'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${title ?? 'this essay assignment'}"?\n\n'
          'This will permanently delete:\n'
          '• The essay assignment\n'
          '• All essay questions\n'
          '• All student submissions and responses\n'
          '• All task materials related to this task\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Get assignment ID from the item
      final assignmentId = item['assignment_id'] as String?;
      final essayId = item['id'] as String?;
      final taskId = item['task_id'] as String?;

      if (assignmentId == null) {
        throw Exception('No assignment ID found for this essay');
      }

      debugPrint('\n=== COLLECTING ESSAY RELATED DATA FOR DELETION ===');
      debugPrint('Assignment ID: $assignmentId');
      debugPrint('Essay ID: $essayId');
      debugPrint('Task ID: $taskId');

      // 1. First, get all related data for deletion

      // Get essay questions for this essay assignment
      List<Map<String, dynamic>> essayQuestions = [];
      if (essayId != null) {
        essayQuestions = await supabase
            .from('essay_questions')
            .select('id')
            .eq('essay_assignment_id', essayId);
        debugPrint('Found ${essayQuestions.length} essay questions to delete');
      }

      // Get student essay responses for this assignment
      final essayResponses = await supabase
          .from('student_essay_responses')
          .select('id')
          .eq('assignment_id', assignmentId);
      debugPrint(
          'Found ${essayResponses.length} student essay responses to delete');

      // Get student submissions for this assignment
      final submissions = await supabase
          .from('student_submissions')
          .select('id')
          .eq('assignment_id', assignmentId);
      debugPrint('Found ${submissions.length} student submissions to delete');

      // Get task materials for this task (if task exists)
      List<Map<String, dynamic>> taskMaterials = [];
      if (taskId != null) {
        taskMaterials = await supabase
            .from('task_materials')
            .select('id')
            .eq('task_id', taskId);
        debugPrint('Found ${taskMaterials.length} task materials to delete');
      }

      debugPrint('=== STARTING ESSAY DELETION PROCESS ===\n');

      // 2. Delete in reverse order

      // a. Delete student essay responses
      if (essayResponses.isNotEmpty) {
        debugPrint('Deleting student essay responses...');
        await supabase
            .from('student_essay_responses')
            .delete()
            .eq('assignment_id', assignmentId);
        debugPrint('✓ Deleted student essay responses');
      }

      // b. Delete essay questions
      if (essayQuestions.isNotEmpty && essayId != null) {
        debugPrint('Deleting essay questions...');
        await supabase
            .from('essay_questions')
            .delete()
            .eq('essay_assignment_id', essayId);
        debugPrint('✓ Deleted essay questions');
      }

      // c. Delete student submissions
      if (submissions.isNotEmpty) {
        debugPrint('Deleting student submissions...');
        await supabase
            .from('student_submissions')
            .delete()
            .eq('assignment_id', assignmentId);
        debugPrint('✓ Deleted student submissions');
      }

      // d. Delete task materials
      if (taskMaterials.isNotEmpty && taskId != null) {
        debugPrint('Deleting task materials...');
        await supabase.from('task_materials').delete().eq('task_id', taskId);
        debugPrint('✓ Deleted task materials');
      }

      // e. Delete essay assignment
      if (essayId != null) {
        debugPrint('Deleting essay assignment...');
        await supabase.from('essay_assignments').delete().eq('id', essayId);
        debugPrint('✓ Deleted essay assignment');
      }

      // f. Finally, delete the main assignment
      debugPrint('Deleting main assignment...');
      await supabase.from('assignments').delete().eq('id', assignmentId);
      debugPrint('✓ Deleted main assignment');

      debugPrint('\n=== ESSAY DELETION COMPLETE ===');

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close loading
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Essay assignment and all related data deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        _refreshTasks();
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close loading
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting essay: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error deleting essay: $e');
    }
  }

  Future<void> _deleteQuiz(Map<String, dynamic> item, String? quizTitle) async {
    if (!mounted) return;

    final primaryColor = Theme.of(context).colorScheme.primary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Delete Quiz Assignment'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${quizTitle ?? 'this quiz assignment'}"?\n\n'
          'This will permanently delete:\n'
          '• The quiz assignment\n'
          '• All quiz questions and options\n'
          '• All student submissions and responses\n'
          '• All task materials related to this task\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: primaryColor)),
    );

    try {
      // Get assignment ID from the item
      String? assignmentId = item['assignment_id'] as String?;
      final quizId = item['id'] as String?;
      final taskId = item['task_id'] as String?;

      // Debug information
      debugPrint('Deleting quiz with:');
      debugPrint('  - Quiz ID: $quizId');
      debugPrint('  - Assignment ID: $assignmentId');
      debugPrint('  - Task ID: $taskId');

      if (assignmentId == null && quizId != null) {
        // Try to find assignment by quiz_id
        debugPrint('Looking for assignment with quiz_id: $quizId');

        final assignmentResponse = await supabase
            .from('assignments')
            .select('id')
            .eq('quiz_id', quizId)
            .eq('class_room_id', widget.classId)
            .maybeSingle();

        debugPrint('Found assignment response: $assignmentResponse');
        assignmentId = assignmentResponse?['id'] as String?;
      }

      if (assignmentId == null) {
        throw Exception('No assignment found for this quiz.');
      }

      // 1. First, get all related data for deletion
      debugPrint('\n=== COLLECTING RELATED DATA FOR DELETION ===');

      // Get all quiz questions for this quiz
      final questions = await supabase
          .from('quiz_questions')
          .select('id')
          .eq('quiz_id', quizId!);

      final questionIds =
          (questions as List).map<String>((q) => q['id'] as String).toList();
      debugPrint('Found ${questionIds.length} questions to delete');

      // Get all student submissions for this assignment
      final submissions = await supabase
          .from('student_submissions')
          .select('id')
          .eq('assignment_id', assignmentId);
      debugPrint('Found ${submissions.length} student submissions to delete');

      // Get task materials for this task (if task exists)
      List<Map<String, dynamic>> taskMaterials = [];
      if (taskId != null) {
        taskMaterials = await supabase
            .from('task_materials')
            .select('id')
            .eq('task_id', taskId);
        debugPrint('Found ${taskMaterials.length} task materials to delete');
      }

      debugPrint('=== STARTING DELETION PROCESS ===\n');

      // 2. Delete in reverse order to maintain referential integrity
      // Start with the most dependent tables and work backwards

      // a. Delete question options for each question
      if (questionIds.isNotEmpty) {
        debugPrint('Deleting question options...');
        for (final questionId in questionIds) {
          await supabase
              .from('question_options')
              .delete()
              .eq('question_id', questionId);
        }
        debugPrint('✓ Deleted question options');
      }

      // b. Delete quiz questions
      if (quizId != null) {
        debugPrint('Deleting quiz questions...');
        await supabase.from('quiz_questions').delete().eq('quiz_id', quizId);
        debugPrint('✓ Deleted quiz questions');
      }

      // c. Delete student submissions
      if (submissions.isNotEmpty) {
        debugPrint('Deleting student submissions...');
        await supabase
            .from('student_submissions')
            .delete()
            .eq('assignment_id', assignmentId);
        debugPrint('✓ Deleted student submissions');
      }

      // d. Delete task materials
      if (taskMaterials.isNotEmpty && taskId != null) {
        debugPrint('Deleting task materials...');
        await supabase.from('task_materials').delete().eq('task_id', taskId);
        debugPrint('✓ Deleted task materials');
      }

      // e. Delete the quiz
      if (quizId != null) {
        debugPrint('Deleting quiz...');
        await supabase.from('quizzes').delete().eq('id', quizId);
        debugPrint('✓ Deleted quiz');
      }

      // f. Finally, delete the assignment
      debugPrint('Deleting assignment...');
      await supabase.from('assignments').delete().eq('id', assignmentId);
      debugPrint('✓ Deleted assignment');

      debugPrint('\n=== DELETION COMPLETE ===');

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Quiz assignment and all related data deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        _refreshTasks();
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting quiz: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error deleting quiz: $e');
    }
  }
}

// Enums for task types and sort order
enum TaskType { all, quiz, essay }

enum SortOrder { newestFirst, oldestFirst }

// Extension to get display name
extension TaskTypeExtension on TaskType {
  String get name {
    switch (this) {
      case TaskType.all:
        return 'All';
      case TaskType.quiz:
        return 'Quiz';
      case TaskType.essay:
        return 'Essay';
    }
  }
}
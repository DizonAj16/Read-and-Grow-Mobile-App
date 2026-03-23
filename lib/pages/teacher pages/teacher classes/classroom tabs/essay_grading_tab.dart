// Add this to your ClassDetailsPage to include an Essay Grading tab

import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/classroom%20tabs/essay_grading_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// New Essay Grading Tab Page
class EssayGradingTabPage extends StatefulWidget {
  final String classId;

  const EssayGradingTabPage({super.key, required this.classId});

  @override
  State<EssayGradingTabPage> createState() => _EssayGradingTabPageState();
}

class _EssayGradingTabPageState extends State<EssayGradingTabPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _essayAssignments = [];

  @override
  void initState() {
    super.initState();
    _loadEssayAssignments();
  }

  Future<void> _loadEssayAssignments() async {
    setState(() => _isLoading = true);
    try {
      // Get all essay assignments for this classroom
      final response = await _supabase
          .from('essay_assignments')
          .select('''
            *,
            assignments!inner(id, task_id),
            tasks!inner(title)
          ''')
          .eq('class_room_id', widget.classId)
          .order('created_at', ascending: false);

      // Cast response to List<Map<String, dynamic>>
      final responseList = response as List<dynamic>;

      // Get submission counts for each assignment
      final assignmentsWithCounts = await Future.wait(
        responseList.map((assignment) async {
          final assignmentMap = assignment as Map<String, dynamic>;
          final assignmentId = assignmentMap['assignment_id'];
          
          // Count total submissions
          final submissionsResponse = await _supabase
              .from('student_essay_responses')
              .select('id, is_graded')
              .eq('assignment_id', assignmentId);

          final submissions = submissionsResponse as List<dynamic>;
          final totalSubmissions = submissions.length;
          final gradedSubmissions = submissions
              .where((s) => (s as Map<String, dynamic>)['is_graded'] == true)
              .length;

          return {
            ...assignmentMap,
            'total_submissions': totalSubmissions,
            'graded_submissions': gradedSubmissions,
            'pending_submissions': totalSubmissions - gradedSubmissions,
          };
        }),
      );

      // Cast to List<Map<String, dynamic>>
      setState(() {
        _essayAssignments = List<Map<String, dynamic>>.from(assignmentsWithCounts);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading essay assignments: $e');
      setState(() => _isLoading = false);
    }
  }

  void _openGradingScreen(String assignmentId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EssayGradingScreen(
          classRoomId: widget.classId,
          assignmentId: assignmentId,
        ),
      ),
    ).then((_) => _loadEssayAssignments());
  }

  Widget _buildEssayCard(Map<String, dynamic> assignment) {
    final title = assignment['title']?.toString() ?? 'Untitled Essay';
    final tasks = assignment['tasks'] as Map<String, dynamic>?;
    final taskTitle = tasks?['title']?.toString() ?? 'No Task';
    final totalSubmissions = assignment['total_submissions'] as int? ?? 0;
    final gradedSubmissions = assignment['graded_submissions'] as int? ?? 0;
    final pendingSubmissions = assignment['pending_submissions'] as int? ?? 0;
    final createdAt = DateTime.tryParse(
      assignment['created_at']?.toString() ?? '',
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      child: InkWell(
        onTap: () => _openGradingScreen(assignment['assignment_id'].toString()),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.edit_note,
                      color: Colors.purple[700],
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'From: $taskTitle',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Statistics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    'Total',
                    totalSubmissions.toString(),
                    Colors.blue,
                  ),
                  _buildStatColumn(
                    'Pending',
                    pendingSubmissions.toString(),
                    Colors.orange,
                  ),
                  _buildStatColumn(
                    'Graded',
                    gradedSubmissions.toString(),
                    Colors.green,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Grading Progress',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        totalSubmissions > 0
                            ? '${(gradedSubmissions / totalSubmissions * 100).toStringAsFixed(0)}%'
                            : '0%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: totalSubmissions > 0
                          ? gradedSubmissions / totalSubmissions
                          : 0,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        gradedSubmissions == totalSubmissions && totalSubmissions > 0
                            ? Colors.green
                            : Colors.blue,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Date and action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (createdAt != null)
                    Text(
                      'Created ${_formatDate(createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  if (pendingSubmissions > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.pending_actions,
                            size: 14,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Grade Now',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (totalSubmissions > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Complete',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _essayAssignments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Essay Assignments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create essay assignments from the Info tab',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadEssayAssignments,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: _essayAssignments.length,
                    itemBuilder: (context, index) {
                      return _buildEssayCard(_essayAssignments[index]);
                    },
                  ),
                ),
    );
  }
}
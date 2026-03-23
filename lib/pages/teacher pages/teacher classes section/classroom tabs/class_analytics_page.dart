import 'dart:typed_data';
import 'package:deped_reading_app_laravel/api/classroom_analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

class ClassAnalyticsPage extends StatefulWidget {
  final String classId;
  final String teacherId;

  const ClassAnalyticsPage({
    super.key,
    required this.classId,
    required this.teacherId,
  });

  @override
  State<ClassAnalyticsPage> createState() => _ClassAnalyticsPageState();
}

class _ClassAnalyticsPageState extends State<ClassAnalyticsPage> {
  bool _isLoading = true;
  bool _hasError = false;
  Map<String, dynamic>? _analyticsData;
  final ClassroomAnalyticsService _analyticsService =
      ClassroomAnalyticsService();
  AnalyticsFilter _currentFilter = AnalyticsFilter.overall;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
  }

  Future<void> _fetchAnalyticsData() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final analytics = await _analyticsService.getClassAnalytics(
        classId: widget.classId,
        teacherId: widget.teacherId,
      );

      setState(() {
        _analyticsData = analytics;
        _isLoading = false;
      });

      // Debug log
      _debugAnalyticsData();
    } catch (e) {
      debugPrint('❌ Error fetching analytics: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _debugAnalyticsData() {
    debugPrint('=== Analytics Data Structure Debug ===');

    // Print all top-level keys
    debugPrint('Top-level keys: ${_analyticsData?.keys.toList()}');

    // Check classInfo
    final classInfo = _analyticsData?['classInfo'] ?? {};
    debugPrint('Class Info keys: ${classInfo.keys.toList()}');

    // Check studentPerformance
    final studentPerformance = _analyticsData?['studentPerformance'] ?? {};
    debugPrint('Student Performance keys: ${studentPerformance.keys.toList()}');

    // Check for students in different locations
    if (studentPerformance['allStudents'] is List) {
      final allStudents = studentPerformance['allStudents'] as List;
      debugPrint('Found allStudents list with ${allStudents.length} items');

      if (allStudents.isNotEmpty) {
        final firstStudent = allStudents.first;
        debugPrint('First allStudent keys: ${firstStudent.keys.toList()}');
        debugPrint('First allStudent data: $firstStudent');
      }
    }

    if (studentPerformance['students'] is List) {
      final students = studentPerformance['students'] as List;
      debugPrint('Found students list with ${students.length} items');
    }

    if (_analyticsData?['students'] is List) {
      final rootStudents = _analyticsData?['students'] as List;
      debugPrint('Found students in root with ${rootStudents.length} items');
    }

    // Check for top and average performers
    if (studentPerformance['topPerformingStudents'] is List) {
      final topStudents = studentPerformance['topPerformingStudents'] as List;
      debugPrint(
        'Found topPerformingStudents with ${topStudents.length} items',
      );
    }

    if (studentPerformance['averagePerformers'] is List) {
      final avgStudents = studentPerformance['averagePerformers'] as List;
      debugPrint('Found averagePerformers with ${avgStudents.length} items');
    }

    debugPrint('======================================');
  }

  void _debugStudentData() {
    final studentPerformance = _analyticsData?['studentPerformance'] ?? {};
    final allStudents = (studentPerformance['allStudents'] as List?) ?? [];

    debugPrint('=== Student Data Structure Debug ===');
    debugPrint('Student performance keys: ${studentPerformance.keys.toList()}');
    debugPrint('Number of students in allStudents: ${allStudents.length}');

    if (allStudents.isNotEmpty) {
      final firstStudent = allStudents.first;
      debugPrint('First student keys: ${firstStudent.keys.toList()}');
      debugPrint('First student data:');
      firstStudent.forEach((key, value) {
        debugPrint('  $key: $value (${value.runtimeType})');
      });
    }

    // Check for alternative student data locations
    if (_analyticsData?.containsKey('students') == true) {
      debugPrint('Found students in root analytics data');
      final rootStudents = (_analyticsData?['students'] as List?) ?? [];
      debugPrint('Root students count: ${rootStudents.length}');
    }

    debugPrint('====================================');
  }

  Future<void> _exportIndividualReport() async {
    if (_analyticsData == null) return;

    setState(() {
      _isExporting = true;
    });

    try {
      // Debug: Print the structure before generating PDF
      debugPrint('=== Before Exporting Individual Report ===');
      _debugAnalyticsData();

      final pdf = await _generateIndividualReport();
      await _saveAndOpenPdf(
        pdf,
        'individual_class_stats_${_getCurrentDateTime()}.pdf',
      );
    } catch (e) {
      debugPrint('Error exporting individual report: $e');
      _showExportError();
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  Future<void> _exportOverallReport() async {
    if (_analyticsData == null) return;

    setState(() {
      _isExporting = true;
    });

    try {
      // In a real app, you would fetch overall stats from API
      // For now, we'll use the current class data as overall
      final pdf = await _generateOverallReport();
      await _saveAndOpenPdf(
        pdf,
        'overall_class_stats_${_getCurrentDateTime()}.pdf',
      );
    } catch (e) {
      debugPrint('Error exporting overall report: $e');
      _showExportError();
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  Future<pw.Document> _generateIndividualReport() async {
    final pdf = pw.Document();
    final classInfo = _analyticsData?['classInfo'] ?? {};
    final overallStats = _analyticsData?['overallStats'] ?? {};
    final performanceBreakdown = _analyticsData?['performanceBreakdown'] ?? {};
    final studentPerformance = _analyticsData?['studentPerformance'] ?? {};

    debugPrint('📊 [PDF] Generating individual report...');

    // Add header page (PORTRAIT)
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              _buildReportHeader(context, 'Individual Class Statistics Report'),

              // Class Information
              _buildSectionHeader('Class Information'),
              pw.SizedBox(height: 10),
              _buildClassInfoTable(classInfo),

              pw.SizedBox(height: 20),

              // Overall Statistics
              _buildSectionHeader('Overall Statistics'),
              pw.SizedBox(height: 10),
              _buildOverallStatsTable(overallStats),

              pw.SizedBox(height: 20),

              // Performance Breakdown
              _buildSectionHeader('Performance Breakdown'),
              pw.SizedBox(height: 10),
              _buildPerformanceBreakdownTable(performanceBreakdown),
            ],
          );
        },
      ),
    );

    // Add detailed analytics page (PORTRAIT)
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Detailed Analytics'),
              pw.SizedBox(height: 10),
              _buildDetailedAnalytics(overallStats, performanceBreakdown),
            ],
          );
        },
      ),
    );

    // Get all students for export
    final List<Map<String, dynamic>> allStudents = _getAllStudentsForExport();

    // Add student performance details page - LANDSCAPE FORMAT
    if (allStudents.isNotEmpty) {
      // For many students, we'll split them across multiple LANDSCAPE pages
      final studentsPerPage = 15; // Adjust for landscape (more columns)
      final totalPages = (allStudents.length / studentsPerPage).ceil();

      for (int page = 0; page < totalPages; page++) {
        final startIndex = page * studentsPerPage;
        final endIndex =
            (page + 1) * studentsPerPage < allStudents.length
                ? (page + 1) * studentsPerPage
                : allStudents.length;
        final pageStudents = allStudents.sublist(startIndex, endIndex);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape, // LANDSCAPE FORMAT
            margin: const pw.EdgeInsets.all(
              20,
            ), // Smaller margins for landscape
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Title with page number
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Student Performance Details',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                        ),
                      ),
                      pw.Text(
                        'Page ${page + 1} of $totalPages',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Class: ${classInfo['name'] ?? 'Class'} • Showing students ${startIndex + 1}-$endIndex of ${allStudents.length}',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.SizedBox(height: 15),

                  // Student table for this page - OPTIMIZED FOR LANDSCAPE
                  _buildLandscapeStudentTable(pageStudents),

                  pw.SizedBox(height: 15),

                  // Summary for this page
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        _buildLandscapeSummaryBox(
                          'Avg Quiz Score',
                          '${_calculateAverageQuizScore(pageStudents).toStringAsFixed(1)}%',
                          PdfColors.blue700,
                        ),
                        _buildLandscapeSummaryBox(
                          'Avg Reading Score',
                          '${_calculateAverageReadingScore(pageStudents).toStringAsFixed(1)}/5',
                          PdfColors.purple700,
                        ),
                        _buildLandscapeSummaryBox(
                          'Avg Overall',
                          '${_calculateAverageOverallScore(pageStudents).toStringAsFixed(1)}%',
                          PdfColors.green700,
                        ),
                      ],
                    ),
                  ),

                  // Footer note
                  if (page == totalPages - 1) ...[
                    pw.SizedBox(height: 15),
                    pw.Text(
                      'Report generated on ${DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.now())}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontStyle: pw.FontStyle.italic,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      }
    } else {
      // Add a page indicating no student data (PORTRAIT)
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'No Student Data Available',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Student performance data will be available once students start participating.',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf;
  }

  // NEW: Build landscape-optimized student table
  pw.Widget _buildLandscapeStudentTable(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return pw.Text(
        'No student data available',
        style: pw.TextStyle(fontSize: 12),
      );
    }

    // Create table rows
    final List<pw.TableRow> tableRows = [];

    // Add header row - OPTIMIZED FOR LANDSCAPE
    tableRows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _buildLandscapeTableCell('No.', isHeader: true),
          _buildLandscapeTableCell('Student Name', isHeader: true),
          _buildLandscapeTableCell('Grade', isHeader: true),
          _buildLandscapeTableCell('Section', isHeader: true),
          _buildLandscapeTableCell('LRN', isHeader: true),
          _buildLandscapeTableCell('Reading Level', isHeader: true),
          _buildLandscapeTableCell('Quiz Avg', isHeader: true),
          _buildLandscapeTableCell('Reading Avg', isHeader: true),
          _buildLandscapeTableCell('Overall Score Avg', isHeader: true),
          _buildLandscapeTableCell('Quiz Tasks Progress', isHeader: true),
          _buildLandscapeTableCell('Reading Tasks Progress', isHeader: true),
          _buildLandscapeTableCell('Last Activity', isHeader: true),
        ],
      ),
    );

    // Add data rows
    for (int i = 0; i < students.length; i++) {
      final student = students[i];
      final studentNumber = (i + 1).toString();

      // Extract student data
      final studentName = _extractStudentName(student);
      final gradeLevel = _extractGradeLevel(student);
      final section = _extractSection(student);
      final lrn = _extractLRN(student);
      final readingLevel = _extractReadingLevel(student);
      final quizAvg = _extractQuizAverage(student);
      final readingAvg = _extractReadingAverage(student);
      final overallAvg = _extractOverallAverage(student);
      final quizProgress = _extractQuizTaskCompletion(student);
      final readingProgress = _extractReadingTaskCompletion(student);
      final lastActivity = _extractLastActivity(student);

      // Alternate row colors for readability
      final rowColor = i % 2 == 0 ? PdfColors.white : PdfColors.grey50;

      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: rowColor),
          children: [
            _buildLandscapeTableCell(studentNumber, isHeader: false),
            _buildLandscapeTableCell(studentName, isHeader: false),
            _buildLandscapeTableCell(gradeLevel, isHeader: false),
            _buildLandscapeTableCell(section, isHeader: false),
            _buildLandscapeTableCell(lrn, isHeader: false),
            _buildLandscapeTableCell(readingLevel, isHeader: false),
            _buildLandscapeTableCell(
              '${quizAvg.toStringAsFixed(1)}%',
              isHeader: false,
              color: _getScoreColorPdf(quizAvg),
            ),
            _buildLandscapeTableCell(
              '${readingAvg.toStringAsFixed(1)}/5',
              isHeader: false,
              color: _getReadingScoreColorPdf(readingAvg),
            ),
            _buildLandscapeTableCell(
              '${overallAvg.toStringAsFixed(1)}%',
              isHeader: false,
              color: _getScoreColorPdf(overallAvg),
            ),
            _buildLandscapeTableCell(
              '${quizProgress.toStringAsFixed(1)}%',
              isHeader: false,
              color: _getCompletionColorPdf(quizProgress),
            ),
            _buildLandscapeTableCell(
              '${readingProgress.toStringAsFixed(1)}%',
              isHeader: false,
              color: _getCompletionColorPdf(readingProgress),
            ),
            _buildLandscapeTableCell(lastActivity, isHeader: false),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.6), // No.
        1: const pw.FlexColumnWidth(2.0), // Student Name
        2: const pw.FlexColumnWidth(0.7), // Grade
        3: const pw.FlexColumnWidth(0.8), // Section
        4: const pw.FlexColumnWidth(1.5), // LRN
        5: const pw.FlexColumnWidth(1.2), // Reading Level
        6: const pw.FlexColumnWidth(0.8), // Quiz Avg
        7: const pw.FlexColumnWidth(0.8), // Reading Avg
        8: const pw.FlexColumnWidth(0.9), // Overall Score
        9: const pw.FlexColumnWidth(0.8), // Quiz Tasks
        10: const pw.FlexColumnWidth(0.8), // Reading Tasks
        11: const pw.FlexColumnWidth(1.0), // Last Activity
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: tableRows,
    );
  }

  // NEW: Build landscape-optimized table cell
  pw.Widget _buildLandscapeTableCell(
    String text, {
    bool isHeader = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 8 : 7,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? (isHeader ? PdfColors.black : PdfColors.grey800),
        ),
        textAlign: pw.TextAlign.center,
        maxLines: 3,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  // NEW: Build summary box for landscape layout
  pw.Widget _buildLandscapeSummaryBox(
    String title,
    String value,
    PdfColor color,
  ) {
    return pw.Column(
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // NEW: Helper methods for color coding in PDF
  PdfColor _getScoreColorPdf(double score) {
    if (score >= 80) return PdfColors.green;
    if (score >= 60) return PdfColors.orange;
    return PdfColors.red;
  }

  PdfColor _getReadingScoreColorPdf(double score) {
    if (score >= 4) return PdfColors.green;
    if (score >= 3) return PdfColors.orange;
    return PdfColors.red;
  }

  PdfColor _getCompletionColorPdf(double completion) {
    if (completion >= 80) return PdfColors.green;
    if (completion >= 60) return PdfColors.orange;
    return PdfColors.red;
  }

  // NEW: Calculate average reading score
  double _calculateAverageReadingScore(List<Map<String, dynamic>> students) {
    if (students.isEmpty) return 0.0;

    double total = 0.0;
    int count = 0;

    for (final student in students) {
      if (student is Map<String, dynamic>) {
        final readingScore = _extractReadingAverage(student);
        if (readingScore > 0) {
          total += readingScore;
          count++;
        }
      }
    }

    return count > 0 ? total / count : 0.0;
  }

  // NEW: Calculate average overall score
  double _calculateAverageOverallScore(List<Map<String, dynamic>> students) {
    if (students.isEmpty) return 0.0;

    double total = 0.0;
    int count = 0;

    for (final student in students) {
      if (student is Map<String, dynamic>) {
        final overallScore = _extractOverallAverage(student);
        if (overallScore > 0) {
          total += overallScore;
          count++;
        }
      }
    }

    return count > 0 ? total / count : 0.0;
  }

  // Helper method to build performance metric for PDF
  pw.Widget _buildPerformanceMetricPdf(
    String label,
    String value,
    PdfColor color,
  ) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // Helper to calculate average quiz score from students list
  double _calculateAverageQuizScore(List<dynamic> students) {
    if (students.isEmpty) return 0.0;

    double total = 0.0;
    int count = 0;

    for (final student in students) {
      if (student is Map<String, dynamic>) {
        final quizScore = _extractQuizAverage(student);
        if (quizScore > 0) {
          total += quizScore;
          count++;
        }
      }
    }

    return count > 0 ? total / count : 0.0;
  }

  // Helper to calculate average reading task completion
  double _calculateAverageReadingTaskCompletion(List<dynamic> students) {
    if (students.isEmpty) return 0.0;

    double total = 0.0;
    int count = 0;

    for (final student in students) {
      if (student is Map<String, dynamic>) {
        final readingCompletion = _extractReadingTaskCompletion(student);
        if (readingCompletion > 0) {
          total += readingCompletion;
          count++;
        }
      }
    }

    return count > 0 ? total / count : 0.0;
  }

  // Helper to count active students (with activity in last 7 days)
  int _countActiveStudents(List<dynamic> students) {
    if (students.isEmpty) return 0;

    int activeCount = 0;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));

    for (final student in students) {
      if (student is Map<String, dynamic>) {
        final lastActivityStr = _extractLastActivity(student);

        // Check if last activity indicates recent activity
        if (lastActivityStr == 'Today' ||
            lastActivityStr == 'Yesterday' ||
            lastActivityStr.contains('day') &&
                !lastActivityStr.contains('days ago')) {
          // Parse the number of days
          final daysMatch = RegExp(r'(\d+)').firstMatch(lastActivityStr);
          if (daysMatch != null) {
            final days = int.tryParse(daysMatch.group(1) ?? '');
            if (days != null && days <= 7) {
              activeCount++;
            }
          } else if (lastActivityStr == 'Today' ||
              lastActivityStr == 'Yesterday') {
            activeCount++;
          }
        }
      }
    }

    return activeCount;
  }

  List<Map<String, dynamic>> _getAllStudentsForExport() {
    final studentPerformance = _analyticsData?['studentPerformance'] ?? {};
    final allStudents = <Map<String, dynamic>>[];

    debugPrint('🔍 [Export] Getting all students for export...');
    debugPrint(
      '🔍 [Export] Student performance keys: ${studentPerformance.keys.toList()}',
    );

    // Helper function to safely cast and add students
    void addStudentsFromList(List<dynamic> studentList) {
      for (var student in studentList) {
        if (student is Map) {
          // Convert to Map<String, dynamic>
          final Map<String, dynamic> typedStudent = {};
          student.forEach((key, value) {
            if (key is String) {
              typedStudent[key] = value;
            }
          });

          if (!_containsStudent(allStudents, typedStudent)) {
            allStudents.add(typedStudent);
          }
        }
      }
    }

    // Check allStudents first
    if (studentPerformance['allStudents'] is List) {
      final students = studentPerformance['allStudents'] as List;
      debugPrint(
        '🔍 [Export] Found ${students.length} students in allStudents',
      );

      // Log each student's data structure
      for (int i = 0; i < students.length; i++) {
        final student = students[i];
        if (student is Map) {
          debugPrint('🔍 [Export] Student $i keys: ${student.keys.toList()}');
          debugPrint('🔍 [Export] Student $i data:');
          student.forEach((key, value) {
            debugPrint('    $key: $value (${value.runtimeType})');
          });
        }
      }

      addStudentsFromList(students);
      debugPrint(
        '🔍 [Export] Added ${students.length} students from allStudents',
      );
    }

    // Also check other possible sources
    final List<String> otherKeys = [
      'topPerformingStudents',
      'averagePerformers',
      'studentsWithData',
    ];

    for (final key in otherKeys) {
      if (studentPerformance[key] is List) {
        final additionalStudents = studentPerformance[key] as List;
        debugPrint(
          '🔍 [Export] Found ${additionalStudents.length} students in $key',
        );
        addStudentsFromList(additionalStudents);
      }
    }

    debugPrint(
      '🔍 [Export] Total unique students for export: ${allStudents.length}',
    );

    // Debug: Print a few students to check their fields
    final sampleCount = allStudents.length > 3 ? 3 : allStudents.length;
    for (int i = 0; i < sampleCount; i++) {
      final student = allStudents[i];
      debugPrint('🔍 [Export] === Sample Student $i ===');
      debugPrint('  Name: ${student['name']}');
      debugPrint('  Grade Level: ${student['grade_level']}');
      debugPrint('  Section: ${student['student_section']}');
      debugPrint('  LRN: ${student['student_lrn']}');
      debugPrint('  Reading Level: ${student['readingLevel']}');
      debugPrint('  Quiz Avg: ${student['quizAverage']}');
      debugPrint('  Reading Avg: ${student['readingAverage']}');
      debugPrint('  Quiz Task Rate: ${student['quizTaskCompletionRate']}');
      debugPrint(
        '  Reading Task Rate: ${student['readingTaskCompletionRate']}',
      );
      debugPrint('  Overall Score: ${student['overallScore']}');
      debugPrint('  Last Activity: ${student['lastActivity']}');
    }

    return allStudents;
  }

  bool _containsStudent(
    List<Map<String, dynamic>> students,
    Map<String, dynamic> student,
  ) {
    final studentId = student['id'];
    if (studentId == null) return false;

    for (var existing in students) {
      if (existing['id'] == studentId) {
        return true;
      }
    }
    return false;
  }

  Future<pw.Document> _generateOverallReport() async {
    final pdf = pw.Document();
    final classInfo = _analyticsData?['classInfo'] ?? {};
    final overallStats = _analyticsData?['overallStats'] ?? {};
    final performanceBreakdown = _analyticsData?['performanceBreakdown'] ?? {};
    final studentPerformance = _analyticsData?['studentPerformance'] ?? {};

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              _buildReportHeader(context, 'Overall Class Statistics Report'),

              // Summary
              _buildSectionHeader('Executive Summary'),
              pw.SizedBox(height: 10),
              _buildExecutiveSummary(overallStats, classInfo),

              pw.SizedBox(height: 20),

              // Key Metrics
              _buildSectionHeader('Key Performance Indicators'),
              pw.SizedBox(height: 10),
              _buildKPITable(overallStats),

              pw.SizedBox(height: 20),

              // Performance Analysis
              _buildSectionHeader('Performance Analysis'),
              pw.SizedBox(height: 10),
              _buildPerformanceAnalysisTable(performanceBreakdown),

              pw.SizedBox(height: 20),

              // Recommendations
              _buildSectionHeader('Recommendations & Insights'),
              pw.SizedBox(height: 10),
              _buildRecommendations(overallStats, performanceBreakdown),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  pw.Widget _buildReportHeader(pw.Context context, String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Read & Grow: Mobile App',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Analytics Report',
                  style: pw.TextStyle(fontSize: 18, color: PdfColors.grey600),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.Text(
                  DateFormat('hh:mm a').format(DateTime.now()),
                  style: pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 10),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue700,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Class: ${_analyticsData?['classInfo']?['name'] ?? 'N/A'}',
          style: pw.TextStyle(fontSize: 14),
        ),
        pw.SizedBox(height: 20),
      ],
    );
  }

  pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue800,
        ),
      ),
    );
  }

  pw.Widget _buildClassInfoTable(Map<String, dynamic> classInfo) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _buildTableCell('Field', isHeader: true),
            _buildTableCell('Value', isHeader: true),
          ],
        ),
        pw.TableRow(
          children: [
            _buildTableCell('Class Name'),
            _buildTableCell(classInfo['name']?.toString() ?? 'N/A'),
          ],
        ),
        pw.TableRow(
          children: [
            _buildTableCell('Total Students'),
            _buildTableCell('${classInfo['totalStudents'] ?? 0}'),
          ],
        ),
        if (classInfo['section'] != null) ...[
          pw.TableRow(
            children: [
              _buildTableCell('Section'),
              _buildTableCell(classInfo['section']?.toString() ?? 'N/A'),
            ],
          ),
        ],
        if (classInfo['gradeLevel'] != null) ...[
          pw.TableRow(
            children: [
              _buildTableCell('Grade Level'),
              _buildTableCell(classInfo['gradeLevel']?.toString() ?? 'N/A'),
            ],
          ),
        ],
        if (classInfo['schoolYear'] != null) ...[
          pw.TableRow(
            children: [
              _buildTableCell('School Year'),
              _buildTableCell(classInfo['schoolYear']?.toString() ?? 'N/A'),
            ],
          ),
        ],
      ],
    );
  }

  pw.Widget _buildOverallStatsTable(Map<String, dynamic> overallStats) {
    // Create two columns for better use of space
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _buildTableCell('Metric', isHeader: true),
                  _buildTableCell('Value', isHeader: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Active Students'),
                  _buildTableCell('${overallStats['activeStudents'] ?? 0}'),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Avg Quiz Score'),
                  _buildTableCell(
                    '${_safeToDouble(overallStats['averageQuizScore'] ?? 0).toStringAsFixed(1)}%',
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Avg Reading Score'),
                  _buildTableCell(
                    '${_safeToDouble(overallStats['averageReadingScore'] ?? 0).toStringAsFixed(1)}/5',
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Overall Completion'),
                  _buildTableCell(
                    '${_safeToDouble(overallStats['overallCompletionRate'] ?? 0).toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _buildTableCell('Metric', isHeader: true),
                  _buildTableCell('Value', isHeader: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Total Quizzes'),
                  _buildTableCell('${overallStats['totalQuizzesTaken'] ?? 0}'),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Graded Recordings'),
                  _buildTableCell(
                    '${overallStats['gradedRecordingsCount'] ?? 0}',
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Reading Tasks'),
                  _buildTableCell(
                    '${overallStats['completedReadingTasks'] ?? 0}/${overallStats['totalReadingTasksAssigned'] ?? 0}',
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Reading Task Rate'),
                  _buildTableCell(
                    '${_safeToDouble(overallStats['readingTaskCompletionRate'] ?? 0).toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPerformanceBreakdownTable(
    Map<String, dynamic> performanceBreakdown,
  ) {
    // Extract all performance data
    final quizPerformance = performanceBreakdown['quizPerformance'] ?? {};
    final readingPerformance = performanceBreakdown['readingPerformance'] ?? {};
    final readingTaskPerformance =
        performanceBreakdown['readingTaskPerformance'] ?? {};
    final quizTaskPerformance =
        performanceBreakdown['quizTaskPerformance'] ?? {};
    final regularTaskPerformance =
        performanceBreakdown['regularTaskPerformance'] ?? {};

    // Calculate percentages
    final quizExcellent = _safeToInt(quizPerformance['excellent'] ?? 0);
    final quizGood = _safeToInt(quizPerformance['good'] ?? 0);
    final quizAverage = _safeToInt(quizPerformance['average'] ?? 0);
    final quizNeedsPractice = _safeToInt(
      quizPerformance['needsImprovement'] ?? 0,
    );
    final totalQuizSubmissions =
        quizExcellent + quizGood + quizAverage + quizNeedsPractice;

    final readingExcellent = _safeToInt(readingPerformance['excellent'] ?? 0);
    final readingGood = _safeToInt(readingPerformance['good'] ?? 0);
    final readingAverage = _safeToInt(readingPerformance['average'] ?? 0);
    final readingNeedsPractice = _safeToInt(
      readingPerformance['needsImprovement'] ?? 0,
    );
    final totalReadingSubmissions =
        readingExcellent + readingGood + readingAverage + readingNeedsPractice;

    final completedReadingTasks = _safeToInt(
      readingTaskPerformance['completed'] ?? 0,
    );
    final totalReadingTasks = _safeToInt(readingTaskPerformance['total'] ?? 0);
    final readingTaskPercent =
        totalReadingTasks > 0
            ? ((completedReadingTasks / totalReadingTasks) * 100)
                .toStringAsFixed(1)
            : '0.0';

    final completedQuizTasks = _safeToInt(
      quizTaskPerformance['completed'] ?? 0,
    );
    final totalQuizTasks = _safeToInt(quizTaskPerformance['total'] ?? 0);
    final quizTaskPercent =
        totalQuizTasks > 0
            ? ((completedQuizTasks / totalQuizTasks) * 100).toStringAsFixed(1)
            : '0.0';

    final completedRegularTasks = _safeToInt(
      regularTaskPerformance['completed'] ?? 0,
    );
    final totalRegularTasks = _safeToInt(regularTaskPerformance['total'] ?? 0);
    final regularTaskPercent =
        totalRegularTasks > 0
            ? ((completedRegularTasks / totalRegularTasks) * 100)
                .toStringAsFixed(1)
            : '0.0';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Quiz Performance Section
        pw.Text(
          'Quiz Performance',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _buildTableCell('Rating', isHeader: true),
                _buildTableCell('Count', isHeader: true),
                _buildTableCell('Percentage', isHeader: true),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Excellent (≥80%)', isHeader: false),
                _buildTableCell('$quizExcellent', isHeader: false),
                _buildTableCell(
                  totalQuizSubmissions > 0
                      ? '${((quizExcellent / totalQuizSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Good (60-79%)', isHeader: false),
                _buildTableCell('$quizGood', isHeader: false),
                _buildTableCell(
                  totalQuizSubmissions > 0
                      ? '${((quizGood / totalQuizSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Average (40-59%)', isHeader: false),
                _buildTableCell('$quizAverage', isHeader: false),
                _buildTableCell(
                  totalQuizSubmissions > 0
                      ? '${((quizAverage / totalQuizSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Needs Practice (<40%)', isHeader: false),
                _buildTableCell('$quizNeedsPractice', isHeader: false),
                _buildTableCell(
                  totalQuizSubmissions > 0
                      ? '${((quizNeedsPractice / totalQuizSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey50),
              children: [
                _buildTableCell('Total Submissions', isHeader: true),
                _buildTableCell('$totalQuizSubmissions', isHeader: false),
                _buildTableCell('100%', isHeader: false),
              ],
            ),
          ],
        ),

        pw.SizedBox(height: 20),

        // Reading Performance Section
        pw.Text(
          'Reading Performance',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _buildTableCell('Rating', isHeader: true),
                _buildTableCell('Count', isHeader: true),
                _buildTableCell('Percentage', isHeader: true),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Excellent (≥4/5)', isHeader: false),
                _buildTableCell('$readingExcellent', isHeader: false),
                _buildTableCell(
                  totalReadingSubmissions > 0
                      ? '${((readingExcellent / totalReadingSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Good (3/5)', isHeader: false),
                _buildTableCell('$readingGood', isHeader: false),
                _buildTableCell(
                  totalReadingSubmissions > 0
                      ? '${((readingGood / totalReadingSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Average (2/5)', isHeader: false),
                _buildTableCell('$readingAverage', isHeader: false),
                _buildTableCell(
                  totalReadingSubmissions > 0
                      ? '${((readingAverage / totalReadingSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Needs Practice (<2/5)', isHeader: false),
                _buildTableCell('$readingNeedsPractice', isHeader: false),
                _buildTableCell(
                  totalReadingSubmissions > 0
                      ? '${((readingNeedsPractice / totalReadingSubmissions) * 100).toStringAsFixed(1)}%'
                      : '0.0%',
                  isHeader: false,
                ),
              ],
            ),
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey50),
              children: [
                _buildTableCell('Total Recordings', isHeader: true),
                _buildTableCell('$totalReadingSubmissions', isHeader: false),
                _buildTableCell('100%', isHeader: false),
              ],
            ),
          ],
        ),

        pw.SizedBox(height: 20),

        // Task Completion Section
        pw.Text(
          'Task Completion',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _buildTableCell('Task Type', isHeader: true),
                _buildTableCell('Completed', isHeader: true),
                _buildTableCell('Total', isHeader: true),
                _buildTableCell('Completion Rate', isHeader: true),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Reading Tasks', isHeader: false),
                _buildTableCell('$completedReadingTasks', isHeader: false),
                _buildTableCell('$totalReadingTasks', isHeader: false),
                _buildTableCell('$readingTaskPercent%', isHeader: false),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Quiz Tasks', isHeader: false),
                _buildTableCell('$completedQuizTasks', isHeader: false),
                _buildTableCell('$totalQuizTasks', isHeader: false),
                _buildTableCell('$quizTaskPercent%', isHeader: false),
              ],
            ),
            pw.TableRow(
              children: [
                _buildTableCell('Regular Tasks', isHeader: false),
                _buildTableCell('$completedRegularTasks', isHeader: false),
                _buildTableCell('$totalRegularTasks', isHeader: false),
                _buildTableCell('$regularTaskPercent%', isHeader: false),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildStudentDetailsTable(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return pw.Text(
        'No student data available',
        style: pw.TextStyle(fontSize: 12),
      );
    }

    // Create table rows manually
    final List<pw.TableRow> tableRows = [];

    // Add header row - UPDATED LAYOUT
    tableRows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _buildTableCell('Student Name', isHeader: true),
          _buildTableCell('Grade Level', isHeader: true),
          _buildTableCell('Section', isHeader: true),
          _buildTableCell('LRN', isHeader: true),
          _buildTableCell('Reading Level', isHeader: true),
          _buildTableCell('Quiz Progress', isHeader: true),
          _buildTableCell('Reading Progress', isHeader: true),
          _buildTableCell('Quiz Avg', isHeader: true),
          _buildTableCell('Reading Avg', isHeader: true),
          _buildTableCell('Overall Avg', isHeader: true),
          _buildTableCell('Overall Progress', isHeader: true),
          _buildTableCell('Last Activity', isHeader: true),
        ],
      ),
    );

    // Add data rows
    for (int i = 0; i < students.length; i++) {
      final student = students[i];

      // Extract student data using updated helper methods
      final studentName = _extractStudentName(student);
      final gradeLevel = _extractGradeLevel(student);
      final section = _extractSection(student);
      final lrn = _extractLRN(student);
      final readingLevel = _extractReadingLevel(student);
      final quizProgress = _extractQuizTaskCompletion(student);
      final readingProgress = _extractReadingTaskCompletion(student);
      final quizAvg = _extractQuizAverage(student);
      final readingAvg = _extractReadingAverage(student);
      final overallAvg = _extractOverallAverage(student);
      final overallProgress = _extractOverallProgress(student);
      final lastActivity = _extractLastActivity(student);

      // Alternate row colors for readability
      final rowColor = i % 2 == 0 ? PdfColors.white : PdfColors.grey50;

      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: rowColor),
          children: [
            _buildTableCell(studentName, isHeader: false, maxLines: 2),
            _buildTableCell(gradeLevel, isHeader: false),
            _buildTableCell(section, isHeader: false),
            _buildTableCell(lrn, isHeader: false),
            _buildTableCell(readingLevel, isHeader: false),
            _buildTableCell(
              '${quizProgress.toStringAsFixed(1)}%',
              isHeader: false,
            ),
            _buildTableCell(
              '${readingProgress.toStringAsFixed(1)}%',
              isHeader: false,
            ),
            _buildTableCell('${quizAvg.toStringAsFixed(1)}%', isHeader: false),
            _buildTableCell(
              '${readingAvg.toStringAsFixed(1)}/5',
              isHeader: false,
            ),
            _buildTableCell(
              '${overallAvg.toStringAsFixed(1)}%',
              isHeader: false,
            ),
            _buildTableCell(
              '${overallProgress.toStringAsFixed(1)}%',
              isHeader: false,
            ),
            _buildTableCell(lastActivity, isHeader: false),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.0), // Student Name
        1: const pw.FlexColumnWidth(1.0), // Grade Level
        2: const pw.FlexColumnWidth(1.0), // Section
        3: const pw.FlexColumnWidth(1.5), // LRN
        4: const pw.FlexColumnWidth(1.2), // Reading Level
        5: const pw.FlexColumnWidth(1.0), // Quiz Progress
        6: const pw.FlexColumnWidth(1.0), // Reading Progress
        7: const pw.FlexColumnWidth(0.8), // Quiz Avg
        8: const pw.FlexColumnWidth(0.8), // Reading Avg
        9: const pw.FlexColumnWidth(0.8), // Overall Avg
        10: const pw.FlexColumnWidth(1.0), // Overall Progress
        11: const pw.FlexColumnWidth(1.2), // Last Activity
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: tableRows,
    );
  }

  // UPDATED HELPER METHODS for PDF table
  String _extractStudentName(Map<String, dynamic> student) {
    return student['name']?.toString() ??
        student['student_name']?.toString() ??
        'Unknown';
  }

  String _extractGradeLevel(Map<String, dynamic> student) {
    // Check for both possible field names
    return student['grade_level']?.toString() ??
        student['student_grade']?.toString() ??
        'N/A';
  }

  String _extractSection(Map<String, dynamic> student) {
    return student['student_section']?.toString() ??
        student['section']?.toString() ??
        'N/A';
  }

  String _extractLRN(Map<String, dynamic> student) {
    return student['student_lrn']?.toString() ??
        student['lrn']?.toString() ??
        'N/A';
  }

  String _extractReadingLevel(Map<String, dynamic> student) {
    return student['readingLevel']?.toString() ??
        student['reading_level']?.toString() ??
        'Not Set';
  }

  double _extractQuizAverage(Map<String, dynamic> student) {
    return _safeToDouble(student['quizAverage'] ?? 0);
  }

  double _extractReadingAverage(Map<String, dynamic> student) {
    return _safeToDouble(student['readingAverage'] ?? 0);
  }

  double _extractOverallAverage(Map<String, dynamic> student) {
    return _safeToDouble(student['overallScore'] ?? 0);
  }

  double _extractQuizTaskCompletion(Map<String, dynamic> student) {
    return _safeToDouble(
      student['quizTaskCompletionRate'] ??
          student['quiz_task_completion_rate'] ??
          0,
    );
  }

  double _extractReadingTaskCompletion(Map<String, dynamic> student) {
    return _safeToDouble(
      student['readingTaskCompletionRate'] ??
          student['reading_task_completion_rate'] ??
          0,
    );
  }

  double _extractOverallProgress(Map<String, dynamic> student) {
    // Calculate overall progress as weighted average of quiz and reading task completion
    final quizProgress = _extractQuizTaskCompletion(student);
    final readingProgress = _extractReadingTaskCompletion(student);

    // You can adjust the weights as needed (50/50 split here)
    return (quizProgress + readingProgress) / 2;
  }

  String _extractLastActivity(Map<String, dynamic> student) {
    final lastActivity = student['lastActivity']?.toString();

    if (lastActivity == null ||
        lastActivity.isEmpty ||
        lastActivity == 'null' ||
        lastActivity == 'Never') {
      return 'Never';
    }

    return lastActivity;
  }

  pw.Widget _buildDetailedAnalytics(
    Map<String, dynamic> overallStats,
    Map<String, dynamic> performanceBreakdown,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Performance Analysis',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          _getPerformanceAnalysis(overallStats, performanceBreakdown),
          style: pw.TextStyle(fontSize: 12),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Key Insights',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Bullet(
          text:
              'Class average quiz score: ${_safeToDouble(overallStats['averageQuizScore'] ?? 0).toStringAsFixed(1)}%',
        ),
        pw.Bullet(
          text:
              'Class average reading score: ${_safeToDouble(overallStats['averageReadingScore'] ?? 0).toStringAsFixed(1)}/5',
        ),
        pw.Bullet(
          text:
              'Overall completion rate: ${_safeToDouble(overallStats['overallCompletionRate'] ?? 0).toStringAsFixed(1)}%',
        ),
        pw.Bullet(
          text:
              'Active students: ${overallStats['activeStudents'] ?? 0}/${_analyticsData?['classInfo']?['totalStudents'] ?? 0}',
        ),
      ],
    );
  }

  pw.Widget _buildExecutiveSummary(
    Map<String, dynamic> overallStats,
    Map<String, dynamic> classInfo,
  ) {
    final totalStudents = classInfo['totalStudents'] ?? 0;
    final activeStudents = overallStats['activeStudents'] ?? 0;
    final avgQuizScore = _safeToDouble(overallStats['averageQuizScore'] ?? 0);
    final avgReadingScore = _safeToDouble(
      overallStats['averageReadingScore'] ?? 0,
    );
    final completionRate = _safeToDouble(
      overallStats['overallCompletionRate'] ?? 0,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'This report provides a comprehensive overview of class performance metrics.',
          style: pw.TextStyle(fontSize: 12),
        ),
        pw.SizedBox(height: 10),
        pw.Bullet(text: 'Class Size: $totalStudents students'),
        pw.Bullet(
          text:
              'Active Engagement: $activeStudents active students (${totalStudents > 0 ? ((activeStudents / totalStudents) * 100).toStringAsFixed(1) : 0}%)',
        ),
        pw.Bullet(
          text:
              'Academic Performance: Average quiz score of ${avgQuizScore.toStringAsFixed(1)}%',
        ),
        pw.Bullet(
          text:
              'Reading Proficiency: Average reading score of ${avgReadingScore.toStringAsFixed(1)}/5',
        ),
        pw.Bullet(
          text:
              'Task Completion: Overall completion rate of ${completionRate.toStringAsFixed(1)}%',
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          _getOverallRating(avgQuizScore, avgReadingScore, completionRate),
          style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
        ),
      ],
    );
  }

  pw.Widget _buildKPITable(Map<String, dynamic> overallStats) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _buildTableCell('Key Performance Indicator', isHeader: true),
            _buildTableCell('Value', isHeader: true),
            _buildTableCell('Status', isHeader: true),
          ],
        ),
        pw.TableRow(
          children: [
            _buildTableCell('Academic Performance (Quiz)'),
            _buildTableCell(
              '${_safeToDouble(overallStats['averageQuizScore'] ?? 0).toStringAsFixed(1)}%',
            ),
            _buildTableCell(
              _getKPIScoreStatus(
                _safeToDouble(overallStats['averageQuizScore'] ?? 0),
                70,
              ),
            ),
          ],
        ),
        pw.TableRow(
          children: [
            _buildTableCell('Reading Proficiency'),
            _buildTableCell(
              '${_safeToDouble(overallStats['averageReadingScore'] ?? 0).toStringAsFixed(1)}/5',
            ),
            _buildTableCell(
              _getKPIScoreStatus(
                _safeToDouble(overallStats['averageReadingScore'] ?? 0) * 20,
                70,
              ),
            ),
          ],
        ),
        pw.TableRow(
          children: [
            _buildTableCell('Task Completion Rate'),
            _buildTableCell(
              '${_safeToDouble(overallStats['overallCompletionRate'] ?? 0).toStringAsFixed(1)}%',
            ),
            _buildTableCell(
              _getKPIScoreStatus(
                _safeToDouble(overallStats['overallCompletionRate'] ?? 0),
                75,
              ),
            ),
          ],
        ),
        pw.TableRow(
          children: [
            _buildTableCell('Student Engagement'),
            _buildTableCell(
              '${overallStats['activeStudents'] ?? 0}/${_analyticsData?['classInfo']?['totalStudents'] ?? 0}',
            ),
            _buildTableCell(
              _getEngagementStatus(
                overallStats['activeStudents'] ?? 0,
                _analyticsData?['classInfo']?['totalStudents'] ?? 0,
              ),
            ),
          ],
        ),
        pw.TableRow(
          children: [
            _buildTableCell('Reading Task Completion'),
            _buildTableCell(
              '${_safeToDouble(overallStats['readingTaskCompletionRate'] ?? 0).toStringAsFixed(1)}%',
            ),
            _buildTableCell(
              _getKPIScoreStatus(
                _safeToDouble(overallStats['readingTaskCompletionRate'] ?? 0),
                70,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildPerformanceAnalysisTable(
    Map<String, dynamic> performanceBreakdown,
  ) {
    final quizPerformance = performanceBreakdown['quizPerformance'] ?? {};
    final readingPerformance = performanceBreakdown['readingPerformance'] ?? {};

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Quiz Performance Distribution',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Excellent: ${_safeToInt(quizPerformance['excellent'] ?? 0)} | '
          'Good: ${_safeToInt(quizPerformance['good'] ?? 0)} | '
          'Average: ${_safeToInt(quizPerformance['average'] ?? 0)} | '
          'Needs Practice: ${_safeToInt(quizPerformance['needsImprovement'] ?? 0)}',
          style: pw.TextStyle(fontSize: 12),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Reading Performance Distribution',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Excellent: ${_safeToInt(readingPerformance['excellent'] ?? 0)} | '
          'Good: ${_safeToInt(readingPerformance['good'] ?? 0)} | '
          'Average: ${_safeToInt(readingPerformance['average'] ?? 0)} | '
          'Needs Practice: ${_safeToInt(readingPerformance['needsImprovement'] ?? 0)}',
          style: pw.TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  pw.Widget _buildRecommendations(
    Map<String, dynamic> overallStats,
    Map<String, dynamic> performanceBreakdown,
  ) {
    final avgQuizScore = _safeToDouble(overallStats['averageQuizScore'] ?? 0);
    final avgReadingScore = _safeToDouble(
      overallStats['averageReadingScore'] ?? 0,
    );
    final completionRate = _safeToDouble(
      overallStats['overallCompletionRate'] ?? 0,
    );
    final quizPerformance = performanceBreakdown['quizPerformance'] ?? {};
    final needsPracticeCount = _safeToInt(
      quizPerformance['needsImprovement'] ?? 0,
    );

    final recommendations = <String>[];

    if (avgQuizScore < 70) {
      recommendations.add(
        'Focus on improving quiz performance through targeted practice sessions',
      );
    }

    if (avgReadingScore < 3.0) {
      recommendations.add(
        'Implement additional reading comprehension exercises',
      );
    }

    if (completionRate < 75) {
      recommendations.add(
        'Increase student engagement through interactive tasks and reminders',
      );
    }

    if (needsPracticeCount > 0) {
      recommendations.add(
        'Provide additional support for students needing practice',
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var recommendation in recommendations)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('• ', style: pw.TextStyle(fontSize: 12)),
                pw.Expanded(
                  child: pw.Text(
                    recommendation,
                    style: pw.TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Next Steps:',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          '1. Review individual student performance reports\n'
          '2. Schedule targeted intervention sessions\n'
          '3. Monitor progress weekly\n'
          '4. Adjust teaching strategies based on analytics',
          style: pw.TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    int maxLines = 1,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.black : PdfColors.grey800,
        ),
        textAlign: pw.TextAlign.left,
        maxLines: maxLines,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  String _getPerformanceAnalysis(
    Map<String, dynamic> overallStats,
    Map<String, dynamic> performanceBreakdown,
  ) {
    final avgQuizScore = _safeToDouble(overallStats['averageQuizScore'] ?? 0);
    final avgReadingScore = _safeToDouble(
      overallStats['averageReadingScore'] ?? 0,
    );
    final completionRate = _safeToDouble(
      overallStats['overallCompletionRate'] ?? 0,
    );
    final quizPerformance = performanceBreakdown['quizPerformance'] ?? {};

    final analysis = StringBuffer();

    analysis.writeln(
      'The class shows ${avgQuizScore >= 70 ? "good" : "moderate"} academic performance with an average quiz score of ${avgQuizScore.toStringAsFixed(1)}%.',
    );

    if (avgReadingScore >= 3.5) {
      analysis.writeln(
        'Reading proficiency is strong with an average score of ${avgReadingScore.toStringAsFixed(1)}/5.',
      );
    } else if (avgReadingScore >= 2.5) {
      analysis.writeln(
        'Reading proficiency is satisfactory with an average score of ${avgReadingScore.toStringAsFixed(1)}/5.',
      );
    } else {
      analysis.writeln(
        'Reading proficiency needs improvement with an average score of ${avgReadingScore.toStringAsFixed(1)}/5.',
      );
    }

    analysis.writeln(
      'Task completion rate stands at ${completionRate.toStringAsFixed(1)}%, indicating ${completionRate >= 80
          ? "high"
          : completionRate >= 60
          ? "moderate"
          : "low"} student engagement.',
    );

    final needsPractice = _safeToInt(quizPerformance['needsImprovement'] ?? 0);
    if (needsPractice > 0) {
      analysis.writeln(
        '$needsPractice student(s) require additional practice and support.',
      );
    }

    return analysis.toString();
  }

  String _getOverallRating(
    double quizScore,
    double readingScore,
    double completionRate,
  ) {
    final score = (quizScore + (readingScore * 20) + completionRate) / 3;

    if (score >= 80)
      return 'Overall Rating: Excellent - Class is performing exceptionally well';
    if (score >= 70)
      return 'Overall Rating: Good - Class is meeting expectations';
    if (score >= 60)
      return 'Overall Rating: Satisfactory - Room for improvement';
    return 'Overall Rating: Needs Attention - Consider implementing intervention strategies';
  }

  String _getKPIScoreStatus(double score, double threshold) {
    if (score >= threshold + 10) return 'Excellent';
    if (score >= threshold) return 'Good';
    if (score >= threshold - 10) return 'Satisfactory';
    return 'Needs Improvement';
  }

  String _getEngagementStatus(int active, int total) {
    if (total == 0) return 'No Data';
    final percentage = (active / total) * 100;
    if (percentage >= 80) return 'High';
    if (percentage >= 60) return 'Moderate';
    return 'Low';
  }

  Future<void> _saveAndOpenPdf(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');

    await file.writeAsBytes(bytes);

    await OpenFile.open(file.path);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Report exported successfully: $fileName'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showExportError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to export report. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _getCurrentDateTime() {
    final now = DateTime.now();
    return DateFormat('yyyyMMdd_HHmmss').format(now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body:
          _isLoading
              ? _buildLoadingState()
              : _hasError
              ? _buildErrorState()
              : _analyticsData?['classInfo']?['totalStudents'] == 0
              ? _buildEmptyState()
              : RefreshIndicator(
                onRefresh: _fetchAnalyticsData,
                color: Theme.of(context).colorScheme.primary,
                child: _buildContent(),
              ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading Class Analytics...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onBackground,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(
            'Failed to load analytics',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onBackground,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check your connection and try again',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _fetchAnalyticsData,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            size: 80,
          ),
          const SizedBox(height: 16),
          Text(
            'No Analytics Data Yet',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onBackground,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'This class has no students enrolled yet. Add students to start seeing analytics.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchAnalyticsData,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final hasStudents = _analyticsData?['classInfo']?['totalStudents'] > 0;

    if (!hasStudents) {
      return _buildEmptyState();
    }

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 20),

              // Export Buttons
              _buildExportButtons(),
              const SizedBox(height: 20),

              // Filter Chips
              _buildFilterChips(),
              const SizedBox(height: 20),

              // Analytics Content
              if (_currentFilter == AnalyticsFilter.overall)
                _buildOverallStats(),
              if (_currentFilter == AnalyticsFilter.quizzes)
                _buildQuizAnalytics(),
              if (_currentFilter == AnalyticsFilter.reading)
                _buildReadingAnalytics(),
              if (_currentFilter == AnalyticsFilter.students)
                _buildStudentsSection(),
            ],
          ),
        ),
        if (_isExporting) _buildExportingOverlay(),
      ],
    );
  }

  Widget _buildExportButtons() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon
            Row(
              children: [
                Icon(
                  Icons.picture_as_pdf,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Export Reports',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              'Generate detailed PDF reports for analysis and record-keeping',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),

            // Export buttons in COLUMN layout
            Column(
              children: [
                // Individual Report Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportIndividualReport,
                    icon: Icon(Icons.assignment, size: 20),
                    label: Text(
                      'Individual Class Statistics Report',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Overall Report Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportOverallReport,
                    icon: Icon(Icons.assessment, size: 20),
                    label: Text(
                      'Overall Class Statistics Report',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // File naming info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceVariant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Files will be saved as:',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file,
                        size: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'individual_class_stats_[datetime].pdf',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file,
                        size: 12,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'overall_class_stats_[datetime].pdf',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Generating Report...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we prepare your PDF',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final totalStudents = _analyticsData?['classInfo']?['totalStudents'] ?? 0;
    final className = _analyticsData?['classInfo']?['name'] ?? 'Class';
    final activeStudents =
        _analyticsData?['overallStats']?['activeStudents'] ?? 0;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.analytics_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                className,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                'Class Analytics Dashboard',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Row(
                children: [
                  Text(
                    '$totalStudents Students',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$activeStudents Active',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.refresh_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: _fetchAnalyticsData,
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            label: 'Overall',
            isSelected: _currentFilter == AnalyticsFilter.overall,
            onTap:
                () => setState(() => _currentFilter = AnalyticsFilter.overall),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Quizzes',
            isSelected: _currentFilter == AnalyticsFilter.quizzes,
            onTap:
                () => setState(() => _currentFilter = AnalyticsFilter.quizzes),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Reading',
            isSelected: _currentFilter == AnalyticsFilter.reading,
            onTap:
                () => setState(() => _currentFilter = AnalyticsFilter.reading),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Students',
            isSelected: _currentFilter == AnalyticsFilter.students,
            onTap:
                () => setState(() => _currentFilter = AnalyticsFilter.students),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildOverallStats() {
    final overallStats = _analyticsData?['overallStats'] ?? {};
    final classInfo = _analyticsData?['classInfo'] ?? {};
    final performanceBreakdown = _analyticsData?['performanceBreakdown'] ?? {};
    final readingLevelDistribution =
        _analyticsData?['readingLevelDistribution'] ?? {};
    final studentPerformance = _analyticsData?['studentPerformance'] ?? {};

    final totalStudents = classInfo['totalStudents'] ?? 0;
    final activeStudents = overallStats['activeStudents'] ?? 0;
    final lastActivity = overallStats['lastActivity'] ?? '';
    final mostCommonLevel = overallStats['mostCommonReadingLevel'] ?? 'Not Set';

    // Calculate derived metrics
    final engagementRate =
        totalStudents > 0 ? (activeStudents / totalStudents * 100) : 0;
    final avgQuizScore = _safeToDouble(overallStats['averageQuizScore'] ?? 0);
    final avgReadingScore = _safeToDouble(
      overallStats['averageReadingScore'] ?? 0,
    );
    final overallCompletionRate = _safeToDouble(
      overallStats['overallCompletionRate'] ?? 0,
    );

    return SingleChildScrollView(
      child: Column(
        children: [
          // Class Performance Overview Card
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.dashboard,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              classInfo['name'] ?? 'Class',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Overall Performance Dashboard',
                              style: TextStyle(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_getOverallPerformanceRating(avgQuizScore, avgReadingScore, overallCompletionRate)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Key Performance Indicators
                  Text(
                    'Key Performance Indicators',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Responsive Grid - FIXED
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      final crossAxisCount = isWide ? 4 : 2;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: isWide ? 0.9 : 0.7,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        children: [
                          _buildKPICard(
                            title: 'Academic Performance',
                            value: '${avgQuizScore.toStringAsFixed(1)}%',
                            subtitle: 'Quiz Average',
                            color: Colors.blue,
                            icon: Icons.school,
                            trend: _getTrendIcon(avgQuizScore, 70),
                          ),
                          _buildKPICard(
                            title: 'Reading Proficiency',
                            value: '${avgReadingScore.toStringAsFixed(1)}/5',
                            subtitle: 'Reading Average',
                            color: Colors.purple,
                            icon: Icons.book,
                            trend: _getTrendIcon(avgReadingScore * 20, 70),
                          ),
                          _buildKPICard(
                            title: 'Student Engagement',
                            value: '${engagementRate.toStringAsFixed(1)}%',
                            subtitle: '$activeStudents/$totalStudents active',
                            color: Colors.green,
                            icon: Icons.group,
                            trend: _getTrendIcon(engagementRate, 60),
                          ),
                          _buildKPICard(
                            title: 'Task Completion',
                            value:
                                '${overallCompletionRate.toStringAsFixed(1)}%',
                            subtitle: 'Overall Progress',
                            color: Colors.orange,
                            icon: Icons.check_circle,
                            trend: _getTrendIcon(overallCompletionRate, 70),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Reading Level Distribution Chart
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bar_chart,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Reading Level Distribution',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Most Common: $mostCommonLevel',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 250, // Fixed height for chart
                    child: _buildReadingLevelChart(
                      readingLevelDistribution,
                      totalStudents,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Performance Trend Analysis
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.trending_up,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Performance Trend Analysis',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Performance Comparison Grid
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      return SizedBox(
                        height: isWide ? 120 : 230,
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: isWide ? 4 : 2,
                          childAspectRatio: isWide ? 1 : 0.7,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          children: [
                            _buildComparisonCard(
                              title: 'Quiz vs Reading',
                              value1: '${avgQuizScore.toStringAsFixed(1)}%',
                              label1: 'Quiz Score',
                              value2:
                                  '${(avgReadingScore * 20).toStringAsFixed(1)}%',
                              label2: 'Reading Score',
                              color1: Colors.blue,
                              color2: Colors.purple,
                            ),
                            _buildComparisonCard(
                              title: 'Engagement vs Completion',
                              value1: '${engagementRate.toStringAsFixed(1)}%',
                              label1: 'Engagement',
                              value2:
                                  '${overallCompletionRate.toStringAsFixed(1)}%',
                              label2: 'Completion',
                              color1: Colors.green,
                              color2: Colors.orange,
                            ),
                            if (isWide) ...[
                              _buildComparisonCard(
                                title: 'Active Students',
                                value1: '$activeStudents',
                                label1: 'Active',
                                value2: '$totalStudents',
                                label2: 'Total',
                                color1: Colors.teal,
                                color2: Colors.deepPurple,
                              ),
                              _buildComparisonCard(
                                title: 'Progress',
                                value1: '${avgQuizScore.toStringAsFixed(1)}%',
                                label1: 'Quiz',
                                value2:
                                    '${(avgReadingScore * 20).toStringAsFixed(1)}%',
                                label2: 'Reading',
                                color1: Colors.blue,
                                color2: Colors.purple,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Performance Insights
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📊 Performance Insights',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._getPerformanceInsights(
                              avgQuizScore,
                              avgReadingScore,
                              engagementRate,
                              overallCompletionRate,
                              mostCommonLevel,
                            )
                            .map(
                              (insight) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        insight,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Task Type Distribution
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.pie_chart,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Task Distribution Analysis',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 300, // Fixed height for chart
                    child: _buildTaskDistributionChart(overallStats),
                  ),
                ],
              ),
            ),
          ),

          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people_alt,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Student Performance Segments',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Use the fixed _buildStudentSegments method
                  if (studentPerformance['allStudents'] is List)
                    _buildStudentSegments(
                      studentPerformance['allStudents'] as List,
                    )
                  else
                    Center(
                      child: Text(
                        'No student data available',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Last Activity & Recommendations
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.update,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Recent Activity & Recommendations',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.access_time, color: Colors.blue),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Last Class Activity',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lastActivity.isEmpty
                                  ? 'No recent activity'
                                  : lastActivity,
                              style: TextStyle(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Actionable Recommendations
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Recommended Actions',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // FIXED: Calculate hasLowerLevels here
                        ..._getActionableRecommendations(
                              avgQuizScore,
                              avgReadingScore,
                              engagementRate,
                              overallCompletionRate,
                              _hasLowerReadingLevels(readingLevelDistribution),
                            )
                            .map(
                              (recommendation) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.arrow_forward,
                                        size: 12,
                                        color: Colors.green,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        recommendation,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Responsive student segments grid
  Widget _buildStudentSegmentsGrid(
    List<dynamic> students, {
    required int crossAxisCount,
    required bool isWide,
  }) {
    if (students.isEmpty) {
      return Center(
        child: Text(
          'No student data available',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Calculate segments
    int excellent = 0;
    int good = 0;
    int average = 0;
    int needsImprovement = 0;

    for (final student in students) {
      final overallScore = _safeToDouble(student['overallScore'] ?? 0);
      if (overallScore >= 80) {
        excellent++;
      } else if (overallScore >= 60) {
        good++;
      } else if (overallScore >= 40) {
        average++;
      } else {
        needsImprovement++;
      }
    }

    final segmentData = [
      {'label': 'Excellent', 'count': excellent, 'color': Colors.green},
      {'label': 'Good', 'count': good, 'color': Colors.blue},
      {'label': 'Average', 'count': average, 'color': Colors.orange},
      {
        'label': 'Needs Improvement',
        'count': needsImprovement,
        'color': Colors.red,
      },
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      childAspectRatio: isWide ? 1.3 : 1.2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children:
          segmentData.map((segment) {
            final label = segment['label'] as String;
            final count = segment['count'] as int;
            final color = segment['color'] as Color;
            final percentage =
                students.isNotEmpty ? (count / students.length * 100) : 0;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: color.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  // Helper Widgets for Overall Tab

  Widget _buildKPICard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    required IconData trend,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Icon(trend, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReadingLevelChart(
    Map<String, dynamic> distribution,
    int totalStudents,
  ) {
    final chartData =
        distribution.entries.map((entry) {
          final percentage =
              totalStudents > 0
                  ? (entry.value as int) / totalStudents * 100
                  : 0;
          return ChartData(
            entry.key,
            entry.value as int,
            _getReadingLevelColor(entry.key),
          );
        }).toList();

    return SfCartesianChart(
      primaryXAxis: CategoryAxis(
        labelStyle: const TextStyle(fontSize: 10),
        majorGridLines: const MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        labelFormat: '{value}',
        numberFormat: NumberFormat.compact(),
        majorGridLines: const MajorGridLines(width: 0),
      ),
      series: <CartesianSeries<ChartData, String>>[
        ColumnSeries<ChartData, String>(
          dataSource: chartData,
          xValueMapper: (ChartData data, _) => data.label,
          yValueMapper: (ChartData data, _) => data.value,
          pointColorMapper: (ChartData data, _) => data.color,
          dataLabelSettings: const DataLabelSettings(
            isVisible: true,
            labelAlignment: ChartDataLabelAlignment.top,
            textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          width: 0.6,
        ),
      ],
      tooltipBehavior: TooltipBehavior(
        enable: true,
        header: '',
        format: 'point.x : point.y students',
      ),
    );
  }

  Widget _buildComparisonCard({
    required String title,
    required String value1,
    required String label1,
    required String value2,
    required String label2,
    required Color color1,
    required Color color2,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value1,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      label1,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey.withOpacity(0.3),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value2,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      label2,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: 0.5,
            backgroundColor: color1.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color2),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskDistributionChart(Map<String, dynamic> overallStats) {
    final readingTasks = overallStats['totalReadingTasksAssigned'] ?? 0;
    final completedReading = overallStats['completedReadingTasks'] ?? 0;
    final quizTasks = overallStats['totalQuizTasksAssigned'] ?? 0;
    final completedQuiz = overallStats['completedQuizTasks'] ?? 0;
    final regularTasks = overallStats['totalRegularTasksAssigned'] ?? 0;
    final completedRegular = overallStats['completedRegularTasks'] ?? 0;

    final totalAssigned = readingTasks + quizTasks + regularTasks;
    final totalCompleted = completedReading + completedQuiz + completedRegular;

    final chartData = [
      ChartData('Reading Tasks', readingTasks, Colors.blue),
      ChartData('Quiz Tasks', quizTasks, Colors.green),
      ChartData('Regular Tasks', regularTasks, Colors.orange),
    ];

    final completionData = [
      ChartData('Completed', totalCompleted, Colors.green),
      ChartData('Pending', totalAssigned - totalCompleted, Colors.orange),
    ];

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: SfCircularChart(
                  title: ChartTitle(
                    text: 'Task Types',
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  legend: Legend(
                    isVisible: true,
                    overflowMode: LegendItemOverflowMode.wrap,
                    position: LegendPosition.bottom,
                    textStyle: const TextStyle(fontSize: 10),
                  ),
                  series: <CircularSeries>[
                    PieSeries<ChartData, String>(
                      dataSource: chartData,
                      xValueMapper: (ChartData data, _) => data.label,
                      yValueMapper: (ChartData data, _) => data.value,
                      pointColorMapper: (ChartData data, _) => data.color,
                      dataLabelSettings: const DataLabelSettings(
                        isVisible: true,
                        labelPosition: ChartDataLabelPosition.outside,
                        textStyle: TextStyle(fontSize: 10),
                      ),
                      radius: '70%',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SfCircularChart(
                  title: ChartTitle(
                    text: 'Completion Status',
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  series: <CircularSeries>[
                    PieSeries<ChartData, String>(
                      dataSource: completionData,
                      xValueMapper: (ChartData data, _) => data.label,
                      yValueMapper: (ChartData data, _) => data.value,
                      pointColorMapper: (ChartData data, _) => data.color,
                      dataLabelSettings: const DataLabelSettings(
                        isVisible: true,
                        labelPosition: ChartDataLabelPosition.inside,
                        textStyle: TextStyle(fontSize: 10, color: Colors.white),
                      ),
                      radius: '70%',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTaskStat(
                'Total Tasks',
                totalAssigned.toString(),
                Colors.blue,
              ),
              _buildTaskStat(
                'Completed',
                totalCompleted.toString(),
                Colors.green,
              ),
              _buildTaskStat(
                'Rate',
                '${totalAssigned > 0 ? ((totalCompleted / totalAssigned) * 100).toStringAsFixed(1) : 0}%',
                Colors.orange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // FIXED: Student Performance Segments Grid
  Widget _buildStudentSegments(List<dynamic> students) {
    if (students.isEmpty) {
      return Center(
        child: Text(
          'No student data available',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Calculate segments
    int excellent = 0;
    int good = 0;
    int average = 0;
    int needsImprovement = 0;

    for (final student in students) {
      final overallScore = _safeToDouble(student['overallScore'] ?? 0);
      if (overallScore >= 80) {
        excellent++;
      } else if (overallScore >= 60) {
        good++;
      } else if (overallScore >= 40) {
        average++;
      } else {
        needsImprovement++;
      }
    }

    final segmentData = [
      {'label': 'Excellent', 'count': excellent, 'color': Colors.green},
      {'label': 'Good', 'count': good, 'color': Colors.blue},
      {'label': 'Average', 'count': average, 'color': Colors.orange},
      {
        'label': 'Needs Improvement',
        'count': needsImprovement,
        'color': Colors.red,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final crossAxisCount = isWide ? 4 : 2;

        return SizedBox(
          height: isWide ? 120 : 250, // Adjusted height
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            childAspectRatio: isWide ? 1.8 : 1.3, // Better aspect ratio
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children:
                segmentData.map((segment) {
                  final label = segment['label'] as String;
                  final count = segment['count'] as int;
                  final color = segment['color'] as Color;
                  final percentage =
                      students.isNotEmpty ? (count / students.length * 100) : 0;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withOpacity(0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: color,
                            fontSize: isWide ? 12 : 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              count.toString(),
                              style: TextStyle(
                                fontSize: isWide ? 24 : 20,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(${percentage.toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontSize: isWide ? 14 : 12,
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: color.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  // Helper Methods for Overall Tab

  String _getOverallPerformanceRating(
    double quizScore,
    double readingScore,
    double completionRate,
  ) {
    final score = (quizScore + (readingScore * 20) + completionRate) / 3;

    if (score >= 85) return 'Excellent';
    if (score >= 75) return 'Very Good';
    if (score >= 65) return 'Good';
    if (score >= 55) return 'Fair';
    return 'Needs Attention';
  }

  IconData _getTrendIcon(double score, double threshold) {
    if (score >= threshold + 10) return Icons.trending_up;
    if (score >= threshold) return Icons.trending_flat;
    return Icons.trending_down;
  }

  Color _getReadingLevelColor(String level) {
    final levelLower = level.toLowerCase();
    if (levelLower.contains('expert')) return Colors.green;
    if (levelLower.contains('advanced')) return Colors.blue;
    if (levelLower.contains('intermediate')) return Colors.orange;
    if (levelLower.contains('beginner')) return Colors.red;
    return Colors.grey;
  }

  List<String> _getPerformanceInsights(
    double quizScore,
    double readingScore,
    double engagementRate,
    double completionRate,
    String mostCommonLevel,
  ) {
    final insights = <String>[];

    if (quizScore >= 80) {
      insights.add('Class excels in academic assessments');
    } else if (quizScore < 60) {
      insights.add('Quiz performance suggests need for academic reinforcement');
    }

    if (readingScore >= 4) {
      insights.add('Strong reading comprehension across the class');
    } else if (readingScore < 3) {
      insights.add('Reading proficiency requires focused attention');
    }

    if (engagementRate >= 80) {
      insights.add('High student engagement and participation');
    } else if (engagementRate < 60) {
      insights.add('Consider strategies to increase student engagement');
    }

    if (completionRate >= 80) {
      insights.add('Excellent task completion rate');
    } else if (completionRate < 60) {
      insights.add('Task completion could be improved with better pacing');
    }

    if (mostCommonLevel.toLowerCase().contains('advanced') ||
        mostCommonLevel.toLowerCase().contains('expert')) {
      insights.add('Majority of students at advanced reading levels');
    } else if (mostCommonLevel.toLowerCase().contains('beginner')) {
      insights.add(
        'Most students at beginner level - consider foundational support',
      );
    }

    return insights;
  }

  List<String> _getActionableRecommendations(
    double quizScore,
    double readingScore,
    double engagementRate,
    double completionRate,
    bool hasLowerLevels,
  ) {
    final recommendations = <String>[];

    if (quizScore < 70) {
      recommendations.add(
        'Implement weekly quiz reviews for challenging topics',
      );
    }

    if (readingScore < 3.5) {
      recommendations.add('Introduce daily reading comprehension exercises');
    }

    if (engagementRate < 70) {
      recommendations.add(
        'Add interactive activities to increase participation',
      );
    }

    if (completionRate < 75) {
      recommendations.add('Break down tasks into smaller, manageable steps');
    }

    if (hasLowerLevels) {
      recommendations.add(
        'Create differentiated reading groups for targeted support',
      );
    }

    if (quizScore >= 80 && readingScore >= 4) {
      recommendations.add('Challenge high performers with advanced materials');
    }

    return recommendations;
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    bool showIconBackground = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  showIconBackground
                      ? color.withOpacity(0.1)
                      : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCharts() {
    final performanceBreakdown = _analyticsData?['performanceBreakdown'] ?? {};
    final quizPerformance = performanceBreakdown['quizPerformance'] ?? {};
    final readingPerformance = performanceBreakdown['readingPerformance'] ?? {};
    final taskPerformance = performanceBreakdown['taskPerformance'] ?? {};
    final readingTaskPerformance =
        performanceBreakdown['readingTaskPerformance'] ?? {};

    return Column(
      children: [
        _buildPerformanceChart(
          title: 'Quiz Performance',
          data: [
            ChartData(
              'Excellent',
              _safeToInt(quizPerformance['excellent'] ?? 0),
              Colors.green,
            ),
            ChartData(
              'Good',
              _safeToInt(quizPerformance['good'] ?? 0),
              Colors.blue,
            ),
            ChartData(
              'Average',
              _safeToInt(quizPerformance['average'] ?? 0),
              Colors.orange,
            ),
            ChartData(
              'Needs Practice',
              _safeToInt(quizPerformance['needsImprovement'] ?? 0),
              Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildPerformanceChart(
          title: 'Reading Performance',
          data: [
            ChartData(
              'Excellent',
              _safeToInt(readingPerformance['excellent'] ?? 0),
              Colors.green,
            ),
            ChartData(
              'Good',
              _safeToInt(readingPerformance['good'] ?? 0),
              Colors.blue,
            ),
            ChartData(
              'Average',
              _safeToInt(readingPerformance['average'] ?? 0),
              Colors.orange,
            ),
            ChartData(
              'Needs Practice',
              _safeToInt(readingPerformance['needsImprovement'] ?? 0),
              Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildTaskPerformanceChart(
          title: 'Reading Task Completion',
          completed: _safeToInt(readingTaskPerformance['completed'] ?? 0),
          pending: _safeToInt(readingTaskPerformance['pending'] ?? 0),
          total: _safeToInt(readingTaskPerformance['total'] ?? 0),
        ),
      ],
    );
  }

  Widget _buildPerformanceChart({
    required String title,
    required List<ChartData> data,
  }) {
    final total = data.fold<int>(0, (sum, item) => sum + item.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: SfCircularChart(
              legend: Legend(
                isVisible: true,
                overflowMode: LegendItemOverflowMode.wrap,
                position: LegendPosition.bottom,
              ),
              series: <CircularSeries>[
                PieSeries<ChartData, String>(
                  dataSource: data,
                  xValueMapper: (ChartData data, _) => data.label,
                  yValueMapper: (ChartData data, _) => data.value,
                  pointColorMapper: (ChartData data, _) => data.color,
                  dataLabelMapper:
                      (ChartData data, _) =>
                          total > 0
                              ? '${((data.value / total) * 100).toInt()}%'
                              : '0%',
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.inside,
                    textStyle: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  radius: '70%',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskPerformanceChart({
    required String title,
    required int completed,
    required int pending,
    required int total,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: SfCircularChart(
              legend: Legend(
                isVisible: true,
                overflowMode: LegendItemOverflowMode.wrap,
                position: LegendPosition.bottom,
              ),
              series: <CircularSeries>[
                PieSeries<ChartData, String>(
                  dataSource: [
                    ChartData('Completed', completed, Colors.green),
                    ChartData('Pending', pending, Colors.orange),
                  ],
                  xValueMapper: (ChartData data, _) => data.label,
                  yValueMapper: (ChartData data, _) => data.value,
                  pointColorMapper: (ChartData data, _) => data.color,
                  dataLabelMapper:
                      (ChartData data, _) =>
                          total > 0
                              ? '${((data.value / total) * 100).toInt()}%'
                              : '0%',
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.inside,
                    textStyle: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  radius: '70%',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Total: $total',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuizAnalytics() {
    final overallStats = _analyticsData?['overallStats'] ?? {};
    final averageQuizScore = _safeToDouble(
      overallStats['averageQuizScore'] ?? 0,
    );
    final totalQuizzesTaken = overallStats['totalQuizzesTaken'] ?? 0;
    final performanceBreakdown = _analyticsData?['performanceBreakdown'] ?? {};
    final quizPerformance = performanceBreakdown['quizPerformance'] ?? {};
    final quizTaskPerformance =
        performanceBreakdown['quizTaskPerformance'] ?? {};

    final totalQuizTasksAssigned = overallStats['totalQuizTasksAssigned'] ?? 0;
    final totalCompletedQuizTasks = overallStats['completedQuizTasks'] ?? 0;
    final quizTaskCompletionRate =
        overallStats['quizTaskCompletionRate'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quiz Performance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // Average Quiz Score
          Center(
            child: Column(
              children: [
                Text(
                  averageQuizScore.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: _getScoreColor(averageQuizScore),
                  ),
                ),
                Text(
                  'Average Score',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          LinearPercentIndicator(
            lineHeight: 8,
            percent: (averageQuizScore.clamp(0, 100) / 100).toDouble(),
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            progressColor: _getScoreColor(averageQuizScore),
            barRadius: const Radius.circular(4),
            animation: true,
            animationDuration: 1000,
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getScoreRating(averageQuizScore),
                style: TextStyle(
                  color: _getScoreColor(averageQuizScore),
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$totalQuizzesTaken quizzes taken',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Quiz Task Completion (NEW SECTION)
          Text(
            'Quiz Task Completion',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          Center(
            child: Column(
              children: [
                Text(
                  '$totalCompletedQuizTasks/$totalQuizTasksAssigned',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  'Quiz Tasks Completed',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          LinearPercentIndicator(
            lineHeight: 8,
            percent: (quizTaskCompletionRate.clamp(0, 100) / 100).toDouble(),
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            progressColor: Colors.blue,
            barRadius: const Radius.circular(4),
            animation: true,
            animationDuration: 1000,
          ),
          const SizedBox(height: 8),

          Center(
            child: Text(
              '${quizTaskCompletionRate.toStringAsFixed(1)}% Completion Rate',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Quiz Performance Breakdown
          Text(
            'Quiz Performance Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Excellent',
                  value: _safeToInt(quizPerformance['excellent'] ?? 0),
                  color: Colors.green,
                  total: totalQuizzesTaken,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Good',
                  value: _safeToInt(quizPerformance['good'] ?? 0),
                  color: Colors.blue,
                  total: totalQuizzesTaken,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Average',
                  value: _safeToInt(quizPerformance['average'] ?? 0),
                  color: Colors.orange,
                  total: totalQuizzesTaken,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Needs Practice',
                  value: _safeToInt(quizPerformance['needsImprovement'] ?? 0),
                  color: Colors.red,
                  total: totalQuizzesTaken,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Quiz Task Breakdown (NEW SECTION)
          Text(
            'Quiz Task Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Completed',
                  value: _safeToInt(quizTaskPerformance['completed'] ?? 0),
                  color: Colors.blue,
                  total: _safeToInt(quizTaskPerformance['total'] ?? 0),
                  showPercentage: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Pending',
                  value: _safeToInt(quizTaskPerformance['pending'] ?? 0),
                  color: Colors.orange,
                  total: _safeToInt(quizTaskPerformance['total'] ?? 0),
                  showPercentage: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadingAnalytics() {
    final overallStats = _analyticsData?['overallStats'] ?? {};
    final averageReadingScore = _safeToDouble(
      overallStats['averageReadingScore'] ?? 0,
    );
    final gradedRecordingsCount = overallStats['gradedRecordingsCount'] ?? 0;
    final performanceBreakdown = _analyticsData?['performanceBreakdown'] ?? {};
    final readingPerformance = performanceBreakdown['readingPerformance'] ?? {};
    final readingTaskPerformance =
        performanceBreakdown['readingTaskPerformance'] ?? {};

    final totalReadingTasksAssigned =
        overallStats['totalReadingTasksAssigned'] ?? 0;
    final completedReadingTasks = overallStats['completedReadingTasks'] ?? 0;
    final readingTaskCompletionRate =
        overallStats['readingTaskCompletionRate'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reading Performance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // Average Reading Score - CENTERED
          Center(
            child: Column(
              children: [
                Text(
                  averageReadingScore.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: _getReadingScoreColor(averageReadingScore),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'out of 5',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          LinearPercentIndicator(
            lineHeight: 8,
            percent: (averageReadingScore.clamp(0, 5) / 5),
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            progressColor: _getReadingScoreColor(averageReadingScore),
            barRadius: const Radius.circular(4),
            animation: true,
            animationDuration: 1000,
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getReadingScoreRating(averageReadingScore),
                style: TextStyle(
                  color: _getReadingScoreColor(averageReadingScore),
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$gradedRecordingsCount graded recordings',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Reading Task Completion
          Text(
            'Reading Task Completion',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          Center(
            child: Column(
              children: [
                Text(
                  '$completedReadingTasks/$totalReadingTasksAssigned',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                Text(
                  'Reading Tasks Completed',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          LinearPercentIndicator(
            lineHeight: 8,
            percent: (readingTaskCompletionRate.clamp(0, 100) / 100).toDouble(),
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            progressColor: Colors.teal,
            barRadius: const Radius.circular(4),
            animation: true,
            animationDuration: 1000,
          ),
          const SizedBox(height: 8),

          Center(
            child: Text(
              '${readingTaskCompletionRate.toStringAsFixed(1)}% Completion Rate',
              style: TextStyle(
                color: Colors.teal,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Reading Performance Breakdown
          Text(
            'Reading Performance Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Excellent',
                  value: _safeToInt(readingPerformance['excellent'] ?? 0),
                  color: Colors.green,
                  total: gradedRecordingsCount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Good',
                  value: _safeToInt(readingPerformance['good'] ?? 0),
                  color: Colors.blue,
                  total: gradedRecordingsCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Average',
                  value: _safeToInt(readingPerformance['average'] ?? 0),
                  color: Colors.orange,
                  total: gradedRecordingsCount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Needs Practice',
                  value: _safeToInt(
                    readingPerformance['needsImprovement'] ?? 0,
                  ),
                  color: Colors.red,
                  total: gradedRecordingsCount,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Reading Task Breakdown
          Text(
            'Reading Task Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Completed',
                  value: _safeToInt(readingTaskPerformance['completed'] ?? 0),
                  color: Colors.teal,
                  total: _safeToInt(readingTaskPerformance['total'] ?? 0),
                  showPercentage: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPerformanceMetric(
                  label: 'Pending',
                  value: _safeToInt(readingTaskPerformance['pending'] ?? 0),
                  color: Colors.orange,
                  total: _safeToInt(readingTaskPerformance['total'] ?? 0),
                  showPercentage: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceMetric({
    required String label,
    required int value,
    required Color color,
    required int total,
    bool showPercentage = false,
  }) {
    final percentage = total > 0 ? (value / total * 100) : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (showPercentage && total > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentsSection() {
    final studentPerformance = _analyticsData?['studentPerformance'] ?? {};
    final allStudents = (studentPerformance['allStudents'] as List?) ?? [];
    final topPerformers =
        (studentPerformance['topPerformingStudents'] as List?) ?? [];
    final averagePerformers =
        (studentPerformance['averagePerformers'] as List?) ?? [];

    if (allStudents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.people_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No Student Data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Student performance data will appear here once students start participating.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student Summary Cards
          _buildStudentSummaryCards(allStudents),
          const SizedBox(height: 24),

          // Student Categories Tabs
          DefaultTabController(
            length: 3,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.1),
                    ),
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    labelColor: Theme.of(context).colorScheme.onPrimary,
                    unselectedLabelColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.emoji_events, size: 20),
                        text: 'Top Performers',
                      ),
                      Tab(
                        icon: Icon(Icons.trending_up, size: 20),
                        text: 'Average',
                      ),
                      Tab(
                        icon: Icon(Icons.people, size: 20),
                        text: 'All Students',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: TabBarView(
                    children: [
                      // Top Performers Tab
                      _buildStudentListTab(
                        students: topPerformers,
                        emptyMessage: 'No top performers yet',
                        icon: Icons.emoji_events,
                      ),
                      // Average Performers Tab
                      _buildStudentListTab(
                        students: averagePerformers,
                        emptyMessage: 'No average performers yet',
                        icon: Icons.trending_up,
                      ),
                      // All Students Tab
                      _buildStudentListTab(
                        students: allStudents,
                        emptyMessage: 'No student data available',
                        icon: Icons.people,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSummaryCards(List<dynamic> allStudents) {
    if (allStudents.isEmpty) return const SizedBox();

    // Calculate stats
    final totalStudents = allStudents.length;
    final studentsWithData =
        allStudents.where((s) {
          final hasData = s['hasData'] as bool?;
          return hasData == true;
        }).length;

    final activeStudents =
        allStudents.where((s) {
          final lastActivity = s['lastActivity'] as String?;
          return lastActivity != null &&
              lastActivity != 'Never' &&
              !lastActivity.contains('days ago');
        }).length;

    final averageQuizScore =
        allStudents.fold<double>(0, (sum, student) {
          return sum + _safeToDouble(student['quizAverage'] ?? 0);
        }) /
        totalStudents;

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.people,
            value: '$totalStudents',
            label: 'Total Students',
            color: Colors.blue,
            subtitle: '$studentsWithData with data',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.check_circle,
            value: '$activeStudents',
            label: 'Active',
            color: Colors.green,
            subtitle: 'Recently engaged',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.quiz,
            value: '${averageQuizScore.toStringAsFixed(1)}%',
            label: 'Avg Quiz Score',
            color: Colors.orange,
            subtitle: 'Class average',
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    String subtitle = '',
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentListTab({
    required List<dynamic> students,
    required String emptyMessage,
    required IconData icon,
  }) {
    if (students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: students.length,
      itemBuilder: (context, index) {
        final student = students[index];
        return _buildStudentCard(
          student,
          index == 0,
        ); // First one gets top badge
      },
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, bool isTopPerformer) {
    final quizAverage = _safeToDouble(student['quizAverage'] ?? 0);
    final readingAverage = _safeToDouble(student['readingAverage'] ?? 0);
    final readingTaskCompletionRate = _safeToDouble(
      student['readingTaskCompletionRate'] ?? 0,
    );
    final quizTaskCompletionRate = _safeToDouble(
      student['quizTaskCompletionRate'] ?? 0,
    );
    final overallScore = _safeToDouble(student['overallScore'] ?? 0);
    final profilePicture = student['profile_picture'] as String?;
    final studentName = student['name'] as String? ?? 'Student';
    final gradeLevel = _extractGradeLevel(student);
    final section = _extractSection(student);
    final lrn = _extractLRN(student);
    final readingLevel = _extractReadingLevel(student);
    final lastActivity = _extractLastActivity(student);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student Header
            Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isTopPerformer
                              ? Colors.green.withOpacity(0.5)
                              : Theme.of(
                                context,
                              ).colorScheme.outline.withOpacity(0.1),
                      width: 2,
                    ),
                  ),
                  child:
                      profilePicture != null && profilePicture.isNotEmpty
                          ? ClipOval(
                            child: Image.network(
                              profilePicture,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Text(
                                    studentName.substring(0, 1).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                          : Center(
                            child: Text(
                              studentName.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                ),
                const SizedBox(width: 12),

                // Student Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              studentName,
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isTopPerformer)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.emoji_events,
                                    size: 12,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Top Performer',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Grade $gradeLevel • Section $section • LRN: $lrn',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '📚 $readingLevel',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '📅 $lastActivity',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Performance Metrics
            Row(
              children: [
                Expanded(
                  child: _buildMetricCircle(
                    value: '${quizAverage.toStringAsFixed(0)}%',
                    label: 'Quiz Avg.',
                    color: Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildMetricCircle(
                    value: '${readingAverage.toStringAsFixed(1)}/5',
                    label: 'Reading Avg.',
                    color: Colors.purple,
                  ),
                ),
                Expanded(
                  child: _buildMetricCircle(
                    value: '${overallScore.toStringAsFixed(0)}%',
                    label: 'Overall Avg.',
                    color: Colors.blue,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress Bars
            Column(
              children: [
                _buildProgressRow(
                  'Quiz Tasks',
                  quizTaskCompletionRate,
                  Colors.blue,
                ),
                const SizedBox(height: 8),
                _buildProgressRow(
                  'Reading Tasks',
                  readingTaskCompletionRate,
                  Colors.teal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCircle({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRow(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value.clamp(0, 100) / 100,
          backgroundColor: color.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }

  Widget _buildTaskCompletionRow({
    required String label,
    required int completed,
    required int total,
    required Color color,
  }) {
    final percentage = total > 0 ? (completed / total * 100) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$completed/$total',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: total > 0 ? (completed / total) : 0,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniProgressBar(String label, double value, Color color) {
    final clampedValue = value.clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${clampedValue.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: clampedValue / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper Methods
  double _safeToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int _safeToInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _getScoreRating(double score) {
    if (score >= 80) return 'Excellent';
    if (score >= 70) return 'Very Good';
    if (score >= 60) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs Practice';
  }

  Color _getReadingScoreColor(double score) {
    if (score >= 4) return Colors.green;
    if (score >= 3) return Colors.orange;
    if (score >= 2) return Colors.orangeAccent;
    return Colors.red;
  }

  String _getReadingScoreRating(double score) {
    if (score >= 4) return 'Excellent';
    if (score >= 3) return 'Good';
    if (score >= 2) return 'Average';
    return 'Needs Practice';
  }

  Color _getCompletionColor(double completion) {
    if (completion >= 80) return Colors.green;
    if (completion >= 60) return Colors.orange;
    return Colors.red;
  }

  String _getCompletionRating(double completion) {
    if (completion >= 80) return 'High Completion';
    if (completion >= 60) return 'Moderate Completion';
    return 'Low Completion';
  }

  String _getReadingTaskRating(double completion) {
    if (completion >= 80) return 'Excellent Progress';
    if (completion >= 60) return 'Good Progress';
    if (completion >= 40) return 'Average Progress';
    return 'Needs More Practice';
  }

  bool _hasLowerReadingLevels(Map<String, dynamic> readingLevelDistribution) {
    final readingLevels = readingLevelDistribution.keys.toList();
    return readingLevels.any(
      (level) =>
          level.toLowerCase().contains('beginner') ||
          level.toLowerCase().contains('intermediate'),
    );
  }
}

// Enums and Data Classes
enum AnalyticsFilter { overall, quizzes, reading, students }

class ChartData {
  final String label;
  final int value;
  final Color color;

  ChartData(this.label, this.value, this.color);
}

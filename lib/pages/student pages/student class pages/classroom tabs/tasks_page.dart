import 'package:deped_reading_app_laravel/constants.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../api/classroom_service.dart';
import 'student_quiz_pages.dart';

class StudentTasksPage extends StatelessWidget {
  final String classId;

  const StudentTasksPage({super.key, required this.classId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue[50],
      body: Stack(
        children: [
          // Wave header
          _buildHeader(),
          // Content below header
          Padding(
            padding: const EdgeInsets.only(top: 140), // same as header height
            child: RefreshIndicator(
              onRefresh: () async {
                // Add refresh functionality here
              },
              color: Colors.blue,
              backgroundColor: Colors.white,
              child: _buildContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return ClipPath(
      clipper: WaveClipper(),
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kPrimaryColor,
              Color(0xFFB71C1C),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const SafeArea(
          child: Center(
            child: Text(
              "Lessons & Quizzes",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 20),
        Center(
          child: Text(
            "Task content goes here",
            style: TextStyle(fontSize: 18),
          ),
        ),
      ],
    );
  }
}


// ✅ StudentQuizzesPage (StatefulWidget)
class StudentQuizzesPage extends StatefulWidget {
  final String studentId;

  const StudentQuizzesPage({super.key, required this.studentId});

  @override
  State<StudentQuizzesPage> createState() => _StudentQuizzesPageState();
}

class _StudentQuizzesPageState extends State<StudentQuizzesPage> {
  List<Map<String, dynamic>> quizzes = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    final result = await ClassroomService.fetchStudentQuizzes(widget.studentId);
    setState(() {
      quizzes = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("My Quizzes")),
      body: ListView.builder(
        itemCount: quizzes.length,
        itemBuilder: (context, index) {
          final quiz = quizzes[index];
          return ListTile(
            title: Text(quiz['quiz_title']),
            subtitle: Text("Class: ${quiz['class_name']}"),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentQuizPage(
                    quizId: quiz['quiz_id'],
                    assignmentId: quiz['assignment_id'],
                    studentId: widget.studentId,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 20);
    var firstControlPoint = Offset(size.width / 4, size.height);
    var firstEndPoint = Offset(size.width / 2, size.height - 30);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );
    var secondControlPoint = Offset(
      size.width - (size.width / 4),
      size.height - 60,
    );
    var secondEndPoint = Offset(size.width, size.height - 20);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

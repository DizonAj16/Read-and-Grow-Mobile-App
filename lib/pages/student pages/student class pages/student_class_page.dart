import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:deped_reading_app_laravel/api/fun_fact_service.dart';
import 'package:deped_reading_app_laravel/api/prefs_service.dart';
import 'package:deped_reading_app_laravel/models/classroom_model.dart';
import 'widgets/class_card.dart';
import 'widgets/empty_classes_widget.dart';
import 'widgets/loading_widget.dart';

class StudentClassPage extends StatefulWidget {
  const StudentClassPage({Key? key}) : super(key: key);

  @override
  State<StudentClassPage> createState() => _StudentClassPageState();
}

class _StudentClassPageState extends State<StudentClassPage> {
  late Future<List<Classroom>> _futureClasses;
  final TextEditingController _classCodeController = TextEditingController();
  bool _isLoadingInitial = true;
  bool _isRefreshingFunFact = false;
  bool _minimumLoadingTimePassed = false;
  String _currentFunFact = "";

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  @override
  void dispose() {
    _classCodeController.dispose();
    super.dispose();
  }

  Future<void> _initializePage() async {
    _futureClasses = _loadClasses();
    await _fetchAndSetFunFact();
    _setMinimumLoadingTime(const Duration(seconds: 10));
  }

  Future<void> _fetchAndSetFunFact() async {
    try {
      final fresh = await FunFactService.getRandomFact();
      if (mounted) setState(() => _currentFunFact = fresh);
    } catch (e) {
      debugPrint("Fun fact fetch failed: $e");
    }
  }

  void _setMinimumLoadingTime(Duration duration) {
    Future.delayed(duration, () {
      if (mounted) setState(() => _minimumLoadingTimePassed = true);
    });
  }

  Future<List<Classroom>> _loadClasses() async {
    try {
      final loadedClasses = await ClassroomService.getStudentClasses();
      await _handleLoadedClasses(loadedClasses);
      return loadedClasses;
    } catch (e) {
      debugPrint("Classroom API error: $e");
      await PrefsService.clearStudentClassesFromPrefs();
      return [];
    } finally {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _handleLoadedClasses(List<Classroom> loadedClasses) async {
    if (loadedClasses.isEmpty) {
      await PrefsService.clearStudentClassesFromPrefs();
    } else {
      await PrefsService.storeStudentClassesToPrefs(loadedClasses);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _minimumLoadingTimePassed = false;
      _isLoadingInitial = true;
      _futureClasses = _loadClasses();
    });
    _setMinimumLoadingTime(const Duration(seconds: 10));
    await Future.wait([_futureClasses, _fetchAndSetFunFact()]);
    if (mounted) setState(() => _isLoadingInitial = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: colorScheme.primary,
        backgroundColor: colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            children: [const SizedBox(height: 16), _buildClassList()],
          ),
        ),
      ),
    );
  }

  Widget _buildClassList() {
    return Expanded(
      child: FutureBuilder<List<Classroom>>(
        future: _futureClasses,
        builder: (context, snapshot) {
          if (_isLoadingInitial || !_minimumLoadingTimePassed) {
            return LoadingWidget(
              currentFunFact: _currentFunFact,
              isRefreshingFunFact: _isRefreshingFunFact,
            );
          }

          if (snapshot.hasError) {
            return _ErrorWidget(errorMessage: 'Failed to load classes');
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return EmptyClassesWidget(
              onJoinClassPressed: _showJoinClassDialog,
              onRefreshPressed: _refresh,
            );
          }

          return _ClassListView(classes: snapshot.data!);
        },
      ),
    );
  }

  Future<void> _showJoinClassDialog() async {
    await showDialog(
      context: context,
      builder:
          (_) => JoinClassDialog(
            controller: _classCodeController,
            onJoinPressed: (code) => _joinClass(code),
          ),
    );
  }

  Future<void> _joinClass(String classCode) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingDialog(),
    );

    try {
      final res = await ClassroomService.joinClass(classCode);

      if (!mounted) return;
      Navigator.pop(context);

      if (res['success'] == true) {
        _showSuccessSnackBar("Successfully joined the class!");
        _classCodeController.clear();
        await _refresh();
      } else {
        final errorMessage = res['message'] ?? "Failed to join class";

        String userFriendlyMessage = errorMessage;
        if (errorMessage.toLowerCase().contains('not found') ||
            errorMessage.toLowerCase().contains('invalid') ||
            errorMessage.toLowerCase().contains('does not exist')) {
          userFriendlyMessage =
              "Class code not found or invalid. Please check the code and try again.";
        } else if (errorMessage.toLowerCase().contains('already')) {
          userFriendlyMessage = "You're already enrolled in this class.";
        } else if (errorMessage.toLowerCase().contains('expired')) {
          userFriendlyMessage =
              "This class code has expired. Please ask your teacher for a new one.";
        }

        _showErrorSnackBar(userFriendlyMessage);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      String errorMessage =
          "Network error. Please check your connection and try again.";
      if (e.toString().contains('timeout') ||
          e.toString().contains('timed out')) {
        errorMessage = "Request timed out. Please try again.";
      }

      _showErrorSnackBar(errorMessage);
      debugPrint("Join class error: $e");
    }
  }

  void _showSuccessSnackBar(String message) {
    _showSnackBar(message, isSuccess: true);
  }

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, isSuccess: false);
  }

  void _showSnackBar(String message, {required bool isSuccess}) {
    final colorScheme = Theme.of(context).colorScheme;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isSuccess ? Colors.green.shade600 : colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error_outline,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
        action: !isSuccess
            ? SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              )
            : null,
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String errorMessage;

  const _ErrorWidget({required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Text(
        errorMessage,
        style: TextStyle(
          color: colorScheme.error,
          fontSize: 16,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ClassListView extends StatelessWidget {
  final List<Classroom> classes;

  const _ClassListView({required this.classes});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: classes.length,
      itemBuilder: (context, index) {
        final classItem = classes[index];
        return ClassCard(
          classId: classItem.id ?? '',
          className: classItem.className,
          sectionName: "${classItem.gradeLevel} - ${classItem.section}",
          teacherName: classItem.teacherName ?? "N/A",
          backgroundImage: 'assets/background/classroombg.jpg',
          realBackgroundImage:
              classItem.backgroundImage ?? 'assets/background/classroombg.jpg',
          teacherEmail: classItem.teacherEmail ?? "No email",
          teacherPosition: classItem.teacherPosition ?? "Teacher",
          teacherAvatar: classItem.teacherAvatar,
        );
      },
    );
  }
}

class JoinClassDialog extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onJoinPressed;

  const JoinClassDialog({
    required this.controller,
    required this.onJoinPressed,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      backgroundColor: colorScheme.surface,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/icons/join_class.jpg',
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Join Your Class!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Enter the class code your teacher gave you.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _buildCodeTextField(context),
              const SizedBox(height: 28),
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeTextField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 20,
        letterSpacing: 2.5,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: "ABCD1234",
        hintStyle: TextStyle(
          fontSize: 18,
          color: colorScheme.onSurfaceVariant.withOpacity(0.6),
          letterSpacing: 2,
        ),
        prefixIcon: Icon(
          Icons.school,
          color: colorScheme.primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
        ),
        filled: true,
        fillColor: colorScheme.primaryContainer.withOpacity(0.3),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCancelButton(context, colorScheme),
        const SizedBox(width: 8),
        _buildJoinButton(context, colorScheme),
      ],
    );
  }

  Widget _buildCancelButton(BuildContext context, ColorScheme colorScheme) {
    return ElevatedButton.icon(
      onPressed: () {
        controller.clear();
        Navigator.pop(context);
      },
      icon: const Icon(Icons.cancel),
      label: const Text("Cancel"),
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.surfaceVariant,
        foregroundColor: colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }

  Widget _buildJoinButton(BuildContext context, ColorScheme colorScheme) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.check_circle),
      onPressed: () {
        Navigator.pop(context);
        if (controller.text.trim().isNotEmpty) {
          onJoinPressed(controller.text.trim());
        }
      },
      label: const Text(
        "Join Class",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 120,
              child: Lottie.asset('assets/animation/searching_file.json'),
            ),
            const SizedBox(height: 12),
            Text(
              "Verifying Class Code...",
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
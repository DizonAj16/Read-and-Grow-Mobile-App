import 'package:deped_reading_app_laravel/api/supabase_auth_service.dart';
import 'package:deped_reading_app_laravel/models/teacher_model.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../pages/auth pages/landing_page.dart';
import '../../widgets/navigation/page_transition.dart';
import 'pupil_management_page.dart';
import 'pupil_submissions_and_report_page.dart';
import 'teacher dashboard/teacher_dashboard_page.dart';
import 'teacher_profile_page.dart';

// ─────────────────────────────────────────────
// Route constants
// ─────────────────────────────────────────────

class _Routes {
  static const dashboard = '/dashboard';
  static const pupils = '/pupils';
  static const submissions = '/submissions';
  // static const badges = '/badges';
  // static const gradeRecordings = '/grade_recordings';
  // static const viewGraded = '/view_graded_recordings';
  // static const readingMaterials = '/reading_materials';
}

// ─────────────────────────────────────────────
// Nav item model
// ─────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String title;
  final String route;

  const _NavItem({
    required this.icon,
    required this.title,
    required this.route,
  });
}

// ─────────────────────────────────────────────
// TeacherPage
// ─────────────────────────────────────────────

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  String _currentTitle = 'Dashboard';
  String _currentRoute = _Routes.dashboard;
  String _teacherName = 'Teacher';
  String? _profilePicture;

  static const _navItems = <_NavItem>[
    _NavItem(icon: Icons.home_rounded, title: 'Dashboard', route: _Routes.dashboard),
    _NavItem(icon: Icons.people_rounded, title: 'Manage Pupils', route: _Routes.pupils),
    _NavItem(icon: Icons.assignment_rounded, title: 'Pupil Submissions/Reports', route: _Routes.submissions),
  ];

  // ── Lifecycle ──────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
  }

  // ── Data loading ───────────────────────────

  Future<void> _loadTeacherData({bool forceRefresh = false}) async {
    try {
      if (forceRefresh && mounted) {
        setState(() => _profilePicture = null);
      }

      final profileResponse = await SupabaseAuthService.getAuthProfile();
      final teacherDetails = profileResponse?['profile'] ?? profileResponse ?? {};
      final teacher = Teacher.fromJson(teacherDetails);

      await teacher.saveToPrefs();

      final profilePicture = teacher.profilePicture?.isNotEmpty == true
          ? _buildProfilePictureUrl(teacher.profilePicture!, forceRefresh: true)
          : null;

      if (mounted) {
        setState(() {
          _teacherName = teacher.name;
          _profilePicture = profilePicture;
        });
      }
    } catch (e) {
      debugPrint('Failed to load teacher from API: $e');
      await _loadTeacherFromPrefs();
    }
  }

  Future<void> _loadTeacherFromPrefs() async {
    try {
      final teacher = await Teacher.fromPrefs();

      final profilePicture = teacher.profilePicture?.isNotEmpty == true
          ? _buildProfilePictureUrl(teacher.profilePicture!)
          : null;

      if (mounted) {
        setState(() {
          _teacherName = teacher.name;
          _profilePicture = profilePicture;
        });
      }
    } catch (e) {
      debugPrint('Failed to load teacher from prefs: $e');
      if (mounted) {
        setState(() {
          _teacherName = 'Teacher';
          _profilePicture = null;
        });
      }
    }
  }

  String _buildProfilePictureUrl(String path, {bool forceRefresh = false}) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final suffix = '?t=$ts&refresh=${forceRefresh ? 1 : 0}';

    if (path.startsWith('http://') || path.startsWith('https://')) {
      final base = path.contains('?') ? path.split('?').first : path;
      return '$base$suffix';
    }

    try {
      final cleanPath = path.replaceFirst(RegExp(r'^/'), '');
      final publicUrl = Supabase.instance.client.storage
          .from('materials')
          .getPublicUrl(cleanPath);
      return '$publicUrl$suffix';
    } catch (e) {
      debugPrint('Error getting Supabase storage URL: $e');
      return path;
    }
  }

  // ── Navigation ─────────────────────────────

  void _navigateTo(String route, String title) {
    if (_currentRoute == route) return;
    setState(() {
      _currentTitle = title;
      _currentRoute = route;
    });
    Navigator.pop(context);
    _navigatorKey.currentState?.pushReplacementNamed(route);
  }

  Route _generateRoute(RouteSettings settings) {
    final page = switch (settings.name) {
      _Routes.pupils      => const PupilManagementPage(),
      _Routes.submissions => const StudentSubmissionsPage(),
      // _Routes.badges            => const BadgesListPage(),
      // _Routes.gradeRecordings   => const ReadingRecordingsGradingPage(),
      // _Routes.viewGraded        => const ViewGradedRecordingsPage(),
      // _Routes.readingMaterials  => const TeacherReadingMaterialsPage(),
      _               => const TeacherDashboardPage(),
    };
    return MaterialPageRoute(builder: (_) => page);
  }

  // ── Auth ───────────────────────────────────

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await SupabaseAuthService.logout();
      await Teacher.clearPrefs();
      await prefs.remove('teacher_classes');
      await prefs.remove('students_data');

      if (!mounted) return;
      _showLoadingDialog(context);
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pushAndRemoveUntil(
          PageTransition(page: const LandingPage()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Logout error: $e');
      if (mounted) {
        _showErrorDialog(
          context,
          title: 'Logout Failed',
          message: 'Unable to logout. Please try again.',
        );
      }
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => _LogoutConfirmationDialog(onConfirm: _logout),
    );
  }

  // ── Profile ────────────────────────────────

  Future<void> _openProfile() async {
    setState(() => _profilePicture = null);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TeacherProfilePage()),
    );
    await _loadTeacherData();
    if (mounted) setState(() {});
  }

  // ── Build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: Navigator(
        key: _navigatorKey,
        initialRoute: _Routes.dashboard,
        onGenerateRoute: _generateRoute,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        _currentTitle,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.primary,
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withOpacity(0.95),
              Theme.of(context).colorScheme.primary.withOpacity(0.9),
            ],
          ),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerHeader(
                    teacherName: _teacherName,
                    profilePicture: _profilePicture,
                    onTap: _openProfile,
                  ),
                  const SizedBox(height: 16),
                  ..._navItems.map(
                    (item) => _DrawerNavItem(
                      icon: item.icon,
                      title: item.title,
                      isSelected: _currentRoute == item.route,
                      onTap: () => _navigateTo(item.route, item.title),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  const Divider(color: Colors.white30, thickness: 1, height: 32),
                  _DrawerNavItem(
                    icon: Icons.logout_rounded,
                    title: 'Log out',
                    isSelected: false,
                    onTap: _confirmLogout,
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

// ─────────────────────────────────────────────
// Drawer sub-widgets
// ─────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final String teacherName;
  final String? profilePicture;
  final VoidCallback onTap;

  const _DrawerHeader({
    required this.teacherName,
    required this.profilePicture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 40, bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Hero(
                  tag: 'teacher-profile-image',
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: Colors.white70,
                      child: ClipOval(child: _ProfileImage(url: profilePicture)),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              teacherName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black, blurRadius: 6, offset: Offset(1, 1))],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Teacher',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ProfileImage extends StatelessWidget {
  final String? url;

  const _ProfileImage({this.url});

  static const _placeholder = 'assets/placeholder/avatar_placeholder.jpg';

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Image.asset(_placeholder, fit: BoxFit.cover);
    }
    return Image.network(
      url!,
      key: ValueKey(url),
      fit: BoxFit.cover,
      cacheWidth: 200,
      cacheHeight: 200,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : Image.asset(_placeholder, fit: BoxFit.cover),
      errorBuilder: (_, error, __) {
        debugPrint('Failed to load profile picture: $error');
        return Image.asset(_placeholder, fit: BoxFit.cover);
      },
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerNavItem({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: Colors.white.withOpacity(0.3), width: 1)
            : null,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 16,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minLeadingWidth: 0,
        horizontalTitleGap: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Dialogs
// ─────────────────────────────────────────────

class _LogoutConfirmationDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const _LogoutConfirmationDialog({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.logout_rounded, color: cs.primary, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'Confirm Logout',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'You are about to log out. Make sure to save your work before leaving.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.cancel_outlined, size: 20, color: cs.onSurface.withOpacity(0.7)),
                    label: Text(
                      'Cancel',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w500),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: cs.outline.withOpacity(0.3), width: 1.5),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.logout_rounded, size: 20, color: Colors.white),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      shadowColor: cs.error.withOpacity(0.3),
                    ),
                    onPressed: onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _showLoadingDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Logging out...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
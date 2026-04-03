import 'package:deped_reading_app_laravel/api/supabase_auth_service.dart';
import 'package:deped_reading_app_laravel/models/student_model.dart';
import 'package:deped_reading_app_laravel/pages/auth%20pages/landing_page.dart';
import 'package:deped_reading_app_laravel/pages/student%20pages/student_dashboard_page.dart';
import 'package:deped_reading_app_laravel/widgets/helpers/tts_helper.dart';
import 'package:deped_reading_app_laravel/widgets/helpers/tts_modal.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/navigation/page_transition.dart';
import 'student class pages/student_class_page.dart';
import 'student_profile_page.dart';

class StudentPage extends StatefulWidget {
  const StudentPage({super.key});

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  final TTSHelper _ttsHelper = TTSHelper();

  // Page titles for AppBar
  final List<String> _pageTitles = [
    "Dashboard",
    "My Class",
  ];

  // Fixed pages - order must match bottom navigation
  final List<Widget> _pages = [
    const StudentDashboardPage(),
    const StudentClassPage(),
  ];

  @override
  void initState() {
    super.initState();
    _ttsHelper.init();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ttsHelper.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    try {
      await SupabaseAuthService.logout();

      final prefs = await SharedPreferences.getInstance();
      await _clearUserData(prefs);

      await _showLogoutSuccess(context);
      _navigateToLandingPage();
    } catch (e) {
      debugPrint("Logout failed: $e");
      _showLogoutError(context);
    }
  }

  Future<void> _clearUserData(SharedPreferences prefs) async {
    await prefs.remove('token');
    await prefs.remove('student_name');
    await prefs.remove('student_email');
    await prefs.remove('student_id');
    await prefs.remove('profile_picture');
    await prefs.remove('students_data');
    await prefs.remove('student_classes');
    await prefs.remove('student_data');
  }

  Future<void> _showLogoutSuccess(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _LogoutProgressDialog(),
    );
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.of(context).pop();
  }

  void _navigateToLandingPage() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        PageTransition(page: const LandingPage()),
        (route) => false,
      );
    }
  }

  void _showLogoutError(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _LogoutErrorDialog(),
    );
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => _LogoutConfirmationDialog(
        onStay: () => Navigator.pop(context),
        onLogout: _logout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _buildPageView(),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AppBar(
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          _pageTitles[_currentIndex],
          key: ValueKey(_currentIndex),
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      backgroundColor: colorScheme.primary,
      iconTheme: IconThemeData(color: colorScheme.onPrimary),
      actions: [
        _ProfilePopupMenu(
          onLogout: _showLogoutConfirmation,
          ttsHelper: _ttsHelper,
        ),
      ],
      elevation: 4,
      shadowColor: colorScheme.shadow.withOpacity(0.3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(20),
        ),
      ),
    );
  }

  Widget _buildPageView() {
    return PageView(
      controller: _pageController,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      children: _pages,
      physics: const PageScrollPhysics(),
      scrollBehavior: const ScrollBehavior().copyWith(
        overscroll: false,
        scrollbars: false,
      ),
    );
  }

  ClipRRect _buildBottomNavigationBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = colorScheme.primary;
    final primaryVariant = Color.alphaBlend(
      primaryColor.withOpacity(0.7),
      Colors.black,
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              primaryColor,
              primaryVariant,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.25),
              blurRadius: 15,
              spreadRadius: 3,
              offset: const Offset(0, -3),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: colorScheme.onPrimary.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          items: _buildBottomNavItems(colorScheme),
          selectedItemColor: colorScheme.onPrimary,
          unselectedItemColor: colorScheme.onPrimary.withOpacity(0.7),
          showUnselectedLabels: true,
          showSelectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.5,
            color: colorScheme.onPrimary,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            letterSpacing: 0.3,
            color: colorScheme.onPrimary.withOpacity(0.7),
          ),
          backgroundColor: Colors.transparent,
          iconSize: 26,
          selectedFontSize: 12,
          unselectedFontSize: 12,
        ),
      ),
    );
  }

  List<BottomNavigationBarItem> _buildBottomNavItems(ColorScheme colorScheme) {
    return [
      BottomNavigationBarItem(
        icon: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.home_outlined, color: colorScheme.onPrimary),
        ),
        activeIcon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                colorScheme.onPrimary.withOpacity(0.3),
                colorScheme.onPrimary.withOpacity(0.1),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.onPrimary.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(Icons.home, color: colorScheme.onPrimary),
        ),
        label: "Dashboard",
      ),
      BottomNavigationBarItem(
        icon: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.class_outlined, color: colorScheme.onPrimary),
        ),
        activeIcon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                colorScheme.onPrimary.withOpacity(0.3),
                colorScheme.onPrimary.withOpacity(0.1),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.onPrimary.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(Icons.class_, color: colorScheme.onPrimary),
        ),
        label: "My Class",
      ),
    ];
  }
}

class _ProfilePopupMenu extends StatefulWidget {
  final VoidCallback onLogout;
  final TTSHelper ttsHelper;

  const _ProfilePopupMenu({required this.onLogout, required this.ttsHelper});

  @override
  State<_ProfilePopupMenu> createState() => _ProfilePopupMenuState();
}

class _ProfilePopupMenuState extends State<_ProfilePopupMenu> {
  Student? _student;
  String? _profilePictureUrl;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    try {
      final profileResponse = await SupabaseAuthService.getAuthProfile();
      final studentProfile = profileResponse?['profile'] ?? {};
      final Student student = Student.fromJson(studentProfile);
      await student.saveToPrefs();
      final String? fullProfileUrl = await _buildProfilePictureUrl(
        student.profilePicture,
      );

      if (mounted) {
        setState(() {
          _student = student;
          _profilePictureUrl = fullProfileUrl;
        });
      }
    } catch (e) {
      try {
        final Student student = await Student.fromPrefs();
        final String? fullProfileUrl = await _buildProfilePictureUrl(
          student.profilePicture,
        );
        if (mounted) {
          setState(() {
            _student = student;
            _profilePictureUrl = fullProfileUrl;
          });
        }
      } catch (prefsError) {
        if (mounted) {
          setState(() {
            _student = Student(
              id: '',
              studentName: "Student",
              studentLrn: null,
              studentGrade: null,
              studentSection: null,
              username: null,
              profilePicture: null,
              classRoomId: null,
              completedTasks: 0,
            );
            _profilePictureUrl = null;
          });
        }
      }
    }
  }

  Future<String?> _buildProfilePictureUrl(String? profilePicture) async {
    if (profilePicture == null || profilePicture.isEmpty) {
      return null;
    }

    try {
      if (profilePicture.startsWith('http://') ||
          profilePicture.startsWith('https://')) {
        debugPrint('🖼️ Profile picture is already a full URL');
        return profilePicture;
      }

      final supabase = Supabase.instance.client;
      final bucketBaseUrl =
          supabase.storage.from('materials').getPublicUrl(profilePicture);

      debugPrint('🖼️ Normalized profile picture URL: $bucketBaseUrl');
      return bucketBaseUrl;
    } catch (e) {
      debugPrint('⚠️ Error building profile picture URL: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return PopupMenuButton<String>(
      icon: _buildProfileAvatar(radius: 16),
      tooltip: "Student Profile",
      onSelected: (value) => _handleMenuSelection(value, context),
      itemBuilder: (context) => _buildMenuItems(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      color: colorScheme.surface,
      shadowColor: colorScheme.shadow.withOpacity(0.2),
    );
  }

  Future<void> _handleMenuSelection(String value, BuildContext context) async {
    switch (value) {
      case 'logout':
        widget.onLogout();
        break;
      case 'profile':
        await _showProfileModal(context);
        break;
      case 'settings':
        await _showSettingsModal(context);
        break;
    }
  }

  Future<void> _showProfileModal(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _ProfileModalContainer(child: const StudentProfilePage()),
    );
    await _loadStudentData();
  }

  Future<void> _showSettingsModal(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProfileModalContainer(
        heightFactor: 0.4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: TTSSettingsModal(ttsHelper: widget.ttsHelper),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final studentName = _student?.studentName ?? "Student";

    return [
      PopupMenuItem<String>(
        value: 'profile',
        height: 100,
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProfileAvatar(radius: 32),
              const SizedBox(height: 8),
              Text(
                studentName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Student',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'logout',
        height: 48,
        child: SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Icons.logout, size: 20, color: colorScheme.error),
              const SizedBox(width: 12),
              Text(
                'Logout',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildProfileAvatar({required double radius}) {
    final colorScheme = Theme.of(context).colorScheme;
    final studentName = _student?.studentName ?? "Student";
    
    final String initials = _generateInitials(studentName);

    return CircleAvatar(
      radius: radius,
      backgroundColor: _profilePictureUrl == null
          ? colorScheme.primary
          : null,
      child: _profilePictureUrl == null
          ? Text(
              initials,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
              ),
            )
          : ClipOval(
              child: FadeInImage.assetNetwork(
                placeholder: 'assets/placeholder/avatar_placeholder.jpg',
                image: _profilePictureUrl!,
                fit: BoxFit.cover,
                width: radius * 2,
                height: radius * 2,
                imageErrorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colorScheme.primary,
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: radius * 0.7,
                        ),
                      ),
                    ),
                  );
                },
                fadeInDuration: const Duration(milliseconds: 300),
                fadeOutDuration: const Duration(milliseconds: 100),
              ),
            ),
    );
  }

  String _generateInitials(String fullName) {
    if (fullName.isEmpty) return "S";
    
    final nameParts = fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    
    if (nameParts.isEmpty) return "S";
    
    if (nameParts.length == 1) {
      return nameParts[0][0].toUpperCase();
    } else {
      return '${nameParts.first[0]}${nameParts.last[0]}'.toUpperCase();
    }
  }
}

class _ProfileModalContainer extends StatelessWidget {
  final Widget child;
  final double heightFactor;

  const _ProfileModalContainer({required this.child, this.heightFactor = 0.68});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: FractionallySizedBox(
        heightFactor: heightFactor,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.25),
                blurRadius: 32,
                spreadRadius: 4,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LogoutProgressDialog extends StatelessWidget {
  const _LogoutProgressDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              "Logging out...",
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutErrorDialog extends StatelessWidget {
  const _LogoutErrorDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colorScheme.surface,
      title: Text(
        'Logout Failed',
        style: TextStyle(color: colorScheme.onSurface),
      ),
      content: Text(
        'Unable to logout. Please try again.',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('OK', style: TextStyle(color: colorScheme.primary)),
        ),
      ],
    );
  }
}

class _LogoutConfirmationDialog extends StatelessWidget {
  final VoidCallback onStay;
  final VoidCallback onLogout;

  const _LogoutConfirmationDialog({
    required this.onStay,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      title: Column(
        children: [
          Icon(
            Icons.logout,
            color: colorScheme.primary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            "Are you leaving?",
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
        ],
      ),
      content: Text(
        "We hope to see you again soon! Are you sure you want to log out?",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
        textAlign: TextAlign.center,
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DialogButton(
              icon: Icons.cancel,
              text: "Stay",
              color: Colors.green,
              onPressed: onStay,
            ),
            const SizedBox(width: 12),
            _DialogButton(
              icon: Icons.logout,
              text: "Log Out",
              color: colorScheme.error,
              onPressed: onLogout,
            ),
          ],
        ),
      ],
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _DialogButton({
    required this.text,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        elevation: 4,
        shadowColor: color.withOpacity(0.4),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}
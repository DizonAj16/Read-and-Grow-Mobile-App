import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../api/parent_service.dart';
import '../../api/supabase_auth_service.dart';
import '../../widgets/navigation/page_transition.dart';
import '../auth pages/landing_page.dart';
import 'child_detail_page.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class ChildSummary {
  const ChildSummary({
    required this.studentId,
    required this.studentName,
    required this.readingLevel,
    required this.totalTasks,
    required this.completedTasks,
    required this.averageScore,
    required this.completedQuizzes,
    required this.totalQuizzes,
    required this.quizAverage,
    this.profilePicture,
  });

  final String studentId;
  final String studentName;
  final String readingLevel;
  final int totalTasks;
  final int completedTasks;
  final double averageScore;
  final int completedQuizzes;
  final int totalQuizzes;
  final double quizAverage;
  final String? profilePicture;

  /// Task completion as a 0–1 fraction.
  double get readingCompletionPercent =>
      totalTasks > 0 ? (completedTasks / totalTasks).clamp(0.0, 1.0) : 0.0;

  /// Quiz completion as a 0–1 fraction.
  double get quizCompletionPercent =>
      totalQuizzes > 0 ? (completedQuizzes / totalQuizzes).clamp(0.0, 1.0) : 0.0;

  /// Constructs a [ChildSummary] from the raw map returned by [ParentService].
  factory ChildSummary.fromMap(Map<String, dynamic> data) {
    return ChildSummary(
      studentId: data['studentId'] as String,
      studentName: data['studentName'] as String,
      readingLevel: data['readingLevel'] as String,
      totalTasks: data['totalTasks'] as int,
      completedTasks: data['completedTasks'] as int,
      averageScore: data['averageScore'] as double,
      completedQuizzes: data['completedQuizzes'] as int,
      totalQuizzes: data['totalQuizzes'] as int,
      quizAverage: data['quizAverage'] as double,
      profilePicture: data['profile_picture'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/// Returns a color for a 0–1 completion [percent].
Color _progressColor(double percent) {
  if (percent >= 0.75) return Colors.green;
  if (percent >= 0.5) return Colors.orange;
  return Colors.red;
}

/// Returns a label for a 0–1 completion [percent].
String _progressLabel(double percent) {
  if (percent >= 0.75) return 'Excellent Progress';
  if (percent >= 0.5) return 'Good Progress';
  if (percent > 0) return 'Needs Improvement';
  return 'No Progress Yet';
}

/// Resolves a child's profile picture to an [ImageProvider], or `null`.
ImageProvider<Object>? _resolveProfileImage(ChildSummary child) {
  final pic = child.profilePicture;
  if (pic == null || pic.isEmpty) return null;

  if (pic.startsWith('http')) return NetworkImage(pic);

  final url = Supabase.instance.client.storage
      .from('document')
      .getPublicUrl(pic);

  debugPrint('🖼️  [ParentDashboard] Profile URL for ${child.studentName}: $url');
  return NetworkImage(url);
}

// ---------------------------------------------------------------------------
// Page widget
// ---------------------------------------------------------------------------

class ParentDashboardPage extends StatefulWidget {
  const ParentDashboardPage({super.key, required this.parentId});

  final String parentId;

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  bool _isLoading = true;
  List<ChildSummary> _children = [];

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _fetchChildrenData();
  }

  // -------------------------------------------------------------------------
  // Data loading
  // -------------------------------------------------------------------------

  Future<void> _fetchChildrenData() async {
    setState(() => _isLoading = true);
    debugPrint('📡 [ParentDashboard] Loading children for parentId: ${widget.parentId}');

    try {
      final rawList = await ParentService().getChildrenSummary(widget.parentId);
      if (!mounted) return;
      setState(() {
        _children = rawList.map(ChildSummary.fromMap).toList();
      });
    } catch (e, stack) {
      debugPrint('❌ [ParentDashboard] Error fetching children: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Logout
  // -------------------------------------------------------------------------

  Future<void> _logout() async {
    final confirmed = await _showLogoutConfirmDialog();
    if (confirmed != true) return;

    _showLoadingDialog();

    try {
      await SupabaseAuthService.logout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('parent_id');
      await prefs.remove('parent_name');

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      Navigator.of(context).pushAndRemoveUntil(
        PageTransition(page: const LandingPage()),
        (route) => false,
      );
    } catch (e, stack) {
      debugPrint('❌ [ParentDashboard] Logout error: $e\n$stack');
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to logout. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<bool?> _showLogoutConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (_) => const _LogoutConfirmDialog(),
    );
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LogoutLoadingDialog(),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.background,
      appBar: _buildAppBar(cs),
      body: _buildBody(cs),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    return AppBar(
      title: const Text(
        'My Children',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 24),
          onPressed: _fetchChildrenData,
          tooltip: 'Refresh',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 24),
          onSelected: (value) {
            if (value == 'logout') _logout();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: Colors.red[700], size: 20),
                  const SizedBox(width: 12),
                  Text('Logout', style: TextStyle(color: cs.onSurface)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_isLoading) return _LoadingIndicator(color: cs.primary);

    if (_children.isEmpty) return const _EmptyChildrenState();

    return RefreshIndicator(
      onRefresh: _fetchChildrenData,
      color: cs.primary,
      backgroundColor: cs.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _children.length,
        itemBuilder: (_, i) => _ChildCard(child: _children[i]),
      ),
    );
  }
}

// ===========================================================================
// Private sub-widgets
// ===========================================================================

// ---------------------------------------------------------------------------
// Loading / empty states
// ---------------------------------------------------------------------------

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: color),
          const SizedBox(height: 16),
          Text(
            'Loading Children Data...',
            style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onBackground),
          ),
        ],
      ),
    );
  }
}

class _EmptyChildrenState extends StatelessWidget {
  const _EmptyChildrenState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.child_care_outlined, size: 80, color: cs.outline),
          const SizedBox(height: 20),
          Text(
            'No children found',
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 18,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Text(
            "Contact your child's teacher to link your account",
            style: TextStyle(color: cs.outline, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logout dialogs
// ---------------------------------------------------------------------------

/// Confirmation dialog shown before logging out.
class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.1),
              cs.primary.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // — Header —
            _DialogSection(
              isTop: true,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.red[100], shape: BoxShape.circle),
                    child: Icon(Icons.logout_rounded,
                        color: Colors.red[700], size: 40),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Logout?',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: Colors.red),
                  ),
                ],
              ),
            ),
            // — Body —
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Are you sure you want to logout?',
                style: TextStyle(
                    fontSize: 16, color: Colors.blueGrey[700], height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
            // — Actions —
            _DialogSection(
              isTop: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: const Text('Logout',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
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

/// Rounded white section used inside the logout confirm dialog.
class _DialogSection extends StatelessWidget {
  const _DialogSection({required this.isTop, required this.child});

  final bool isTop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = isTop
        ? const BorderRadius.vertical(top: Radius.circular(20))
        : const BorderRadius.vertical(bottom: Radius.circular(20));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: isTop ? const Offset(0, 2) : const Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Spinner dialog shown while the logout call is in progress.
class _LogoutLoadingDialog extends StatelessWidget {
  const _LogoutLoadingDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Logging out...',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Child card
// ---------------------------------------------------------------------------

/// The main card displayed for each child in the list.
class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child});

  final ChildSummary child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = _progressColor(child.readingCompletionPercent);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        color: cs.surface,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChildDetailPage(
                studentId: child.studentId,
                studentName: child.studentName,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChildCardHeader(child: child, borderColor: borderColor),
                const SizedBox(height: 20),
                Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.outline.withOpacity(0.3)),
                const SizedBox(height: 16),
                _ChildCardStats(child: child),
                const SizedBox(height: 16),
                _ChildCardProgress(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Top row of the child card: avatar + name + reading level badge + arrow.
class _ChildCardHeader extends StatelessWidget {
  const _ChildCardHeader({
    required this.child,
    required this.borderColor,
  });

  final ChildSummary child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Avatar
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: borderColor.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 32,
            backgroundColor: cs.primaryContainer,
            backgroundImage: _resolveProfileImage(child),
            child: _resolveProfileImage(child) == null
                ? Text(
                    child.studentName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 16),

        // Name + level badge
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                child.studentName,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '📚 ${child.readingLevel} • ⭐ ${child.averageScore.toStringAsFixed(0)}% Avg',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // Arrow
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.arrow_forward_ios_rounded,
              color: cs.outline, size: 18),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Three stat chips shown in the middle of the child card.
class _ChildCardStats extends StatelessWidget {
  const _ChildCardStats({required this.child});

  final ChildSummary child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completedPct = child.totalTasks > 0
        ? '${((child.completedTasks / child.totalTasks) * 100).toInt()}%'
        : '0%';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatChip(
          icon: Icons.quiz_outlined,
          label: 'Quizzes',
          value: '${child.completedQuizzes}',
          color: Colors.orange[700]!,
        ),
        _StatChip(
          icon: Icons.star_rounded,
          label: 'Avg Score',
          value: '${child.averageScore.toStringAsFixed(0)}%',
          color: Colors.green[700]!,
        ),
        _StatChip(
          icon: Icons.check_circle_rounded,
          label: 'Completed',
          value: completedPct,
          color: cs.primary,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Progress bars section at the bottom of the child card.
class _ChildCardProgress extends StatelessWidget {
  const _ChildCardProgress({required this.child});

  final ChildSummary child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progress Overview',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface),
          ),
          const SizedBox(height: 16),

          _ProgressBar(
            icon: Icons.book_rounded,
            title: 'Reading Tasks',
            completed: child.completedTasks,
            total: child.totalTasks,
            percent: child.readingCompletionPercent,
            iconColor: cs.primary,
          ),
          const SizedBox(height: 16),

          _ProgressBar(
            icon: Icons.quiz_rounded,
            title: 'Quizzes',
            completed: child.completedQuizzes,
            total: child.totalQuizzes,
            percent: child.quizCompletionPercent,
            iconColor: cs.primary,
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

/// A compact stat chip used in the child card stats row.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: outline, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// A labeled progress bar with icon, fraction label, and status text.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.icon,
    required this.title,
    required this.completed,
    required this.total,
    required this.percent,
    required this.iconColor,
  });

  final IconData icon;
  final String title;
  final int completed;
  final int total;
  final double percent;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final barColor = _progressColor(percent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ),
            Text('$completed/$total',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.outline,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 8),

        // Bar
        LinearPercentIndicator(
          lineHeight: 8.0,
          percent: percent.clamp(0.0, 1.0),
          backgroundColor: cs.outline.withOpacity(0.2),
          progressColor: barColor,
          barRadius: const Radius.circular(4),
          animation: true,
          animationDuration: 1000,
        ),
        const SizedBox(height: 6),

        // Footer labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_progressLabel(percent),
                style: TextStyle(
                    fontSize: 11,
                    color: barColor,
                    fontWeight: FontWeight.w600)),
            Text('${(percent * 100).toStringAsFixed(0)}% Complete',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.outline,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}
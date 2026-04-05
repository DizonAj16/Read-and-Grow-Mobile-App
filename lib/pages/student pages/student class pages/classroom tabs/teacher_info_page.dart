import 'package:deped_reading_app_laravel/constants.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class _SocialLinksSection extends StatelessWidget {
  final Map<String, dynamic> socialLinks;

  const _SocialLinksSection({required this.socialLinks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12),
      child: Column(
        children: [
          Text(
            "📱 Connect with Teacher",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[800],
              fontFamily: 'ComicNeue',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (socialLinks['facebook'] != null)
                _SocialButton(
                  icon: Icons.facebook,
                  color: Colors.blue[700]!,
                  label: "Facebook",
                  url: socialLinks['facebook'],
                ),
              if (socialLinks['linkedin'] != null)
                _SocialButton(
                  icon: Icons.business_center_rounded,
                  color: Colors.indigo,
                  label: "LinkedIn",
                  url: socialLinks['linkedin'],
                ),
              if (socialLinks['twitter'] != null)
                _SocialButton(
                  icon: Icons.alternate_email_rounded,
                  color: Colors.lightBlue,
                  label: "Twitter / X",
                  url: socialLinks['twitter'],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String url;

  const _SocialButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.url,
  });

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('❌ Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _launchUrl(url),
      child: Chip(
        avatar: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.blueGrey,
            fontWeight: FontWeight.w600,
            fontFamily: 'ComicNeue',
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        shadowColor: color.withOpacity(0.2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
    );
  }
}


class TeacherInfoPage extends StatefulWidget {
  final String classId;

  const TeacherInfoPage({
    super.key,
    required this.classId,
  });

  @override
  State<TeacherInfoPage> createState() => _TeacherInfoPageState();
}

class _TeacherInfoPageState extends State<TeacherInfoPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _teacherData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
  }

  /// Load teacher data from database based on class ID
  Future<void> _loadTeacherData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Get class room details with teacher information
      final classResponse = await supabase
          .from('class_rooms')
          .select('''
            teacher_id,
            teachers:teachers(
              id,
              teacher_name,
              teacher_email,
              teacher_position,
              profile_picture,
              social_links
            )
          ''')
          .eq('id', widget.classId)
          .maybeSingle();

      if (classResponse == null) {
        throw Exception('Class not found');
      }

      final teacherData = classResponse['teachers'];
      if (teacherData == null) {
        throw Exception('Teacher not found for this class');
      }

      setState(() {
        _teacherData = Map<String, dynamic>.from(teacherData);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading teacher data: $e');
      setState(() {
        _errorMessage = 'Failed to load teacher information';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.lightBlue[50],
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null || _teacherData == null) {
      return Scaffold(
        backgroundColor: Colors.lightBlue[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Teacher information not available',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadTeacherData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Extract teacher data with fallbacks
    final teacherName = _teacherData!['teacher_name']?.toString() ?? 'Teacher';
    final teacherEmail = _teacherData!['teacher_email']?.toString() ?? 'Email not available';
    final teacherPosition = _teacherData!['teacher_position']?.toString() ?? 'Position not set';
    final teacherAvatar = _teacherData!['profile_picture']?.toString();
    final socialLinks = _teacherData!['social_links'] as Map<String, dynamic>?;

    final avatarLetter = teacherName.isNotEmpty ? teacherName[0].toUpperCase() : '?';
    final avatarColor = _getAvatarColor(teacherName);

    return Scaffold(
      backgroundColor: Colors.lightBlue[50],
      body: Column(
        children: [
          const _TeacherHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _ProfileCard(
                    teacherName: teacherName,
                    teacherEmail: teacherEmail,
                    teacherPosition: teacherPosition,
                    teacherAvatar: teacherAvatar,
                    avatarLetter: avatarLetter,
                    avatarColor: avatarColor,
                  ),

                  // Social links section - now using database data
                  if (socialLinks != null && socialLinks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SocialLinksSection(
                      socialLinks: socialLinks,
                    ),
                  ],

                  const _SuperpowersSection(),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }

  Color _getAvatarColor(String name) {
    final colors = [
      Colors.pink[300]!,
      Colors.blue[300]!,
      Colors.green[300]!,
      Colors.orange[300]!,
      Colors.purple[300]!,
      Colors.teal[300]!,
    ];
    return colors[name.hashCode % colors.length];
  }
}

class _TeacherHeader extends StatelessWidget {
  const _TeacherHeader();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: 120,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryColor, Color(0xFFB71C1C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Text(
            "Teacher Profile",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'ComicNeue',
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String teacherName;
  final String teacherEmail;
  final String teacherPosition;
  final String? teacherAvatar;
  final String avatarLetter;
  final Color avatarColor;

  const _ProfileCard({
    required this.teacherName,
    required this.teacherEmail,
    required this.teacherPosition,
    required this.teacherAvatar,
    required this.avatarLetter,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 300),
        tween: Tween(begin: 0, end: 1),
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: Card(
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          shadowColor: avatarColor.withOpacity(0.25),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.85),
                  Colors.white.withOpacity(0.9),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: avatarColor.withOpacity(0.2)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _TeacherAvatar(
                  teacherAvatar: teacherAvatar,
                  avatarLetter: avatarLetter,
                  avatarColor: avatarColor,
                ),
                const SizedBox(height: 20),
                _TeacherName(name: teacherName, avatarColor: avatarColor),
                const SizedBox(height: 20),
                _TeacherInfoCard(
                  icon: Icons.email_rounded,
                  color: Colors.pink[300]!,
                  title: "Email",
                  value: teacherEmail,
                ),
                const SizedBox(height: 12),
                _TeacherInfoCard(
                  icon: Icons.school_rounded,
                  color: Colors.purple[300]!,
                  title: "Position",
                  value: teacherPosition,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherAvatar extends StatelessWidget {
  final String? teacherAvatar;
  final String avatarLetter;
  final Color avatarColor;

  const _TeacherAvatar({
    required this.teacherAvatar,
    required this.avatarLetter,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: avatarColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: avatarColor.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: teacherAvatar != null && teacherAvatar!.isNotEmpty
            ? FadeInImage.assetNetwork(
                placeholder: 'assets/placeholder/avatar_placeholder.jpg',
                image: teacherAvatar!,
                fit: BoxFit.cover,
                imageErrorBuilder: (_, __, ___) => _AvatarFallback(
                  letter: avatarLetter,
                  backgroundColor: avatarColor,
                ),
              )
            : _AvatarFallback(
                letter: avatarLetter,
                backgroundColor: avatarColor,
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String letter;
  final Color backgroundColor;

  const _AvatarFallback({
    required this.letter,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      alignment: Alignment.center,
      child: Text(
        letter.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.bold,
          fontFamily: 'ComicNeue',
        ),
      ),
    );
  }
}

class _TeacherName extends StatelessWidget {
  final String name;
  final Color avatarColor;

  const _TeacherName({
    required this.name,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
            fontFamily: 'ComicNeue',
          ),
        ),
        Container(
          width: 100,
          height: 4,
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: avatarColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _TeacherInfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;

  const _TeacherInfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontFamily: 'ComicNeue',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                      fontFamily: 'ComicNeue',
                    ),
                    overflow: TextOverflow.ellipsis,
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

class _SuperpowersSection extends StatelessWidget {
  const _SuperpowersSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            "🌟 Teacher Superpowers 🌟",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
              fontFamily: 'ComicNeue',
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: const [
              _SuperpowerCard(
                title: "Knowledge Ninja",
                icon: Icons.lightbulb,
                color: Colors.pink,
              ),
              _SuperpowerCard(
                title: "Homework Hero",
                icon: Icons.auto_awesome,
                color: Colors.blue,
              ),
              _SuperpowerCard(
                title: "Story Sage",
                icon: Icons.menu_book,
                color: Colors.purple,
              ),
              _SuperpowerCard(
                title: "Patience Pro",
                icon: Icons.self_improvement,
                color: Colors.green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _SuperpowerCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SuperpowerCard({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.12), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'ComicNeue',
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.blueGrey,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
      size.width / 4,
      size.height,
      size.width / 2,
      size.height - 20,
    );
    path.quadraticBezierTo(
      3 / 4 * size.width,
      size.height - 40,
      size.width,
      size.height - 10,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
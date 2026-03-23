// screens/announcements_list_screen.dart
import 'package:deped_reading_app_laravel/api/classroom_service.dart';
import 'package:deped_reading_app_laravel/models/announcement_model.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/classroom%20tabs/create_announcement_screen.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20classes/classroom%20tabs/update_announcement_dialog.dart';
import 'package:deped_reading_app_laravel/pages/teacher%20pages/teacher%20dashboard/cards/announcement_card.dart';
import 'package:flutter/material.dart';

class AnnouncementsListScreen extends StatefulWidget {
  final String classRoomId;
  final String className;
  final bool isTeacher;

  const AnnouncementsListScreen({
    super.key,
    required this.classRoomId,
    required this.className,
    this.isTeacher = true,
  });

  @override
  State<AnnouncementsListScreen> createState() =>
      _AnnouncementsListScreenState();
}

class _AnnouncementsListScreenState extends State<AnnouncementsListScreen> {
  List<Announcement> _announcements = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final announcements = await ClassroomService.getClassAnnouncements(
        widget.classRoomId,
      );

      setState(() {
        _announcements = announcements;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAnnouncement(String announcementId, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Announcement'),
            content: const Text(
              'Are you sure you want to delete this announcement? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final success = await ClassroomService.deleteAnnouncement(announcementId);

      if (success) {
        setState(() {
          _announcements.removeAt(index);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Announcement deleted successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete announcement'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // In AnnouncementsListScreen, update the _editAnnouncement method:
  void _editAnnouncement(Announcement announcement) {
    showDialog(
      context: context,
      builder:
          (context) => UpdateAnnouncementDialog(
            announcement: announcement,
            onUpdated: _loadAnnouncements,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isTeacher ? 'Class Announcements' : 'Announcements'),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _hasError
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load announcements',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loadAnnouncements,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              )
              : _announcements.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.announcement_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.isTeacher
                          ? 'No announcements yet'
                          : 'No announcements from teacher',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (widget.isTeacher)
                      Text(
                        'Create your first announcement to share updates with students',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _loadAnnouncements,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _announcements.length,
                  itemBuilder: (context, index) {
                    final announcement = _announcements[index];
                    return AnnouncementCard(
                      announcement: announcement,
                      isTeacher: widget.isTeacher,
                      onEdit:
                          widget.isTeacher
                              ? () => _editAnnouncement(announcement)
                              : null,
                      onDelete:
                          widget.isTeacher
                              ? () =>
                                  _deleteAnnouncement(announcement.id, index)
                              : null,
                    );
                  },
                ),
              ),
      floatingActionButton:
          widget.isTeacher
              ? FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => CreateAnnouncementScreen(
                            classRoomId: widget.classRoomId,
                            className: widget.className,
                          ),
                    ),
                  ).then((_) => _loadAnnouncements());
                },
                child: const Icon(Icons.add),
              )
              : null,
    );
  }
}

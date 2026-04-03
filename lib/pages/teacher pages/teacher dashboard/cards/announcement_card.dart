// widgets/announcement_card.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:deped_reading_app_laravel/models/announcement_model.dart';
import 'package:flutter/material.dart';

class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool showClassInfo;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isTeacher;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    this.showClassInfo = false,
    this.onEdit,
    this.onDelete,
    this.isTeacher = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 1,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with teacher info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile picture
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withOpacity(0.1),
                    image: announcement.teacherProfilePicture != null
                        ? DecorationImage(
                            image: NetworkImage(announcement.teacherProfilePicture!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: announcement.teacherProfilePicture == null
                      ? Icon(
                          Icons.person_outline,
                          size: 20,
                          color: colorScheme.primary,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                
                // Teacher info and time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.teacherName ?? 'Teacher',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            announcement.displayDate,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          if (announcement.updatedAt != null && 
                              announcement.updatedAt!.isAfter(announcement.createdAt))
                            Row(
                              children: [
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: colorScheme.onSurface.withOpacity(0.4),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Action menu for teachers
                if (isTeacher && (onEdit != null || onDelete != null))
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                    color: colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 20, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Edit', style: TextStyle(color: colorScheme.onSurface)),
                            ],
                          ),
                        ),
                      if (onDelete != null)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                              const SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: colorScheme.error)),
                            ],
                          ),
                        ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit' && onEdit != null) {
                        onEdit!();
                      } else if (value == 'delete' && onDelete != null) {
                        onDelete!();
                      }
                    },
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Title
            Text(
              announcement.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Image if exists
            if (announcement.imageUrl != null && announcement.imageUrl!.isNotEmpty)
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: announcement.imageUrl!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Container(
                        height: 200,
                        color: colorScheme.surfaceVariant,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 200,
                        color: colorScheme.surfaceVariant,
                        child: Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 48,
                            color: colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            
            // Content
            Text(
              announcement.content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.8),
                height: 1.5,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Class info (for student view)
            if (showClassInfo)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.class_outlined,
                      size: 14,
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Class Announcement',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
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
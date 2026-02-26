import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import '../models/classroom.dart';
import '../models/post.dart';
import '../models/assignment.dart';
import '../models/attachment.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';
import 'student_assignment_detail_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  final Classroom classroom;

  const StudentDashboardScreen({super.key, required this.classroom});

  @override
  State<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _dbService = DatabaseService();
  List<Post> _localPosts = [];
  List<Assignment> _localAssignments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final posts = await _dbService.getPostsForClassroom(widget.classroom.id);
    final assignments = await _dbService.getAssignmentsForClassroom(widget.classroom.id);
    if (mounted) {
      setState(() {
        _localPosts = posts;
        _localAssignments = assignments;
      });
    }
  }

  /// Decide which posts to show: live P2P if connected, otherwise local DB
  List<Post> _getPosts(P2PProvider p2p) {
    if (_isConnected(p2p)) {
      if (p2p.posts.isNotEmpty) return p2p.posts;
      return []; // Return empty list to correctly show empty state if live but no posts
    }
    return _localPosts;
  }

  List<Assignment> _getAssignments(P2PProvider p2p) {
    if (_isConnected(p2p)) {
      if (p2p.assignments.isNotEmpty) return p2p.assignments;
      return []; // Return empty list to correctly show empty state if live but no assignments
    }
    return _localAssignments;
  }

  bool _isConnected(P2PProvider p2p) {
    return (p2p.state == P2PState.connected || p2p.state == P2PState.advertising) &&
        p2p.currentClassroom?.id == widget.classroom.id;
  }

  void _openAttachment(Attachment attachment) async {
    final file = File(attachment.filePath);
    if (await file.exists()) {
      final result = await OpenFilex.open(attachment.filePath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file: ${result.message}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('File not found. It may still be transferring.'),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showShareUpdatesDialog(P2PProvider p2p) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false).profile!;
    
    // Start advertising as a student host
    await p2p.startStudentSyncAdvertising(widget.classroom, profile.displayName);

    final qrData = jsonEncode({
      'type': 'student_sync',
      'hostName': profile.displayName,
      'classroomId': widget.classroom.id,
      'teacherName': widget.classroom.teacherName,
      'classroomName': widget.classroom.name,
      'password': widget.classroom.password,
    });

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Share Setup', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Have your classmate scan this code from the P2P Hub to instantly sync all updates!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Consumer<P2PProvider>(
              builder: (context, p2pState, child) {
                if (p2pState.connectedStudents.where((s) => s.isAuthenticated).isNotEmpty) {
                  // A student has connected and authenticated! Close dialog soon.
                  Future.microtask(() {
                    if (Navigator.canPop(ctx)) {
                       Navigator.pop(ctx);
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Peer connected! Syncing...'), backgroundColor: Colors.green),
                       );
                    }
                  });
                  return const Text('Connected!', style: TextStyle(color: Colors.green));
                }
                return Column(
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF00C9A7)),
                    const SizedBox(height: 8),
                    Text(
                      'Awaiting connection...',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              p2p.stopAll();
              Navigator.pop(ctx);
            },
            child: const Text('Stop Sharing', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<P2PProvider>(
      builder: (context, p2p, _) {
        final posts = _getPosts(p2p);
        final assignments = _getAssignments(p2p);
        final connected = _isConnected(p2p);

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F0C29),
                  Color(0xFF302B63),
                  Color(0xFF24243E),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios,
                                  color: Colors.white70),
                              onPressed: () {
                                if (connected) p2p.stopAll();
                                Navigator.pop(context);
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.classroom.name,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Teacher: ${widget.classroom.teacherName}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!connected) // Only show if offline and not connected to teacher
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00C9A7).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF00C9A7).withValues(alpha: 0.3)),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.share_rounded, color: Color(0xFF00C9A7), size: 20),
                                  onPressed: () => _showShareUpdatesDialog(p2p),
                                  tooltip: 'Share offline updates to peers',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Connection status
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: (connected
                                    ? Colors.greenAccent
                                    : Colors.white)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (connected
                                      ? Colors.greenAccent
                                      : Colors.white38)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: connected
                                      ? Colors.greenAccent
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  connected
                                      ? (p2p.state == P2PState.advertising ? 'Sharing live with peers...' : 'Connected to teacher')
                                      : 'Offline — viewing saved posts',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (connected)
                                InkWell(
                                  onTap: () => p2p.stopAll(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Disconnect', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Tab Bar
                        TabBar(
                          controller: _tabController,
                          indicatorColor: const Color(0xFF00C9A7),
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white54,
                          tabs: const [
                            Tab(text: 'Announcements'),
                            Tab(text: 'Assignments'),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),

                // TabBarView Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Posts view
                      _buildPostsView(posts, connected, p2p),
                      
                      // Assignments view
                      _buildAssignmentsView(assignments, connected, p2p),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    );
  }

  Widget _buildPostsView(List<Post> posts, bool connected, P2PProvider p2p) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 64,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              connected
                  ? 'No announcements yet.\nWaiting for teacher to post...'
                  : 'No saved posts yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLocalData,
      color: const Color(0xFF00C9A7),
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          return _StudentPostCard(
            post: post,
            teacherName: widget.classroom.teacherName,
            formatTime: _formatTime,
            onAttachmentTap: _openAttachment,
            p2p: p2p,
          );
        },
      ),
    );
  }

  Widget _buildAssignmentsView(List<Assignment> assignments, bool connected, P2PProvider p2p) {
    if (assignments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_rounded,
              size: 64,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              connected
                  ? 'No assignments yet.\nWaiting for teacher to assign...'
                  : 'No saved assignments yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLocalData,
      color: const Color(0xFF00C9A7),
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: assignments.length,
        itemBuilder: (context, index) {
          final assignment = assignments[index];
          return _StudentAssignmentCard(
            assignment: assignment,
            teacherName: widget.classroom.teacherName,
            formatTime: _formatTime,
            p2p: p2p,
            onAttachmentTap: _openAttachment,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StudentAssignmentDetailScreen(
                    assignment: assignment,
                    teacherName: widget.classroom.teacherName,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Student Post Card ───

class _StudentPostCard extends StatelessWidget {
  final Post post;
  final String teacherName;
  final String Function(DateTime) formatTime;
  final void Function(Attachment) onAttachmentTap;
  final P2PProvider p2p;

  const _StudentPostCard({
    required this.post,
    required this.teacherName,
    required this.formatTime,
    required this.onAttachmentTap,
    required this.p2p,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Teacher info row
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    size: 16,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  teacherName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  formatTime(post.createdAt),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Post text
            if (post.content.isNotEmpty)
              Text(
                post.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

            // Image preview (inline for images)
            if (post.hasAttachments) ...[
              const SizedBox(height: 12),

              // Show image previews first
              ...post.attachments
                  .where((a) => a.isImage)
                  .map((attachment) => _buildImagePreview(attachment)),

              // Show non-image attachments as tappable badges
              if (post.attachments.any((a) => !a.isImage))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: post.attachments
                      .where((a) => !a.isImage)
                      .map((attachment) {
                    final progress = p2p.fileTransferProgress[attachment.id];
                    return _FileAttachmentButton(
                      attachment: attachment,
                      progress: progress,
                      onTap: () => onAttachmentTap(attachment),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(Attachment attachment) {
    final file = File(attachment.filePath);
    final progress = p2p.fileTransferProgress[attachment.id];
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: file.existsSync() && progress == null
            ? Image.file(
                file,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _imagePlaceholder(attachment, progress),
              )
            : _imagePlaceholder(attachment, progress),
      ),
    );
  }

  Widget _imagePlaceholder(Attachment attachment, [double? progress]) {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_rounded, size: 32,
              color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          if (progress != null) ...[
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                color: const Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading ${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
          ] else
            Text(
              attachment.fileName,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ─── File Attachment Button (tappable, for student) ───

class _FileAttachmentButton extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onTap;
  final double? progress;

  const _FileAttachmentButton({
    required this.attachment,
    required this.onTap,
    this.progress,
  });

  IconData _getIcon() {
    switch (attachment.fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'mp3':
        return Icons.audiotrack_rounded;
      case 'mp4':
        return Icons.videocam_rounded;
      case 'csv':
        return Icons.table_chart_rounded;
      case 'docx':
      case 'doc':
        return Icons.description_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getColor() {
    switch (attachment.fileType.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFFF6B6B);
      case 'mp3':
        return const Color(0xFFFF9F43);
      case 'mp4':
        return const Color(0xFF54A0FF);
      case 'csv':
        return const Color(0xFF5F27CD);
      case 'docx':
      case 'doc':
        return const Color(0xFF2E86DE);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFEE5A24);
      default:
        return const Color(0xFF6C63FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getIcon(), size: 18, color: color),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                attachment.fileName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (progress != null) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(progress! * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: color, fontSize: 10),
              ),
            ] else ...[
              Text(
                attachment.fileSizeFormatted,
                style: TextStyle(
                  color: color.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.open_in_new_rounded, size: 12, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Student Assignment Card ───

class _StudentAssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final String teacherName;
  final String Function(DateTime) formatTime;
  final VoidCallback onTap;
  final Function(Attachment) onAttachmentTap;
  final P2PProvider p2p;

  const _StudentAssignmentCard({
    required this.assignment,
    required this.teacherName,
    required this.formatTime,
    required this.onTap,
    required this.onAttachmentTap,
    required this.p2p,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon + Title + Due Date
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF5A52D5)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.assignment_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Assigned by $teacherName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Description
            if (assignment.description.isNotEmpty) ...[
              Text(
                assignment.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Meta Row
            Row(
              children: [
                if (assignment.dueDate != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9F43).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 12, color: Color(0xFFFF9F43)),
                        const SizedBox(width: 6),
                        Text(
                          'Due ${DateFormat('MMM d').format(assignment.dueDate!)}',
                          style: const TextStyle(
                            color: Color(0xFFFF9F43),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (assignment.dueDate != null) const SizedBox(width: 8),
                if (assignment.maxScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C9A7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.score, size: 12, color: Color(0xFF00C9A7)),
                        const SizedBox(width: 6),
                        Text(
                          '${assignment.maxScore} pts',
                          style: const TextStyle(
                            color: Color(0xFF00C9A7),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: Colors.white54),
              ],
            ),
            
            // Attachments
            if (assignment.hasAttachments) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              
              // Non-image Attachments
              if (assignment.attachments.any((a) => !a.isImage))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: assignment.attachments
                      .where((a) => !a.isImage)
                      .map((attachment) {
                    final progress = p2p.fileTransferProgress[attachment.id];
                    return _FileAttachmentButton(
                      attachment: attachment,
                      progress: progress,
                      onTap: () => onAttachmentTap(attachment),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models/attachment.dart';
import '../models/classroom.dart';
import '../models/post.dart';
import '../models/assignment.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'teacher_assignment_detail_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  final Classroom classroom;

  const TeacherDashboardScreen({super.key, required this.classroom});

  @override
  State<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _postController = TextEditingController();
  
  // Assignment form state
  final _assignmentTitleController = TextEditingController();
  final _assignmentDescController = TextEditingController();
  DateTime? _selectedDueDate;
  double? _selectedMaxScore;

  final DatabaseService _dbService = DatabaseService();
  List<Post> _localPosts = [];
  List<Assignment> _localAssignments = [];
  bool _isLive = false;
  bool _isPosting = false;

  // Selected files for a new post/assignment
  List<PlatformFile> _selectedFiles = [];

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

  void _goLive() async {
    // Request all P2P permissions before starting
    final granted = await PermissionService.requestP2PPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Location permission is required for P2P sharing. Please enable it in Settings.'),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final p2p = Provider.of<P2PProvider>(context, listen: false);
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile!;

    await p2p.createAndAdvertise(widget.classroom, profile.displayName);
    if (mounted) {
      setState(() => _isLive = true);
    }
  }

  void _goOffline() async {
    final p2p = Provider.of<P2PProvider>(context, listen: false);
    await p2p.stopAll();
    if (mounted) {
      setState(() => _isLive = false);
    }
  }

  void _createPost() async {
    final content = _postController.text.trim();
    if (content.isEmpty && _selectedFiles.isEmpty) return;

    final p2p = Provider.of<P2PProvider>(context, listen: false);
    final filePaths = _selectedFiles
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();

    if (_isLive) {
      // Live mode: post via P2P (broadcasts to students + saves to DB)
      await p2p.createPost(content, filePaths: filePaths);
    } else {
      // Offline mode: just save locally
      final postId = DateTime.now().millisecondsSinceEpoch.toString();
      final attachments = <Attachment>[];
      for (final path in filePaths) {
        final file = File(path);
        if (await file.exists()) {
          final fileName = path.split(Platform.pathSeparator).last;
          final ext = fileName.contains('.')
              ? fileName.split('.').last.toLowerCase()
              : 'unknown';
          final fileSize = await file.length();
          attachments.add(Attachment(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            postId: postId,
            fileName: fileName,
            fileType: ext,
            filePath: path,
            fileSize: fileSize,
          ));
        }
      }
      final post = Post(
        id: postId,
        classroomId: widget.classroom.id,
        content: content,
        attachments: attachments,
      );
      await _dbService.savePost(post);
    }

    _postController.clear();
    _selectedFiles.clear();
    await _loadLocalData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLive
              ? 'Post created & sent!'
              : 'Post saved locally'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _createAssignment() async {
    final title = _assignmentTitleController.text.trim();
    final desc = _assignmentDescController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title is required')));
      return;
    }

    final p2p = Provider.of<P2PProvider>(context, listen: false);
    final filePaths = _selectedFiles
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();

    if (_isLive) {
      await p2p.createAssignment(title, desc, _selectedDueDate, _selectedMaxScore, filePaths: filePaths);
    } else {
      final assignmentId = DateTime.now().millisecondsSinceEpoch.toString();
      final attachments = <Attachment>[];
      for (final path in filePaths) {
        final file = File(path);
        if (await file.exists()) {
          final fileName = path.split(Platform.pathSeparator).last;
          final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'unknown';
          final fileSize = await file.length();
          attachments.add(Attachment(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            assignmentId: assignmentId,
            fileName: fileName,
            fileType: ext,
            filePath: path,
            fileSize: fileSize,
          ));
        }
      }
      final assignment = Assignment(
        id: assignmentId,
        classroomId: widget.classroom.id,
        title: title,
        description: desc,
        dueDate: _selectedDueDate,
        maxScore: _selectedMaxScore,
        attachments: attachments,
      );
      await _dbService.saveAssignment(assignment);
    }

    _assignmentTitleController.clear();
    _assignmentDescController.clear();
    _selectedDueDate = null;
    _selectedMaxScore = null;
    _selectedFiles.clear();
    await _loadLocalData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLive ? 'Assignment sent!' : 'Assignment saved locally'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showQrCode() {
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile!;
        
    final qrData = jsonEncode({
      'teacherName': profile.displayName,
      'classroomName': widget.classroom.name,
      'password': widget.classroom.password,
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Classroom QR Code',
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
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
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Students can scan this code\nto join instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF6C63FF))),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'jpg', 'jpeg', 'png', 'mp3', 'mp4',
          'csv', 'docx', 'doc', 'ppt', 'pptx',
        ],
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _showPostDialog() {
    _showCreationDialog(isAssignment: false);
  }

  void _showAssignmentDialog() {
    _assignmentTitleController.clear();
    _assignmentDescController.clear();
    _selectedDueDate = null;
    _selectedMaxScore = 100;
    _showCreationDialog(isAssignment: true);
  }

  void _showCreationDialog({required bool isAssignment}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          final viewInsets = MediaQuery.of(context).viewInsets;
          return Container(
            padding: EdgeInsets.only(
              bottom: viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A40),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAssignment ? 'New Assignment' : 'New Announcement',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white54),
                        onPressed: () {
                          _selectedFiles.clear();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isAssignment) ...[
                    TextField(
                      controller: _assignmentTitleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Title',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3)),
                        filled: true,
                        fillColor: const Color(0xFF1E1E2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: isAssignment ? _assignmentDescController : _postController,
                    maxLines: isAssignment ? 4 : 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: isAssignment ? 'Instructions (optional)' : 'What do you want to share?',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (isAssignment) ...[
                    // Due Date and Max Score Row
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now().add(const Duration(days: 1)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setModalState(() => _selectedDueDate = date);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E2E),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today, color: Colors.white.withValues(alpha: 0.5), size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    _selectedDueDate == null ? 'Due Date' : DateFormat('MMM d, y').format(_selectedDueDate!),
                                    style: TextStyle(color: _selectedDueDate == null ? Colors.white54 : Colors.white),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            onChanged: (val) => _selectedMaxScore = double.tryParse(val),
                            decoration: InputDecoration(
                              hintText: 'Max Score (100)',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                              filled: true,
                              fillColor: const Color(0xFF1E1E2E),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_selectedFiles.isNotEmpty) ...[
                    const Text('Attachments',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_selectedFiles.length, (index) {
                        return _AttachmentChip(
                          fileName: _selectedFiles[index].name,
                          fileSize: _selectedFiles[index].size,
                          onRemove: () {
                            setModalState(() {
                              _removeFile(index);
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file, color: Color(0xFF00C9A7)),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(allowMultiple: true);
                          if (result != null) {
                            setModalState(() {
                              _selectedFiles.addAll(result.files);
                            });
                          }
                        },
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _isPosting
                            ? null
                            : () {
                                if (isAssignment) {
                                  _createAssignment();
                                } else {
                                  _createPost();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isPosting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                isAssignment ? 'Assign' : 'Post',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  /// Combine P2P live posts with local DB posts (avoiding duplicates)
  List<Post> _getMergedPosts(P2PProvider p2p) {
    if (_isLive && p2p.posts.isNotEmpty) {
      // When live, use P2P provider posts (they include newly broadcast posts)
      return p2p.posts;
    }
    return _localPosts;
  }

  /// Combine P2P live assignments with local DB
  List<Assignment> _getMergedAssignments(P2PProvider p2p) {
    if (_isLive) return p2p.assignments;
    return _localAssignments;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<P2PProvider>(
      builder: (context, p2p, _) {
        final posts = _getMergedPosts(p2p);

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
                                if (_isLive) p2p.stopAll();
                                Navigator.pop(context);
                              },
                            ),
                            Expanded(
                              child: Text(
                                widget.classroom.name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (_isLive)
                              IconButton(
                                icon: const Icon(
                                  Icons.qr_code_rounded,
                                  color: Color(0xFF00C9A7),
                                  size: 28,
                                ),
                                onPressed: _showQrCode,
                                tooltip: 'Show Login QR Code',
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Info chips row
                        Row(
                          children: [
                            _InfoChip(
                              icon: Icons.key_rounded,
                              label: widget.classroom.password,
                              color: const Color(0xFFFF6B6B),
                            ),
                            const SizedBox(width: 10),
                            if (_isLive)
                              _InfoChip(
                                icon: Icons.people_rounded,
                                label:
                                    '${p2p.connectedStudents.where((s) => s.isAuthenticated).length} students',
                                color: const Color(0xFF4ECB71),
                              ),
                            const SizedBox(width: 10),
                            _InfoChip(
                              icon: Icons.article_outlined,
                              label: '${posts.length} posts',
                              color: const Color(0xFF6C63FF),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Go Live / Go Offline button
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _isLive ? _goOffline : _goLive,
                            icon: Icon(
                              _isLive
                                  ? Icons.stop_rounded
                                  : Icons.wifi_tethering_rounded,
                            ),
                            label: Text(
                              _isLive
                                  ? 'Stop Broadcasting'
                                  : 'Go Live (Start P2P)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isLive
                                  ? Colors.red.shade700
                                  : const Color(0xFF00C9A7),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        if (_isLive) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color:
                                  Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p2p.statusMessage,
                                    style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),

                  // TabBarView Content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Posts view
                        _buildPostsView(posts),
                        
                        // Assignments view
                        _buildAssignmentsView(_getMergedAssignments(p2p)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // FAB for new post / assignment
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _tabController.index == 0 ? _showPostDialog : _showAssignmentDialog,
            backgroundColor: const Color(0xFF6C63FF),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text(
               _tabController.index == 0 ? 'New Post' : 'New Assignment',
               style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostsView(List<Post> posts) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.post_add_rounded,
              size: 64,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet.\nTap + to create your first announcement.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return _PostCard(
          post: post,
          formatTime: _formatTime,
        );
      },
    );
  }

  Widget _buildAssignmentsView(List<Assignment> assignments) {
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
              'No assignments yet.\nTap + to create your first assignment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: assignments.length,
      itemBuilder: (context, index) {
        final assignment = assignments[index];
        return _AssignmentCard(
          assignment: assignment,
          formatTime: _formatTime,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TeacherAssignmentDetailScreen(
                  assignment: assignment,
                ),
              ),
            );
          },
        );
      },
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

// ─── Post Card Widget ───

class _PostCard extends StatelessWidget {
  final Post post;
  final String Function(DateTime) formatTime;

  const _PostCard({
    required this.post,
    required this.formatTime,
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
            if (post.content.isNotEmpty) ...[
              Text(
                post.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              if (post.hasAttachments) const SizedBox(height: 12),
            ],

            // Attachment chips
            if (post.hasAttachments)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: post.attachments.map((attachment) {
                  return _FileAttachmentBadge(
                    fileName: attachment.fileName,
                    fileType: attachment.fileType,
                    fileSize: attachment.fileSizeFormatted,
                  );
                }).toList(),
              ),

            const SizedBox(height: 10),
            Text(
              formatTime(post.createdAt),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── File Attachment Badge (shown on posts) ───

class _FileAttachmentBadge extends StatelessWidget {
  final String fileName;
  final String fileType;
  final String fileSize;

  const _FileAttachmentBadge({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
  });

  IconData _getIcon() {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_rounded;
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
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFFF6B6B);
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Color(0xFF4ECB71);
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getIcon(), size: 16, color: color),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            fileSize,
            style: TextStyle(
              color: color.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Attachment Chip (in post dialog, removable) ───

class _AttachmentChip extends StatelessWidget {
  final String fileName;
  final int fileSize;
  final VoidCallback onRemove;

  const _AttachmentChip({
    required this.fileName,
    required this.fileSize,
    required this.onRemove,
  });

  String get _formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file_rounded,
                  size: 14, color: Color(0xFF6C63FF)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formattedSize,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Chip ───

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Assignment Card Widget ───

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final String Function(DateTime) formatTime;
  final VoidCallback onTap;

  const _AssignmentCard({
    required this.assignment,
    required this.formatTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A40),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          'Posted ${formatTime(assignment.createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              if (assignment.description.isNotEmpty) ...[
                Text(
                  assignment.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Meta Row
              Row(
                children: [
                  if (assignment.dueDate != null)
                    _InfoChip(
                      icon: Icons.calendar_today,
                      label: 'Due ${formatTime(assignment.dueDate!)}',
                      color: const Color(0xFFFF9F43),
                    ),
                  if (assignment.dueDate != null) const SizedBox(width: 8),
                  if (assignment.maxScore != null)
                    _InfoChip(
                      icon: Icons.score_rounded,
                      label: '${assignment.maxScore} pts',
                      color: const Color(0xFF00C9A7),
                    ),
                ],
              ),

              // Attachments
              if (assignment.hasAttachments) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attachments (${assignment.attachments.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...assignment.attachments.map((attachment) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _FileAttachmentBadge(
                            fileName: attachment.fileName,
                            fileType: attachment.fileType,
                            fileSize: attachment.fileSizeFormatted,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

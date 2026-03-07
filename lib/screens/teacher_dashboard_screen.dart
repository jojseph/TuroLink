import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../models/attachment.dart';
import '../models/classroom.dart';
import '../models/post.dart';
import '../models/assignment.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'teacher_assignment_detail_screen.dart';
import 'forum/forum_feed_view.dart';
import 'ai_chatbot_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';


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
  DateTime? _selectedScheduledDate;

  // This DatabaseService is not defined in the provided code, assuming it exists elsewhere.
  // For the purpose of this edit, it's left as is.
  final DatabaseService _dbService = DatabaseService();
  List<Post> _localPosts = [];
  List<Assignment> _localAssignments = [];
  bool _isLive = false;
  bool _isPosting = false;
  int _selectedNavIndex = 0;

  // Selected files for a new post/assignment
  List<PlatformFile> _selectedFiles = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    // PermissionService is not defined in the provided code, assuming it exists elsewhere.
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
      await p2p.createPost(content, filePaths: filePaths, scheduledDate: _selectedScheduledDate);
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
        scheduledDate: _selectedScheduledDate,
        attachments: attachments,
      );
      await _dbService.savePost(post);
    }

    _postController.clear();
    _selectedFiles.clear();
    _selectedScheduledDate = null;
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
      await p2p.createAssignment(title, desc, _selectedDueDate, _selectedMaxScore, filePaths: filePaths, scheduledDate: _selectedScheduledDate);
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
        scheduledDate: _selectedScheduledDate,
        attachments: attachments,
      );
      await _dbService.saveAssignment(assignment);
    }

    _assignmentTitleController.clear();
    _assignmentDescController.clear();
    _selectedDueDate = null;
    _selectedMaxScore = null;
    _selectedScheduledDate = null;
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
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Classroom QR Code',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
              // QrImageView is not defined in the provided code, assuming it exists elsewhere.
              child: SizedBox(
                width: 220,
                height: 220,
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 220.0,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF000000),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF000000),
                  ),
                  errorStateBuilder: (ctx, err) {
                    return Center(
                      child: Text(
                        'Error generating QR:\n${err.toString()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Students can scan this code\nto join instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
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
    _selectedScheduledDate = null;
    _showCreationDialog(isAssignment: false);
  }

  void _showAssignmentDialog() {
    _assignmentTitleController.clear();
    _assignmentDescController.clear();
    _selectedDueDate = null;
    _selectedMaxScore = 100;
    _selectedScheduledDate = null;
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
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.chevronLeft,
                            color: Colors.black),
                        onPressed: () {
                          _selectedFiles.clear();
                          _selectedScheduledDate = null;
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isAssignment) ...[
                    TextField(
                      controller: _assignmentTitleController,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Title',
                        hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: isAssignment ? 'Instructions (optional)' : 'What do you want to share?',
                      hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    _selectedDueDate == null ? 'Due Date' : DateFormat('MMM d, y').format(_selectedDueDate!),
                                    style: TextStyle(color: _selectedDueDate == null ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface),
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
                            style: const TextStyle(color: Colors.black),
                            onChanged: (val) => _selectedMaxScore = double.tryParse(val),
                            decoration: InputDecoration(
                              hintText: 'Max Score (100)',
                              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    Text('Attachments',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                        icon: Icon(Icons.attach_file, color: Theme.of(context).colorScheme.primary),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(allowMultiple: true);
                          if (result != null) {
                            setModalState(() {
                              _selectedFiles.addAll(result.files);
                            });
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.schedule, color: Colors.orange),
                        tooltip: 'Schedule Post/Assignment',
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (time != null) {
                              setModalState(() {
                                _selectedScheduledDate = DateTime(
                                  date.year, date.month, date.day, time.hour, time.minute
                                );
                              });
                            }
                          }
                        },
                      ),
                      if (_selectedScheduledDate != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              'Sch: ${DateFormat('MMM d, h:mm a').format(_selectedScheduledDate!)}',
                              style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                      else
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
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                                _selectedScheduledDate != null 
                                    ? 'Schedule' 
                                    : (isAssignment ? 'Assign' : 'Post'),
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

  Widget _buildClassroomView(P2PProvider p2p, List<Post> posts) {
    return SafeArea(
        bottom: false,
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
                        icon: const Icon(LucideIcons.chevronLeft,
                            color: Colors.black),
                        onPressed: () {
                          if (_isLive) p2p.stopAll();
                          Navigator.pop(context);
                        },
                      ),
                      Expanded(
                        child: Text(
                          widget.classroom.name,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      if (_isLive)
                        IconButton(
                          icon: Icon(
                            LucideIcons.qrCode,
                            color: Theme.of(context).colorScheme.primary,
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
                        icon: LucideIcons.key,
                        label: widget.classroom.password,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      if (_isLive)
                        _InfoChip(
                          icon: LucideIcons.users,
                          label:
                              '${p2p.connectedStudents.where((s) => s.isAuthenticated).length} students',
                          color: const Color(0xFF4ECB71),
                        ),
                      const SizedBox(width: 10),
                      _InfoChip(
                        icon: LucideIcons.fileText,
                        label: '${posts.length} posts',
                        color: const Color(0xFF6C63FF),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Go Live / Go Offline button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isLive ? _goOffline : _goLive,
                      icon: Icon(
                        _isLive
                            ? LucideIcons.stopCircle
                            : LucideIcons.radio,
                        color: _isLive ? Colors.black : Colors.white,
                      ),
                      label: Text(
                        _isLive
                            ? 'Stop Broadcasting'
                            : 'Go Live (Start P2P)',
                        style: const TextStyle(
                          fontSize: 16, // Added larger font size
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLive
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: _isLive
                            ? Theme.of(context).colorScheme.onError
                            : Theme.of(context).colorScheme.onPrimary,
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
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  TabBar(
                    controller: _tabController,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    tabs: const [
                      Tab(text: 'Announcements'),
                      Tab(text: 'Assignments'),
                      Tab(text: 'Forum'),
                    ],
                  ),
                ],
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
                  
                  // Forum view
                  // ForumFeedView is not defined in the provided code, assuming it exists elsewhere.
                  ForumFeedView(classroom: widget.classroom, isTeacher: true),
                ],
              ),
            ),
          ],
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<P2PProvider>(
      builder: (context, p2p, _) {
        final posts = _getMergedPosts(p2p);

        return Scaffold(
          body: IndexedStack(
            index: _selectedNavIndex,
            children: [
              _buildClassroomView(p2p, posts),
              // AiChatbotScreen is not defined in the provided code, assuming it exists elsewhere.
              const AiChatbotScreen(),
            ],
          ),

          // FAB only on Classroom tab and not on Forum tab (Forum has its own FAB)
          floatingActionButton: _selectedNavIndex == 0 && _tabController.index != 2
              ? FloatingActionButton.extended(
                  onPressed: _tabController.index == 0 ? _showPostDialog : _showAssignmentDialog,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  icon: const Icon(LucideIcons.plus, color: Colors.white),
                  label: Text(
                     _tabController.index == 0 ? 'New Post' : 'New Assignment',
                     style: const TextStyle(color: Colors.white),
                  ),
                )
              : null,

          // Bottom Navigation Bar
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
            ),
            child: BottomNavigationBar(
              currentIndex: _selectedNavIndex,
              onTap: (index) => setState(() => _selectedNavIndex = index),
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 4,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(LucideIcons.graduationCap),
                  activeIcon: Icon(LucideIcons.graduationCap),
                  label: 'Classroom',
                ),
                BottomNavigationBarItem(
                  icon: Icon(LucideIcons.sparkles),
                  activeIcon: Icon(LucideIcons.sparkles),
                  label: 'AI Assistant',
                ),
              ],
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
              LucideIcons.filePlus,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet.\nTap + to create your first announcement.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
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
              LucideIcons.clipboardList,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No assignments yet.\nTap + to create your first assignment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            // TeacherAssignmentDetailScreen is not defined in the provided code, assuming it exists elsewhere.
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TeacherAssignmentDetailScreen(
                  assignment: assignment,
                ),
              ),
            );
          },
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2),
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
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.school,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Teacher',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (post.scheduledDate != null && post.scheduledDate!.isAfter(DateTime.now()))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      'Scheduled for ${DateFormat('MMM d, y, h:mm a').format(post.scheduledDate!)}',
                      style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            if (post.content.isNotEmpty) ...[
              Text(
                post.content,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
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
                    filePath: attachment.filePath,
                  );
                }).toList(),
              ),

            const SizedBox(height: 10),
            Text(
              formatTime(post.createdAt),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final String filePath;

  const _FileAttachmentBadge({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.filePath,
  });

  IconData _getIcon() {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'mp3':
        return Icons.audiotrack;
      case 'mp4':
        return Icons.videocam;
      case 'csv':
        return Icons.table_chart;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
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
    return GestureDetector(
      onTap: () async {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open file: ${result.message}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
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
                color: color.withOpacity(0.6),
                fontSize: 10,
              ),
            ),
          ],
        ),
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
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file,
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
                child: const Icon(Icons.close,
                    size: 14, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formattedSize,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Teacher info & Status row (same as post)
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.school,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Teacher',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (assignment.scheduledDate != null && assignment.scheduledDate!.isAfter(DateTime.now()))
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 14, color: Colors.orange),
                      const SizedBox(width: 6),
                      Text(
                        'Scheduled for ${DateFormat('MMM d, y, h:mm a').format(assignment.scheduledDate!)}',
                        style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: assignment.type == 'quiz'
                            ? [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)]
                            : [const Color(0xFF6C63FF), const Color(0xFF5A52D5)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      assignment.type == 'quiz'
                          ? Icons.quiz
                          : Icons.assignment,
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Posted ${formatTime(assignment.createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              if (assignment.type == 'quiz') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8E53).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF8E53).withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.quiz, size: 16, color: Color(0xFFFF8E53)),
                      const SizedBox(width: 8),
                      Text(
                        'Quiz • ${assignment.maxScore?.toInt() ?? 0} questions',
                        style: const TextStyle(
                          color: Color(0xFFFF8E53),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (assignment.description.isNotEmpty) ...[
                Text(
                  assignment.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
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
                      icon: Icons.score,
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attachments (${assignment.attachments.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            filePath: attachment.filePath,
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

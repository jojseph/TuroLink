import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path_provider/path_provider.dart';
import '../models/classroom.dart';
import '../models/post.dart';
import '../models/attachment.dart';
import '../models/assignment.dart';
import '../models/submission.dart';
import '../services/p2p_service.dart';
import '../services/database_service.dart';
import 'package:uuid/uuid.dart';

/// Represents a discovered peer (teacher endpoint) for students
class DiscoveredPeer {
  final String endpointId;
  final String endpointName;
  final String serviceId;

  DiscoveredPeer({
    required this.endpointId,
    required this.endpointName,
    required this.serviceId,
  });
}

/// Represents a connected student (for teacher)
class ConnectedStudent {
  final String endpointId;
  String name;
  bool isAuthenticated;

  ConnectedStudent({
    required this.endpointId,
    required this.name,
    this.isAuthenticated = false,
  });
}

enum P2PState {
  idle,
  advertising,
  discovering,
  connecting,
  connected,
}

class P2PProvider extends ChangeNotifier {
  final P2PService _p2pService = P2PService();
  final DatabaseService _dbService = DatabaseService();
  final _uuid = const Uuid();

  P2PState _state = P2PState.idle;
  Classroom? _currentClassroom;
  String _statusMessage = '';

  bool _isStudentSyncHost = false;
  bool _isStudentSyncClient = false;

  final List<Post> _posts = [];
  final List<Assignment> _assignments = [];
  final List<Submission> _submissions = [];

  void _updateOrAddSubmission(Submission submission) {
    final index = _submissions.indexWhere((s) => s.id == submission.id);
    if (index != -1) {
      _submissions[index] = submission;
    } else {
      _submissions.add(submission);
    }
  }

  final List<DiscoveredPeer> _discoveredPeers = [];
  final List<ConnectedStudent> _connectedStudents = [];
  String? _teacherEndpointId; // For student to remember who the teacher is

  // File transfer tracking
  // Maps payloadId -> {attachmentId, postId, fileName, fileType, fileSize}
  final Map<int, Map<String, dynamic>> _pendingFileTransfers = {};
  
  // Track files that arrived before their metadata
  final Map<int, String> _unmatchedReceivedFiles = {};

  // QR Code Join Tracking
  String? _targetTeacherName;
  String? _scannedPassword;
  String? _scannedStudentName;
  // Maps postId -> list of attachments still in transfer
  final Map<String, int> _pendingAttachmentCounts = {};
  // Maps attachmentId -> progress (0.0 to 1.0)
  final Map<String, double> _fileTransferProgress = {};

  P2PState get state => _state;
  Classroom? get currentClassroom => _currentClassroom;
  String get statusMessage => _statusMessage;
  List<Post> get posts => List.unmodifiable(_posts);
  List<Assignment> get assignments => List.unmodifiable(_assignments);
  List<Submission> get submissions => List.unmodifiable(_submissions);
  List<DiscoveredPeer> get discoveredPeers =>
      List.unmodifiable(_discoveredPeers);
  List<ConnectedStudent> get connectedStudents =>
      List.unmodifiable(_connectedStudents);
  Map<String, double> get fileTransferProgress =>
      Map.unmodifiable(_fileTransferProgress);

  P2PProvider() {
    _setupCallbacks();
  }

  void _setupCallbacks() {
    _p2pService.onEndpointFound = _onEndpointFound;
    _p2pService.onEndpointLost = _onEndpointLost;
    _p2pService.onConnectionInitiated = _onConnectionInitiated;
    _p2pService.onConnectionResult = _onConnectionResult;
    _p2pService.onDisconnected = _onDisconnected;
    _p2pService.onMessageReceived = _onMessageReceived;
    _p2pService.onFileReceived = _onFileReceived;
    _p2pService.onFileTransferUpdate = _onFileTransferUpdate;
  }

  /// Teacher: Create classroom and start advertising
  Future<void> createAndAdvertise(
      Classroom classroom, String userName) async {
    _currentClassroom = classroom;
    _state = P2PState.advertising;
    _isStudentSyncHost = false;
    _isStudentSyncClient = false;
    _statusMessage = 'Starting P2P...';
    notifyListeners();

    // Load existing posts and assignments for this classroom
    _posts.clear();
    _posts.addAll(await _dbService.getPostsForClassroom(classroom.id));
    _assignments.clear();
    _assignments.addAll(await _dbService.getAssignmentsForClassroom(classroom.id));
    _submissions.clear();
    for (final assignment in _assignments) {
      _submissions.addAll(await _dbService.getSubmissionsForAssignment(assignment.id));
    }

    final started = await _p2pService.startAdvertising(userName);
    _statusMessage =
        started ? 'Broadcasting — waiting for students...' : 'Failed to start';
    notifyListeners();
  }

  /// Teacher: Create a new post and broadcast to all connected students
  Future<Post> createPost(String content,
      {List<String> filePaths = const []}) async {
    // Build attachments from file paths
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
          id: _uuid.v4(),
          postId: '', // will set after post ID is known
          fileName: fileName,
          fileType: ext,
          filePath: path,
          fileSize: fileSize,
        ));
      }
    }

    final postId = _uuid.v4();

    // Update attachment postIds
    final updatedAttachments = attachments
        .map((a) => Attachment(
              id: a.id,
              postId: postId,
              fileName: a.fileName,
              fileType: a.fileType,
              filePath: a.filePath,
              fileSize: a.fileSize,
            ))
        .toList();

    final post = Post(
      id: postId,
      classroomId: _currentClassroom!.id,
      content: content,
      attachments: updatedAttachments,
    );

    await _dbService.savePost(post);
    _posts.insert(0, post);

    // Broadcast to all authenticated students
    final authenticatedIds = _connectedStudents
        .where((s) => s.isAuthenticated)
        .map((s) => s.endpointId)
        .toList();

    if (authenticatedIds.isNotEmpty) {
      // 1️⃣ Send post metadata (text + attachment info) as bytes
      await _p2pService.broadcastMessage(
        authenticatedIds,
        P2PMessage(
          type: P2PMessageType.newPost,
          data: post.toJson(),
        ),
      );

      // 2️⃣ Send each attachment file
      for (final attachment in updatedAttachments) {
        for (final endpointId in authenticatedIds) {
          // Send the actual file first to get the payload ID
          final payloadId = await _p2pService.sendFilePayload(endpointId, attachment.filePath);
          
          if (payloadId != null) {
            // Then send file metadata explicitly linked to this payloadId
            await _p2pService.sendMessage(
              endpointId,
              P2PMessage(
                type: P2PMessageType.fileMetadata,
                data: {
                  'payloadId': payloadId,
                  'attachmentId': attachment.id,
                  'postId': postId,
                  'fileName': attachment.fileName,
                  'fileType': attachment.fileType,
                  'fileSize': attachment.fileSize,
                },
              ),
            );
          }
        }
      }
    }

    _statusMessage = 'Post created${updatedAttachments.isNotEmpty ? ' with ${updatedAttachments.length} file(s)' : ''}!';
    notifyListeners();
    return post;
  }

  /// Teacher: Create a new assignment and broadcast to all connected students
  Future<Assignment> createAssignment(String title, String description, DateTime? dueDate, double? maxScore,
      {List<String> filePaths = const []}) async {
    final attachments = <Attachment>[];
    for (final path in filePaths) {
      final file = File(path);
      if (await file.exists()) {
        final fileName = path.split(Platform.pathSeparator).last;
        final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'unknown';
        final fileSize = await file.length();
        attachments.add(Attachment(
          id: _uuid.v4(),
          assignmentId: '', // will set after assignment ID is known
          fileName: fileName,
          fileType: ext,
          filePath: path,
          fileSize: fileSize,
        ));
      }
    }

    final assignmentId = _uuid.v4();
    final updatedAttachments = attachments
        .map((a) => Attachment(
              id: a.id,
              assignmentId: assignmentId,
              fileName: a.fileName,
              fileType: a.fileType,
              filePath: a.filePath,
              fileSize: a.fileSize,
            ))
        .toList();

    final assignment = Assignment(
      id: assignmentId,
      classroomId: _currentClassroom!.id,
      title: title,
      description: description,
      dueDate: dueDate,
      maxScore: maxScore,
      attachments: updatedAttachments,
    );

    await _dbService.saveAssignment(assignment);
    _assignments.insert(0, assignment);

    final authenticatedIds = _connectedStudents
        .where((s) => s.isAuthenticated)
        .map((s) => s.endpointId)
        .toList();

    if (authenticatedIds.isNotEmpty) {
      await _p2pService.broadcastMessage(
        authenticatedIds,
        P2PMessage(
          type: P2PMessageType.newAssignment,
          data: assignment.toJson(),
        ),
      );

      for (final attachment in updatedAttachments) {
        for (final endpointId in authenticatedIds) {
          final payloadId = await _p2pService.sendFilePayload(endpointId, attachment.filePath);
          if (payloadId != null) {
            await _p2pService.sendMessage(
              endpointId,
              P2PMessage(
                type: P2PMessageType.fileMetadata,
                data: {
                  'payloadId': payloadId,
                  'attachmentId': attachment.id,
                  'assignmentId': assignmentId,
                  'fileName': attachment.fileName,
                  'fileType': attachment.fileType,
                  'fileSize': attachment.fileSize,
                },
              ),
            );
          }
        }
      }
    }

    _statusMessage = 'Assignment created${updatedAttachments.isNotEmpty ? ' with ${updatedAttachments.length} file(s)' : ''}!';
    notifyListeners();
    return assignment;
  }

  /// Student: Turn in an assignment
  Future<bool> turnInAssignment(Submission submission) async {
    // 1. Save it locally as not synced
    await _dbService.saveSubmission(submission);
    _updateOrAddSubmission(submission);
    
    // 2. Transmit to teacher if connected
    if (_state == P2PState.connected && _teacherEndpointId != null) {
      await _syncUnsyncedSubmissions(_teacherEndpointId!);
    }
    notifyListeners();
    return true;
  }

  /// Student: Start discovering nearby teachers
  Future<void> startDiscovering(String userName) async {
    _state = P2PState.discovering;
    _discoveredPeers.clear();
    _statusMessage = 'Scanning for nearby classrooms...';
    notifyListeners();

    await _p2pService.startDiscovery(userName);
  }

  /// Student: Start advertising to share with peers
  Future<void> startStudentSyncAdvertising(Classroom classroom, String userName) async {
    _currentClassroom = classroom;
    _state = P2PState.advertising;
    _isStudentSyncHost = true;
    _isStudentSyncClient = false;
    _statusMessage = 'Sharing updates...';
    notifyListeners();

    _posts.clear();
    _posts.addAll(await _dbService.getPostsForClassroom(classroom.id));
    _assignments.clear();
    _assignments.addAll(await _dbService.getAssignmentsForClassroom(classroom.id));

    final started = await _p2pService.startAdvertising("[SYNC]$userName");
    _statusMessage =
        started ? 'Broadcasting for peers...' : 'Failed to start sharing';
    notifyListeners();
  }

  /// Student: Join a student sync via QR Code
  Future<void> joinStudentSync(String hostName, Classroom classroom, String tempStudentName) async {
    _currentClassroom = classroom;
    _targetTeacherName = "[SYNC]$hostName";
    _scannedPassword = classroom.password; // We use the classroom password
    _scannedStudentName = tempStudentName;
    _isStudentSyncHost = false;
    _isStudentSyncClient = true;

    // Pre-load our posts so we can send them to the host if needed!
    _posts.clear();
    _posts.addAll(await _dbService.getPostsForClassroom(classroom.id));
    _assignments.clear();
    _assignments.addAll(await _dbService.getAssignmentsForClassroom(classroom.id));
    
    await startDiscovering(tempStudentName);
  }

  /// Student: Join via QR Code instantly
  Future<void> joinViaQRCode(
      String teacherName, String classroomName, String password, String studentName) async {
    _targetTeacherName = teacherName;
    _scannedPassword = password;
    _scannedStudentName = studentName;
    
    await startDiscovering(studentName);
  }

  /// Student: Connect to a discovered teacher
  Future<void> connectToPeer(
      String endpointId, String userName) async {
    _state = P2PState.connecting;
    _statusMessage = 'Connecting...';
    notifyListeners();
    await _p2pService.requestConnection(userName, endpointId);
  }

  /// Student: Send join request with password
  Future<void> sendJoinRequest(
      String endpointId, String password, String studentName) async {
    final profile = await _dbService.getProfile();
    final deviceId = profile?.deviceId ?? 'unknown';

    await _p2pService.sendMessage(
      endpointId,
      P2PMessage(
        type: P2PMessageType.joinRequest,
        data: {
          'password': password,
          'studentName': studentName,
          'deviceId': deviceId,
        },
      ),
    );
    _statusMessage = 'Join request sent, waiting for approval...';
    notifyListeners();
  }

  // ─── P2P Event Handlers ───

  void _onEndpointFound(
      String endpointId, String endpointName, String serviceId) {
    // Avoid duplicates
    if (!_discoveredPeers.any((p) => p.endpointId == endpointId)) {
      _discoveredPeers.add(DiscoveredPeer(
        endpointId: endpointId,
        endpointName: endpointName,
        serviceId: serviceId,
      ));
      notifyListeners();

      // Auto-connect if it matches our scanned QR code target
      if (_targetTeacherName != null && endpointName == _targetTeacherName) {
        String currentName = _scannedStudentName ?? "Student";
        connectToPeer(endpointId, currentName);
      }
    }
  }

  void _onEndpointLost(String endpointId) {
    _discoveredPeers.removeWhere((p) => p.endpointId == endpointId);
    notifyListeners();
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    // Auto-accept all connections — authentication happens via join request
    _p2pService.acceptConnection(endpointId);
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      debugPrint('[P2PProvider] Connected to $endpointId');

      if (_state == P2PState.advertising) {
        // Teacher side: add the student (not authenticated yet)
        _connectedStudents.add(ConnectedStudent(
          endpointId: endpointId,
          name: 'Unknown',
        ));
        _statusMessage = 'A student connected — awaiting authentication...';

        // Send classroom info
        if (_currentClassroom != null) {
          _p2pService.sendMessage(
            endpointId,
            P2PMessage(
              type: P2PMessageType.classroomInfo,
              data: _currentClassroom!.toMap(),
            ),
          );
        }
      } else {
        // Student side
        _state = P2PState.connected;
        _teacherEndpointId = endpointId;
        _statusMessage = 'Connected to teacher!';
      }
      notifyListeners();
    } else {
      _statusMessage = 'Connection failed.';
      notifyListeners();
    }
  }

  void _onDisconnected(String endpointId) {
    _connectedStudents.removeWhere((s) => s.endpointId == endpointId);
    if (_teacherEndpointId == endpointId) {
      _teacherEndpointId = null;
    }
    if (_state == P2PState.connected) {
      _state = P2PState.idle;
      _statusMessage = 'Disconnected from teacher.';
    }
    notifyListeners();
  }

  void _onMessageReceived(String endpointId, P2PMessage message) {
    switch (message.type) {
      case P2PMessageType.classroomInfo:
        // Student receives classroom info from teacher
        final classroom =
            Classroom.fromMap(Map<String, dynamic>.from(message.data));
        _currentClassroom = classroom;
        
        if (_scannedPassword != null) {
          // Auto-send join request if we scanned a QR code
          sendJoinRequest(endpointId, _scannedPassword!, _scannedStudentName ?? "Student");
          _statusMessage = 'Joining ${classroom.name} automatically...';
        } else {
          _statusMessage =
              'Connected to: ${classroom.name}. Enter password to join.';
        }
        notifyListeners();
        break;

      case P2PMessageType.joinRequest:
        // Teacher receives join request from student
        _handleJoinRequest(endpointId, message.data);
        break;

      case P2PMessageType.joinAccepted:
        // Student: join accepted
        _state = P2PState.connected;
        if (_currentClassroom != null) {
          _dbService.saveClassroom(_currentClassroom!);
        }
        _statusMessage = 'Joined classroom!';

        // TWO WAY SYNC: If we are a student sync client, send OUR posts back to the host!
        if (_isStudentSyncClient) {
          _p2pService.sendMessage(
            endpointId,
            P2PMessage(
              type: P2PMessageType.syncAllPosts,
              data: {
                'posts': _posts.map((p) => p.toJson()).toList(),
              },
            ),
          );
          _p2pService.sendMessage(
            endpointId,
            P2PMessage(
              type: P2PMessageType.syncAssignments,
              data: {
                'assignments': _assignments.map((a) => a.toJson()).toList(),
              },
            ),
          );
        } else {
          // Connected to teacher: sync our unsynced submissions!
          _syncUnsyncedSubmissions(endpointId);
        }
        
        // Reset QR tracking variables
        _targetTeacherName = null;
        _scannedPassword = null;
        _scannedStudentName = null;
        
        notifyListeners();
        break;

      case P2PMessageType.joinRejected:
        _statusMessage = 'Join request rejected. Wrong password?';
        
        // Reset QR tracking variables so they can try again manually
        _targetTeacherName = null;
        _scannedPassword = null;
        _scannedStudentName = null;
        
        notifyListeners();
        break;

      case P2PMessageType.newPost:
        // Student receives a new post
        final post = Post.fromJson(message.data);
        _dbService.savePost(post);

        if (!_posts.any((p) => p.id == post.id)) {
          _posts.insert(0, post);
        }
        _statusMessage = 'New post received!';
        notifyListeners();
        break;

      case P2PMessageType.syncAllPosts:
        // Student receives all posts
        final postsJson = message.data['posts'] as List;
        final syncedPosts = postsJson
            .map((p) => Post.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList();

        // TWO-WAY SYNC MERGE LOGIC
        int newPostsCount = 0;
        final missingAttachmentIds = <String>[];

        for (final post in syncedPosts) {
          if (!_posts.any((p) => p.id == post.id)) {
            newPostsCount++;
            _dbService.savePost(post);
            _posts.insert(0, post);
          }
          
          // Check if we need to request any file attachments we don't physically have
          for (final attachment in post.attachments) {
            final file = File(attachment.filePath);
            if (!file.existsSync()) {
               missingAttachmentIds.add(attachment.id);
            }
          }
        }

        _posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _statusMessage = 'Synced! $newPostsCount new post(s).';

        if (missingAttachmentIds.isNotEmpty && (_isStudentSyncClient || _isStudentSyncHost)) {
           _p2pService.sendMessage(endpointId, P2PMessage(
              type: P2PMessageType.requestFiles,
              data: {'attachmentIds': missingAttachmentIds},
           ));
        }

        notifyListeners();
        break;

      case P2PMessageType.newAssignment:
        final assignment = Assignment.fromJson(message.data);
        _dbService.saveAssignment(assignment);
        if (!_assignments.any((a) => a.id == assignment.id)) {
          _assignments.insert(0, assignment);
        }
        _statusMessage = 'New assignment received!';
        notifyListeners();
        break;

      case P2PMessageType.syncAssignments:
        final assignmentsJson = message.data['assignments'] as List;
        final syncedAssignments = assignmentsJson
            .map((a) => Assignment.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList();

        int newCount = 0;
        final missingAttachmentIds = <String>[];
        for (final assignment in syncedAssignments) {
          if (!_assignments.any((a) => a.id == assignment.id)) {
            newCount++;
            _dbService.saveAssignment(assignment);
            _assignments.insert(0, assignment);
          }
          for (final attachment in assignment.attachments) {
            final file = File(attachment.filePath);
            if (!file.existsSync()) {
              missingAttachmentIds.add(attachment.id);
            }
          }
        }
        _assignments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (newCount > 0) _statusMessage = 'Synced! $newCount new assignment(s).';

        if (missingAttachmentIds.isNotEmpty && (_isStudentSyncClient || _isStudentSyncHost)) {
           _p2pService.sendMessage(endpointId, P2PMessage(
              type: P2PMessageType.requestFiles,
              data: {'attachmentIds': missingAttachmentIds},
           ));
        }
        notifyListeners();
        break;

      case P2PMessageType.turnInSubmission:
        // Teacher receives a submission
        final submission = Submission.fromJson(message.data);
        _dbService.saveSubmission(submission);
        _updateOrAddSubmission(submission);
        _statusMessage = '${submission.studentName} turned in an assignment!';
        // Send ACK back
        _p2pService.sendMessage(
           endpointId,
           P2PMessage(
             type: P2PMessageType.submissionReceived,
             data: {'submissionId': submission.id},
           )
        );
        notifyListeners();
        break;

      case P2PMessageType.submissionReceived:
        // Student receives ack from teacher -> mark as synced
        final submissionId = message.data['submissionId'] as String;
        _dbService.markSubmissionSynced(submissionId);
        _statusMessage = 'Submission delivered to teacher!';
        notifyListeners();
        break;

      case P2PMessageType.returnSubmission:
        // Student receives a graded submission
        final submission = Submission.fromJson(message.data);
        _dbService.saveSubmission(submission);
        _updateOrAddSubmission(submission);
        _statusMessage = 'An assignment was graded/returned!';
        notifyListeners();
        break;

      case P2PMessageType.syncReturnedSubmissions:
        // Student receives all their returned submissions
        final subsJson = message.data['submissions'] as List;
        for (final sJson in subsJson) {
          final sub = Submission.fromJson(Map<String, dynamic>.from(sJson as Map));
          _dbService.saveSubmission(sub);
          _updateOrAddSubmission(sub);
        }
        notifyListeners();
        break;

      case P2PMessageType.fileMetadata:
        // Student receives metadata about an incoming file
        _handleFileMetadata(endpointId, message.data);
        break;

      case P2PMessageType.requestFiles:
        _handleRequestFiles(endpointId, message);
        break;
    }
  }

  /// Handle file requests (student syncing)
  Future<void> _handleRequestFiles(String endpointId, P2PMessage message) async {
    final attachmentIds = List<String>.from(message.data['attachmentIds']);
    for (final id in attachmentIds) {
      bool found = false;
      // Search in posts
      for (final post in _posts) {
        final attachments = post.attachments.where((a) => a.id == id).toList();
        if (attachments.isNotEmpty) {
          final attachment = attachments.first;
          final file = File(attachment.filePath);
          if (file.existsSync()) {
            final payloadId = await _p2pService.sendFilePayload(endpointId, attachment.filePath);
            if (payloadId != null) {
              await _p2pService.sendMessage(
                endpointId,
                P2PMessage(
                  type: P2PMessageType.fileMetadata,
                  data: {
                    'payloadId': payloadId,
                    'attachmentId': attachment.id,
                    'postId': post.id,
                    'fileName': attachment.fileName,
                    'fileType': attachment.fileType,
                    'fileSize': attachment.fileSize,
                  },
                ),
              );
            }
          }
          found = true;
          break;
        }
      }

      if (found) continue;

      // Search in assignments
      for (final assignment in _assignments) {
        final attachments = assignment.attachments.where((a) => a.id == id).toList();
        if (attachments.isNotEmpty) {
          final attachment = attachments.first;
          final file = File(attachment.filePath);
          if (file.existsSync()) {
            final payloadId = await _p2pService.sendFilePayload(endpointId, attachment.filePath);
            if (payloadId != null) {
              await _p2pService.sendMessage(
                endpointId,
                P2PMessage(
                  type: P2PMessageType.fileMetadata,
                  data: {
                    'payloadId': payloadId,
                    'attachmentId': attachment.id,
                    'assignmentId': assignment.id,
                    'fileName': attachment.fileName,
                    'fileType': attachment.fileType,
                    'fileSize': attachment.fileSize,
                  },
                ),
              );
            }
          }
          break;
        }
      }
    }
  }

  void _handleFileMetadata(String endpointId, Map<String, dynamic> data) {
    final payloadId = data['payloadId'] as int;
    final attachmentId = data['attachmentId'] as String;
    final postId = data['postId'] as String?;
    final assignmentId = data['assignmentId'] as String?;
    final submissionId = data['submissionId'] as String?;
    final fileName = data['fileName'] as String;
    final fileType = data['fileType'] as String;
    final fileSize = data['fileSize'] as int;

    // Store precisely by payloadId
    _pendingFileTransfers[payloadId] = {
      'payloadId': payloadId,
      'attachmentId': attachmentId,
      'postId': postId,
      'assignmentId': assignmentId,
      'submissionId': submissionId,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'endpointId': endpointId,
    };

    debugPrint('[P2PProvider] Expecting file: $fileName for post/assign $postId/$assignmentId (payloadId: $payloadId)');

    if (_unmatchedReceivedFiles.containsKey(payloadId)) {
      debugPrint('[P2PProvider] File payload already received, processing now');
      final tempFilePath = _unmatchedReceivedFiles.remove(payloadId)!;
      _onFileReceived(endpointId, payloadId, tempFilePath);
    }
  }

  /// Handle received file payload (student side)
  void _onFileReceived(
      String endpointId, int payloadId, String tempFilePath) async {
    debugPrint('[P2PProvider] File received: payloadId=$payloadId, path=$tempFilePath');

    // Remove the tracking for this payloadId
    final metadata = _pendingFileTransfers.remove(payloadId);
    if (metadata == null) {
      debugPrint('[P2PProvider] No metadata for received file, skipping');
      _unmatchedReceivedFiles[payloadId] = tempFilePath;
      return;
    }

    final attachmentId = metadata['attachmentId'] as String;
    _fileTransferProgress.remove(attachmentId);
    notifyListeners();

    try {
      // Move file to app's storage directory with proper name
      final receivedDir = await P2PService.getReceivedFilesDir();
      final fileName = metadata['fileName'] as String;
      final attachmentId = metadata['attachmentId'] as String;
      final fileType = metadata['fileType'] as String;
      final fileSize = metadata['fileSize'] as int;

      String targetPath = '$receivedDir/${attachmentId}_$fileName';

      // Ensure the targetPath has the correct file extension for OpenFilex to work
      if (fileType != 'unknown' && !targetPath.toLowerCase().endsWith('.$fileType')) {
        targetPath = '$targetPath.$fileType';
        debugPrint('[P2PProvider] Adjusted targetPath to include extension: $targetPath');
      }

      // The nearby_connections plugin saves files with the payloadId as name
      // If it returns a content:// URI on Android 10+, we must use the plugin's native copy method
      if (tempFilePath.startsWith('content://')) {
        await Nearby().copyFileAndDeleteOriginal(tempFilePath, targetPath);
      } else {
        final tempFile = File(tempFilePath);
        if (await tempFile.exists()) {
          await tempFile.copy(targetPath);
          await tempFile.delete();
        }
      }

      // Create and save attachment record
      final attachment = Attachment(
        id: attachmentId,
        postId: metadata['postId'] as String?,
        assignmentId: metadata['assignmentId'] as String?,
        submissionId: metadata['submissionId'] as String?,
        fileName: fileName,
        fileType: fileType,
        filePath: targetPath,
        fileSize: fileSize,
      );
      await _dbService.saveAttachment(attachment);

      // Update the post/assignment/submission in our list to include this attachment
      if (attachment.postId != null) {
        final postId = attachment.postId!;
        final postIndex = _posts.indexWhere((p) => p.id == postId);
        if (postIndex != -1) {
          final existingPost = _posts[postIndex];
          final updatedAttachments = existingPost.attachments
              .where((a) => a.id != attachment.id)
              .toList()
            ..add(attachment);
            
          final updatedPost = Post(
            id: existingPost.id,
            classroomId: existingPost.classroomId,
            content: existingPost.content,
            createdAt: existingPost.createdAt,
            attachments: updatedAttachments,
          );
          _posts[postIndex] = updatedPost;
        }
      } else if (attachment.assignmentId != null) {
        final assignmentId = attachment.assignmentId!;
        final index = _assignments.indexWhere((a) => a.id == assignmentId);
        if (index != -1) {
          final existing = _assignments[index];
          final updatedAttachments = existing.attachments
              .where((a) => a.id != attachment.id)
              .toList()
            ..add(attachment);
            
          final updated = Assignment(
            id: existing.id,
            classroomId: existing.classroomId,
            title: existing.title,
            description: existing.description,
            dueDate: existing.dueDate,
            maxScore: existing.maxScore,
            createdAt: existing.createdAt,
            attachments: updatedAttachments,
          );
          _assignments[index] = updated;
        }
      } else if (attachment.submissionId != null) {
        final submissionId = attachment.submissionId!;
        final index = _submissions.indexWhere((s) => s.id == submissionId);
        if (index != -1) {
          final existing = _submissions[index];
          final updatedAttachments = existing.attachments
              .where((a) => a.id != attachment.id)
              .toList()
            ..add(attachment);
            
          final updated = Submission(
            id: existing.id,
            assignmentId: existing.assignmentId,
            studentDeviceId: existing.studentDeviceId,
            studentName: existing.studentName,
            content: existing.content,
            submittedAt: existing.submittedAt,
            score: existing.score,
            isReturned: existing.isReturned,
            attachments: updatedAttachments,
          );
          _submissions[index] = updated;
        }
      }

      _statusMessage = 'File received: $fileName';
      notifyListeners();
    } catch (e) {
      debugPrint('[P2PProvider] Error handling received file: $e');
    }
  }

  /// File transfer progress callback
  void _onFileTransferUpdate(
      String endpointId, int payloadId, int bytesTransferred, int totalBytes) {
    
    final metadata = _pendingFileTransfers[payloadId];
    if (metadata != null) {
      final percent = totalBytes > 0 ? (bytesTransferred / totalBytes) : 0.0;
      final attachmentId = metadata['attachmentId'] as String;
      _fileTransferProgress[attachmentId] = percent;
      notifyListeners();
    } else {
      debugPrint('[P2PProvider] Warning: progress update for unknown payloadId $payloadId');
    }
  }

  /// Teacher: handle join request with password check
  Future<void> _handleJoinRequest(
      String endpointId, Map<String, dynamic> data) async {
    final password = data['password'] as String;
    final studentName = data['studentName'] as String;
    final deviceId = data['deviceId'] as String?;

    // Update student name
    final idx =
        _connectedStudents.indexWhere((s) => s.endpointId == endpointId);
    if (idx != -1) {
      _connectedStudents[idx].name = studentName;
    }

    if (_currentClassroom != null &&
        password == _currentClassroom!.password) {
      // Accepted
      if (idx != -1) {
        _connectedStudents[idx].isAuthenticated = true;
      }

      _p2pService.sendMessage(
        endpointId,
        P2PMessage(type: P2PMessageType.joinAccepted, data: {}),
      );

      _statusMessage = '$studentName joined the classroom!';

      // Send all existing posts
      _p2pService.sendMessage(
        endpointId,
        P2PMessage(
          type: P2PMessageType.syncAllPosts,
          data: {
            'posts': _posts.map((p) => p.toJson()).toList(),
          },
        ),
      );

      // Send all assignments
      _p2pService.sendMessage(
        endpointId,
        P2PMessage(
          type: P2PMessageType.syncAssignments,
          data: {
            'assignments': _assignments.map((a) => a.toJson()).toList(),
          },
        ),
      );

      // Fetch and send only this student's returned submissions
      if (deviceId != null) {
        final returnedSubs = await _dbService.getReturnedSubmissionsForStudent(deviceId);
        if (returnedSubs.isNotEmpty) {
          _p2pService.sendMessage(
            endpointId,
            P2PMessage(
              type: P2PMessageType.syncReturnedSubmissions,
              data: {
                'submissions': returnedSubs.map((s) => s.toJson()).toList(),
              },
            ),
          );
        }
      }

      // Send all file attachments for existing posts and assignments
      _sendAllPostFilesToEndpoint(endpointId);
    } else {
      // Rejected
      _p2pService.sendMessage(
        endpointId,
        P2PMessage(type: P2PMessageType.joinRejected, data: {}),
      );
      _statusMessage = 'Rejected join request from $studentName';
    }
    notifyListeners();
  }

  /// Send all file attachments for existing posts to a newly joined student (Teacher only)
  Future<void> _sendAllPostFilesToEndpoint(String endpointId) async {
    // If this is a student sync, we wait for the client to REQUEST the missing files instead of blindly sending
    if (_isStudentSyncHost || _isStudentSyncClient) return;

    for (final post in _posts) {
      for (final attachment in post.attachments) {
        await _sendFileWithMetadata(endpointId, attachment, post.id, null);
      }
    }
    
    for (final assignment in _assignments) {
      for (final attachment in assignment.attachments) {
        await _sendFileWithMetadata(endpointId, attachment, null, assignment.id);
      }
    }
  }

  Future<void> _sendFileWithMetadata(String endpointId, Attachment attachment, String? postId, String? assignmentId) async {
    final file = File(attachment.filePath);
    if (await file.exists()) {
      // Send file first to get ID
      final payloadId = await _p2pService.sendFilePayload(endpointId, attachment.filePath);
      
      if (payloadId != null) {
        // Then send explicit metadata
        await _p2pService.sendMessage(
          endpointId,
          P2PMessage(
            type: P2PMessageType.fileMetadata,
            data: {
              'payloadId': payloadId,
              'attachmentId': attachment.id,
              if (postId != null) 'postId': postId,
              if (assignmentId != null) 'assignmentId': assignmentId,
              'fileName': attachment.fileName,
              'fileType': attachment.fileType,
              'fileSize': attachment.fileSize,
            },
          ),
        );
      }
    }
  }

  /// Send our unsynced submissions to the teacher
  Future<void> _syncUnsyncedSubmissions(String teacherEndpointId) async {
    final unsynced = await _dbService.getUnsyncedSubmissions();
    for (final sub in unsynced) {
      await _p2pService.sendMessage(
        teacherEndpointId,
        P2PMessage(
          type: P2PMessageType.turnInSubmission,
          data: sub.toJson(),
        ),
      );
      
      for (final attachment in sub.attachments) {
        final payloadId = await _p2pService.sendFilePayload(teacherEndpointId, attachment.filePath);
        if (payloadId != null) {
           await _p2pService.sendMessage(
            teacherEndpointId,
            P2PMessage(
              type: P2PMessageType.fileMetadata,
              data: {
                'payloadId': payloadId,
                'attachmentId': attachment.id,
                'submissionId': sub.id,
                'fileName': attachment.fileName,
                'fileType': attachment.fileType,
                'fileSize': attachment.fileSize,
              },
            ),
          );
        }
      }
    }
  }

  /// Teacher returns a graded submission
  Future<void> returnSubmission(Submission submission, double score) async {
    submission = Submission(
      id: submission.id,
      assignmentId: submission.assignmentId,
      studentDeviceId: submission.studentDeviceId,
      studentName: submission.studentName,
      content: submission.content,
      submittedAt: submission.submittedAt,
      score: score,
      isReturned: true,
      isSynced: true,
      attachments: submission.attachments,
    );
    await _dbService.saveSubmission(submission);
    _updateOrAddSubmission(submission);

    // Try to find the student's endpoint by name
    String? studentEndpointId;
    try {
      studentEndpointId = _connectedStudents.firstWhere((s) => s.name == submission.studentName).endpointId;
    } catch (_) {}

    // If student is currently connected, send it live
    if (studentEndpointId != null) {
      await _p2pService.sendMessage(
        studentEndpointId,
        P2PMessage(
          type: P2PMessageType.returnSubmission,
          data: submission.toJson(),
        ),
      );
    }
    notifyListeners();
  }

  /// Set classroom for student (used after authentication)
  void setClassroom(Classroom classroom) {
    _currentClassroom = classroom;
    notifyListeners();
  }

  /// Load posts from local DB
  Future<void> loadLocalPosts(String classroomId) async {
    _posts.clear();
    _posts.addAll(await _dbService.getPostsForClassroom(classroomId));
    notifyListeners();
  }

  /// Stop only discovery (keep connections active)
  Future<void> stopDiscovery() async {
    await _p2pService.stopDiscovery();
    if (_state == P2PState.discovering) {
      _state = P2PState.idle;
      _statusMessage = 'Stopped scanning.';
      notifyListeners();
    }
  }

  /// Stop everything
  Future<void> stopAll() async {
    await _p2pService.stopAll();
    _state = P2PState.idle;
    _discoveredPeers.clear();
    _connectedStudents.clear();
    _teacherEndpointId = null;
    _pendingFileTransfers.clear();
    _unmatchedReceivedFiles.clear();
    _pendingAttachmentCounts.clear();
    _isStudentSyncHost = false;
    _isStudentSyncClient = false;
    _statusMessage = 'Disconnected.';
    notifyListeners();
  }

  @override
  void dispose() {
    _p2pService.stopAll();
    super.dispose();
  }
}

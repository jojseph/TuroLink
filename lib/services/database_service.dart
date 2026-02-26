import 'package:sqflite/sqflite.dart';
import '../models/classroom.dart';
import '../models/post.dart';
import '../models/attachment.dart';
import '../models/user_profile.dart';
import '../models/assignment.dart';
import '../models/submission.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/p2p_classroom.db';

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE user_profile (
            deviceId TEXT PRIMARY KEY,
            displayName TEXT NOT NULL,
            isTeacher INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE classrooms (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            password TEXT NOT NULL,
            teacherId TEXT NOT NULL,
            teacherName TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE posts (
            id TEXT PRIMARY KEY,
            classroomId TEXT NOT NULL,
            content TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY (classroomId) REFERENCES classrooms (id)
          )
        ''');
        await _createAttachmentsTable(db);
        await _createAssignmentsTable(db);
        await _createSubmissionsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createAttachmentsTable(db);
        }
        if (oldVersion < 3) {
          await _createAssignmentsTable(db);
          await _createSubmissionsTable(db);
          
          // Alter attachments table to support assignmentId and submissionId
          // SQLite doesn't let us easily drop NOT NULL from postId, so we 
          // recreate the table by renaming the old one.
          await db.execute('ALTER TABLE attachments RENAME TO _attachments_old');
          await _createAttachmentsTable(db);
          await db.execute('''
            INSERT INTO attachments (id, postId, fileName, fileType, filePath, fileSize)
            SELECT id, postId, fileName, fileType, filePath, fileSize FROM _attachments_old
          ''');
          await db.execute('DROP TABLE _attachments_old');
        }
      },
    );
  }

  Future<void> _createAttachmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY,
        postId TEXT,
        assignmentId TEXT,
        submissionId TEXT,
        fileName TEXT NOT NULL,
        fileType TEXT NOT NULL,
        filePath TEXT NOT NULL,
        fileSize INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createAssignmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assignments (
        id TEXT PRIMARY KEY,
        classroomId TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        dueDate TEXT,
        maxScore REAL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSubmissionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS submissions (
        id TEXT PRIMARY KEY,
        assignmentId TEXT NOT NULL,
        studentDeviceId TEXT NOT NULL,
        studentName TEXT NOT NULL,
        content TEXT NOT NULL,
        submittedAt TEXT NOT NULL,
        score REAL,
        isReturned INTEGER NOT NULL DEFAULT 0,
        isSynced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // ─── User Profile ───

  Future<void> saveProfile(UserProfile profile) async {
    final db = await database;
    await db.insert('user_profile', profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<UserProfile?> getProfile() async {
    final db = await database;
    final maps = await db.query('user_profile', limit: 1);
    if (maps.isEmpty) return null;
    return UserProfile.fromMap(maps.first);
  }

  // ─── Classrooms ───

  Future<void> saveClassroom(Classroom classroom) async {
    final db = await database;
    await db.insert('classrooms', classroom.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Classroom?> getClassroom(String id) async {
    final db = await database;
    final maps = await db.query('classrooms', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Classroom.fromMap(maps.first);
  }

  Future<List<Classroom>> getAllClassrooms() async {
    final db = await database;
    final maps = await db.query('classrooms', orderBy: 'createdAt DESC');
    return maps.map((m) => Classroom.fromMap(m)).toList();
  }

  /// Get classrooms created by a specific teacher
  Future<List<Classroom>> getClassroomsByTeacher(String teacherId) async {
    final db = await database;
    final maps = await db.query('classrooms',
        where: 'teacherId = ?',
        whereArgs: [teacherId],
        orderBy: 'createdAt DESC');
    return maps.map((m) => Classroom.fromMap(m)).toList();
  }

  /// Get classrooms NOT created by the given user (joined as student)
  Future<List<Classroom>> getJoinedClassrooms(String myDeviceId) async {
    final db = await database;
    final maps = await db.query('classrooms',
        where: 'teacherId != ?',
        whereArgs: [myDeviceId],
        orderBy: 'createdAt DESC');
    return maps.map((m) => Classroom.fromMap(m)).toList();
  }

  /// Get post count for a classroom
  Future<int> getPostCount(String classroomId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM posts WHERE classroomId = ?',
        [classroomId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ─── Posts ───

  Future<void> savePost(Post post) async {
    final db = await database;
    await db.insert('posts', post.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    // Save attachments if any
    for (final attachment in post.attachments) {
      await db.insert('attachments', attachment.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Post>> getPostsForClassroom(String classroomId) async {
    final db = await database;
    final maps = await db.query(
      'posts',
      where: 'classroomId = ?',
      whereArgs: [classroomId],
      orderBy: 'createdAt DESC',
    );

    final posts = <Post>[];
    for (final m in maps) {
      final postId = m['id'] as String;
      final attachments = await getAttachmentsForPost(postId);
      posts.add(Post.fromMap(m, attachments: attachments));
    }
    return posts;
  }

  Future<void> savePosts(List<Post> posts) async {
    final db = await database;
    final batch = db.batch();
    for (final post in posts) {
      batch.insert('posts', post.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (final attachment in post.attachments) {
        batch.insert('attachments', attachment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  // ─── Assignments ───

  Future<void> saveAssignment(Assignment assignment) async {
    final db = await database;
    await db.insert('assignments', assignment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    for (final attachment in assignment.attachments) {
      batchInsertAttachment(db, attachment);
    }
  }

  Future<List<Assignment>> getAssignmentsForClassroom(String classroomId) async {
    final db = await database;
    final maps = await db.query(
      'assignments',
      where: 'classroomId = ?',
      whereArgs: [classroomId],
      orderBy: 'createdAt DESC',
    );

    final assignments = <Assignment>[];
    for (final m in maps) {
      final assignmentId = m['id'] as String;
      final attachments = await getAttachmentsForAssignment(assignmentId);
      assignments.add(Assignment.fromMap(m, attachments: attachments));
    }
    return assignments;
  }

  Future<Assignment?> getAssignment(String id) async {
    final db = await database;
    final maps = await db.query('assignments', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    final attachments = await getAttachmentsForAssignment(id);
    return Assignment.fromMap(maps.first, attachments: attachments);
  }

  Future<void> saveAssignments(List<Assignment> assignments) async {
    final db = await database;
    final batch = db.batch();
    for (final a in assignments) {
      batch.insert('assignments', a.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (final attachment in a.attachments) {
        batch.insert('attachments', attachment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  // ─── Submissions ───

  Future<void> saveSubmission(Submission submission) async {
    final db = await database;
    await db.insert('submissions', submission.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    for (final attachment in submission.attachments) {
      batchInsertAttachment(db, attachment);
    }
  }

  Future<List<Submission>> getSubmissionsForAssignment(String assignmentId) async {
    final db = await database;
    final maps = await db.query(
      'submissions',
      where: 'assignmentId = ?',
      whereArgs: [assignmentId],
      orderBy: 'submittedAt DESC',
    );

    final submissions = <Submission>[];
    for (final m in maps) {
      final submissionId = m['id'] as String;
      final attachments = await getAttachmentsForSubmission(submissionId);
      submissions.add(Submission.fromMap(m, attachments: attachments));
    }
    return submissions;
  }

  Future<Submission?> getSubmissionForStudent(String assignmentId, String studentDeviceId) async {
    final db = await database;
    final maps = await db.query(
      'submissions',
      where: 'assignmentId = ? AND studentDeviceId = ?',
      whereArgs: [assignmentId, studentDeviceId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final attachments = await getAttachmentsForSubmission(maps.first['id'] as String);
    return Submission.fromMap(maps.first, attachments: attachments);
  }

  Future<List<Submission>> getReturnedSubmissionsForStudent(String studentDeviceId) async {
    final db = await database;
    final maps = await db.query(
      'submissions',
      where: 'studentDeviceId = ? AND isReturned = ?',
      whereArgs: [studentDeviceId, 1],
    );
    final submissions = <Submission>[];
    for (final m in maps) {
      final submissionId = m['id'] as String;
      final attachments = await getAttachmentsForSubmission(submissionId);
      submissions.add(Submission.fromMap(m, attachments: attachments));
    }
    return submissions;
  }

  Future<List<Submission>> getUnsyncedSubmissions() async {
    final db = await database;
    final maps = await db.query(
      'submissions',
      where: 'isSynced = ?',
      whereArgs: [0], // 0 means false
    );
    final submissions = <Submission>[];
    for (final m in maps) {
      final submissionId = m['id'] as String;
      final attachments = await getAttachmentsForSubmission(submissionId);
      submissions.add(Submission.fromMap(m, attachments: attachments));
    }
    return submissions;
  }
  
  Future<void> saveSubmissions(List<Submission> submissions) async {
    final db = await database;
    final batch = db.batch();
    for (final s in submissions) {
      batch.insert('submissions', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (final attachment in s.attachments) {
        batch.insert('attachments', attachment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> markSubmissionSynced(String id) async {
    final db = await database;
    await db.update(
      'submissions',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── Attachments ───

  Future<void> saveAttachment(Attachment attachment) async {
    final db = await database;
    await db.insert('attachments', attachment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // helper to safely insert in a non-batch way but without blocking multiple rows
  Future<void> batchInsertAttachment(Database db, Attachment attachment) async {
    await db.insert('attachments', attachment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Attachment>> getAttachmentsForPost(String postId) async {
    final db = await database;
    final maps = await db.query(
      'attachments',
      where: 'postId = ?',
      whereArgs: [postId],
    );
    return maps.map((m) => Attachment.fromMap(m)).toList();
  }

  Future<List<Attachment>> getAttachmentsForAssignment(String assignmentId) async {
    final db = await database;
    final maps = await db.query(
      'attachments',
      where: 'assignmentId = ?',
      whereArgs: [assignmentId],
    );
    return maps.map((m) => Attachment.fromMap(m)).toList();
  }

  Future<List<Attachment>> getAttachmentsForSubmission(String submissionId) async {
    final db = await database;
    final maps = await db.query(
      'attachments',
      where: 'submissionId = ?',
      whereArgs: [submissionId],
    );
    return maps.map((m) => Attachment.fromMap(m)).toList();
  }

  Future<void> saveAttachments(List<Attachment> attachments) async {
    final db = await database;
    final batch = db.batch();
    for (final a in attachments) {
      batch.insert('attachments', a.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../models/assignment.dart';
import '../models/submission.dart';
import '../models/attachment.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';

class StudentAssignmentDetailScreen extends StatefulWidget {
  final Assignment assignment;
  final String teacherName;

  const StudentAssignmentDetailScreen({
    super.key,
    required this.assignment,
    required this.teacherName,
  });

  @override
  State<StudentAssignmentDetailScreen> createState() => _StudentAssignmentDetailScreenState();
}

class _StudentAssignmentDetailScreenState extends State<StudentAssignmentDetailScreen> {
  final _contentController = TextEditingController();
  List<PlatformFile> _selectedFiles = [];
  bool _isTurningIn = false;
  bool _isLoading = true;
  Submission? _existingSubmission;

  @override
  void initState() {
    super.initState();
    _loadSubmission();
  }

  Future<void> _loadSubmission() async {
    final profile = Provider.of<ProfileProvider>(context, listen: false).profile;
    if (profile == null) return;
    final submission = await DatabaseService().getSubmissionForStudent(widget.assignment.id, profile.deviceId);
    if (mounted) {
      setState(() {
        _existingSubmission = submission;
        _isLoading = false;
      });
    }
  }

  Submission? _getLatestSubmission(P2PProvider p2p) {
    if (_existingSubmission == null) return null;
    try {
      final p2pSub = p2p.submissions.firstWhere((s) => s.id == _existingSubmission!.id);
      return p2pSub;
    } catch (_) {
      return _existingSubmission;
    }
  }

  void _openAttachment(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      OpenFilex.open(filePath);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('File not found.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.files);
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _turnIn() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add some text or files to turn in.')),
      );
      return;
    }

    setState(() => _isTurningIn = true);

    final profile = Provider.of<ProfileProvider>(context, listen: false).profile!;
    final p2p = Provider.of<P2PProvider>(context, listen: false);

    final submissionId = DateTime.now().millisecondsSinceEpoch.toString();
    final attachments = <Attachment>[];

    for (final f in _selectedFiles) {
      if (f.path != null) {
        final file = File(f.path!);
        if (await file.exists()) {
          attachments.add(Attachment(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            submissionId: submissionId,
            fileName: f.name,
            fileType: f.extension ?? 'unknown',
            filePath: f.path!,
            fileSize: f.size,
          ));
        }
      }
    }

    final submission = Submission(
      id: submissionId,
      assignmentId: widget.assignment.id,
      studentDeviceId: profile.deviceId,
      studentName: profile.displayName,
      content: content,
      submittedAt: DateTime.now(),
      attachments: attachments,
    );

    // Call provider to turn in (saves locally, syncs if connected)
    await p2p.turnInAssignment(submission);

    if (!mounted) return;
    setState(() {
      _isTurningIn = false;
      _existingSubmission = submission;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Assignment turned in successfully!'),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Assignment Details', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<P2PProvider>(
        builder: (context, p2p, _) {
          final latestSub = _getLatestSubmission(p2p);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Assignment info
            Text(
              assignment.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Assigned by ${widget.teacherName}',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                if (assignment.dueDate != null) ...[
                  Icon(Icons.calendar_today, size: 14, color: Colors.orange.shade300),
                  const SizedBox(width: 4),
                  Text(
                    'Due ${DateFormat('MMM d, yhm').format(assignment.dueDate!)}',
                    style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                ],
                if (assignment.maxScore != null) ...[
                  const Icon(Icons.score, size: 14, color: Color(0xFF00C9A7)),
                  const SizedBox(width: 4),
                  Text(
                    '${assignment.maxScore} pts',
                    style: const TextStyle(color: Color(0xFF00C9A7), fontSize: 13),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 24),
            if (assignment.description.isNotEmpty) ...[
              const Text('Instructions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                assignment.description,
                style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 24),
            ],

            if (assignment.hasAttachments) ...[
              const Text('Reference Materials', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: assignment.attachments.map((a) {
                  return GestureDetector(
                    onTap: () => _openAttachment(a.filePath),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.attach_file, size: 16, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(a.fileName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
            ],

            const Divider(color: Colors.white24),
            const SizedBox(height: 24),
            const Text('Your Work', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (latestSub != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         const Text('Submitted Work', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                         if (latestSub.isReturned)
                           Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Graded: ${latestSub.score} / ${assignment.maxScore ?? 100}', 
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                           )
                         else
                           const Text('Turned In', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
                       ]
                    ),
                    const SizedBox(height: 12),
                    if (latestSub.content.isNotEmpty) ...[
                      Text(latestSub.content, style: const TextStyle(color: Colors.white, height: 1.5)),
                      const SizedBox(height: 12),
                    ],
                    
                    if (latestSub.attachments.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: latestSub.attachments.map((a) {
                           return ActionChip(
                             backgroundColor: Colors.white.withOpacity(0.08),
                             labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                             label: Text(a.fileName),
                             avatar: const Icon(Icons.attach_file, size: 14, color: Colors.white54),
                             onPressed: () => _openAttachment(a.filePath),
                           );
                        }).toList(),
                      ),
                    ]
                  ],
                ),
              )
            else ...[
              TextField(
                controller: _contentController,
                maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Type your answer or comments here...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
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

              if (_selectedFiles.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_selectedFiles.length, (index) {
                    final file = _selectedFiles[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            file.name,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _removeFile(index),
                            child: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.attach_file, color: Color(0xFF00C9A7)),
                    label: const Text('Attach Files', style: TextStyle(color: Color(0xFF00C9A7))),
                  ),
                  ElevatedButton(
                    onPressed: _isTurningIn ? null : _turnIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isTurningIn
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Turn In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
     },
    ),
   );
  }
}

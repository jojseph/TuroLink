import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../models/assignment.dart';
import '../models/submission.dart';
import '../services/database_service.dart';
import '../providers/p2p_provider.dart';
import 'package:intl/intl.dart';

class TeacherAssignmentDetailScreen extends StatefulWidget {
  final Assignment assignment;

  const TeacherAssignmentDetailScreen({
    super.key,
    required this.assignment,
  });

  @override
  State<TeacherAssignmentDetailScreen> createState() => _TeacherAssignmentDetailScreenState();
}

class _TeacherAssignmentDetailScreenState extends State<TeacherAssignmentDetailScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Submission> _localSubmissions = [];

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    final submissions = await _dbService.getSubmissionsForAssignment(widget.assignment.id);
    if (mounted) {
      setState(() {
        _localSubmissions = submissions;
      });
    }
  }

  List<Submission> _getSubmissions(P2PProvider p2p) {
    // Merge live incoming submissions that might not have been db updated in UI yet
    final p2pSubs = p2p.submissions.where((s) => s.assignmentId == widget.assignment.id).toList();
    // Use a map to combine local and p2p
    final Map<String, Submission> merged = {};
    for (var sub in _localSubmissions) {
      merged[sub.id] = sub;
    }
    for (var sub in p2pSubs) {
      merged[sub.id] = sub; // P2P overwrites local if newer
    }
    return merged.values.toList()..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
  }

  void _showGradeDialog(Submission submission) {
    final gradeController = TextEditingController(text: submission.score?.toString() ?? '');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A40),
        title: Text('Grade ${submission.studentName}', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: gradeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Score (out of ${widget.assignment.maxScore ?? 100})',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            onPressed: () async {
              final score = double.tryParse(gradeController.text);
              if (score != null) {
                final p2p = Provider.of<P2PProvider>(context, listen: false);
                await p2p.returnSubmission(submission, score);
                await _loadSubmissions(); // refresh
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Submission returned with grade!'), backgroundColor: Colors.green),
                  );
                }
              }
            },
            child: const Text('Grade & Return', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openFile(String path) async {
    if (await File(path).exists()) {
      OpenFilex.open(path);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File not found locally.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        title: const Text('Assignment Detail', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<P2PProvider>(
        builder: (context, p2p, _) {
          final submissions = _getSubmissions(p2p);
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Info
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.assignment.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('${submissions.length} Submissions', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                  ],
                ),
              ),
              const Divider(color: Colors.white24),
              
              // Submissions List
              Expanded(
                child: submissions.isEmpty
                    ? Center(child: Text('No submissions yet.', style: TextStyle(color: Colors.white.withOpacity(0.5))))
                    : ListView.builder(
                        itemCount: submissions.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final sub = submissions[index];
                          return Card(
                            color: const Color(0xFF1E1E2E),
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(sub.studentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                      if (sub.isReturned)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                          child: Text('${sub.score} / ${widget.assignment.maxScore ?? 100}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                        )
                                      else
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF6C63FF),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          onPressed: () => _showGradeDialog(sub),
                                          child: const Text('Grade', style: TextStyle(color: Colors.white)),
                                        )
                                    ],
                                  ),
                                  Text('Turned in ${DateFormat('MMM d, h:mm a').format(sub.submittedAt)}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                                  const SizedBox(height: 12),
                                  if (sub.content.isNotEmpty)
                                    Text(sub.content, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                  if (sub.attachments.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: sub.attachments.map((a) {
                                        return ActionChip(
                                          backgroundColor: Colors.white.withOpacity(0.1),
                                          labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                                          label: Text(a.fileName),
                                          avatar: const Icon(Icons.attach_file, size: 14, color: Colors.white70),
                                          onPressed: () => _openFile(a.filePath),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

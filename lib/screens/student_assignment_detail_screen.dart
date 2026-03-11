import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'quiz_player_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/assignment.dart';
import '../models/submission.dart';
import '../models/attachment.dart';
import '../models/quiz.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';
import 'package:flutter_animate/flutter_animate.dart';


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
  Quiz? _quiz;
  final Map<int, int> _selectedAnswers = {};

  @override
  void initState() {
    super.initState();
    if (widget.assignment.type == 'quiz') {
      if (widget.assignment.description.startsWith('{')) {
        try {
          _quiz = Quiz.fromJson(jsonDecode(widget.assignment.description));
        } catch (e) {
          debugPrint('Error parsing quiz JSON: $e');
        }
      }
    }
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
    if (content.isEmpty && _selectedFiles.isEmpty && widget.assignment.type != 'quiz') {
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

    String submissionContent = content;
    double? calculatedScore;
    bool isAutoGraded = false;

    if (widget.assignment.type == 'quiz' && _quiz != null) {
      double score = 0;
      final answerMap = <String, int>{};
      for (int i = 0; i < _quiz!.items.length; i++) {
        final selected = _selectedAnswers[i];
        answerMap[i.toString()] = selected ?? -1;
        if (selected != null && selected == _quiz!.items[i].correctIndex) {
          score++;
        }
      }
      submissionContent = jsonEncode({
        'answers': answerMap,
        'quizTitle': _quiz!.title,
      });
      calculatedScore = score;
      isAutoGraded = true;
    } else {
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
    }

    final submission = Submission(
      id: submissionId,
      assignmentId: widget.assignment.id,
      studentDeviceId: profile.deviceId,
      studentName: profile.displayName,
      content: submissionContent,
      submittedAt: DateTime.now(),
      attachments: attachments,
      score: calculatedScore,
      isReturned: isAutoGraded,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Assignment Details', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
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
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 8),
            Text(
              'Assigned by ${widget.teacherName}',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 16),
            
            Row(
              children: [
                if (assignment.dueDate != null) ...[
                  Icon(Icons.calendar_today_rounded, size: 14, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 4),
                  Text(
                    'Due ${DateFormat('MMM d, yhm').format(assignment.dueDate!)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                ],
                if (assignment.maxScore != null) ...[
                  Icon(Icons.star_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    '${assignment.maxScore} pts',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 24),
            if (widget.assignment.isQuiz && _quiz != null) ...[
               if (_quiz!.description.isNotEmpty || _quiz!.items.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      // Quiz Info Box
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8E53).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFF8E53).withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF8E53).withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.helpCircle, color: Color(0xFFFF8E53), size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _quiz!.title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                      Text(
                                        '${_quiz!.items.length} Multiple Choice Questions',
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_quiz!.description.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                _quiz!.description,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.5),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
               ],
            ] else if (widget.assignment.description.isNotEmpty) ...[
              Text('Instructions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text(
                widget.assignment.description,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 24),
            ],

            // Removed quiz preview call here to prevent students from seeing questions before starting.

            if (assignment.hasAttachments && widget.assignment.type != 'quiz') ...[
              Text('Reference Materials', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
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
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.attach_file_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(a.fileName, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
            ],

            if (widget.assignment.type != 'quiz')
              Divider(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
            const SizedBox(height: 24),
            Text(widget.assignment.type == 'quiz' ? 'Quiz Status' : 'Your Work', 
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 16),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (latestSub != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         Text('Submitted Work', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                         if (latestSub.isReturned)
                           Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Graded: ${latestSub.score} / ${assignment.maxScore ?? 100}', 
                                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                           )
                         else
                           Text('Turned In', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                       ]
                    ),
                    const SizedBox(height: 12),
                    if (widget.assignment.type != 'quiz' && latestSub.content.isNotEmpty) ...[
                      Text(latestSub.content, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.5)),
                      const SizedBox(height: 12),
                    ],
                    
                    if (widget.assignment.type == 'quiz') ...[
                      Text('You have completed this quiz.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('Score: ${latestSub.score?.toInt() ?? 0} / ${_quiz?.items.length ?? 0}', 
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (_quiz == null) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => QuizPlayerScreen(
                                  assignment: widget.assignment,
                                  quiz: _quiz!,
                                  submission: latestSub, // Pass the submission for review
                                ),
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.rotateCcw, size: 18),
                          label: const Text('Review Answers', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            foregroundColor: Theme.of(context).colorScheme.onSurface,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                    
                    if (latestSub.attachments.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                         children: latestSub.attachments.map((a) {
                           return ActionChip(
                             backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                             labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
                             label: Text(a.fileName),
                             avatar: Icon(Icons.attach_file_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                             onPressed: () => _openAttachment(a.filePath),
                             side: BorderSide.none,
                           );
                        }).toList(),
                      ),
                    ]
                  ],
                ),
              )
            else ...[
              if (widget.assignment.type != 'quiz')
                TextField(
                  controller: _contentController,
                  maxLines: 6,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Type your answer or comments here...',
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(20),
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.attach_file_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            file.name,
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _removeFile(index),
                            child: Icon(Icons.close_rounded, size: 16, color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
              ],

              if (widget.assignment.type != 'quiz') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _pickFiles,
                      icon: Icon(Icons.attach_file_rounded, color: Theme.of(context).colorScheme.primary),
                      label: Text('Attach Files', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isTurningIn ? null : _turnIn,
                      icon: Icon(Icons.send_rounded, size: 18, color: Theme.of(context).colorScheme.onPrimary),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      label: _isTurningIn
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                          : Text('Turn In', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ] else if (latestSub == null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                onPressed: _isTurningIn ? null : () async {
                  if (_quiz == null) return;
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuizPlayerScreen(
                        assignment: widget.assignment,
                        quiz: _quiz!,
                      ),
                    ),
                  );
                  if (result == true) {
                    _loadSubmission(); // Reload submission after quiz completion
                  }
                },
                    icon: Icon(Icons.play_arrow_rounded, size: 20, color: Theme.of(context).colorScheme.onPrimary),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    label: _isTurningIn
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                        : const Text('Start Quiz', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ],
          ],
        ),
      );
     },
    ),
   );
  }

  Widget _buildQuizQuestions(Quiz quiz, Submission? latestSub) {
    bool isSubmitted = latestSub != null;
    Map<int, int> submittedAnswers = {};
    if (isSubmitted) {
      try {
        final data = jsonDecode(latestSub.content);
        if (data['answers'] != null) {
          (data['answers'] as Map).forEach((k, v) {
            submittedAnswers[int.parse(k)] = v as int;
          });
        }
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Questions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 16),
        ...quiz.items.asMap().entries.map((entry) {
          int idx = entry.key;
          QuizItem item = entry.value;
          int? selected = isSubmitted ? submittedAnswers[idx] : _selectedAnswers[idx];

          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${idx + 1}. ${item.question}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...item.choices.asMap().entries.map((cEntry) {
                  int cIdx = cEntry.key;
                  String choice = cEntry.value;
                  bool isSelected = selected == cIdx;
                  bool isCorrect = item.correctIndex == cIdx;

                  Color itemColor = Colors.transparent;
                  if (isSelected) {
                    itemColor = isSubmitted 
                       ? (isCorrect ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1))
                       : Theme.of(context).colorScheme.primary.withOpacity(0.1);
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: isSubmitted ? null : () {
                        setState(() {
                          _selectedAnswers[idx] = cIdx;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: itemColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected 
                               ? (isSubmitted 
                                   ? (isCorrect ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5))
                                   : Theme.of(context).colorScheme.primary)
                               : (isSubmitted && isCorrect ? Colors.green.withOpacity(0.5) : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected 
                                    ? (isSubmitted 
                                        ? (isCorrect ? Colors.green : Colors.red)
                                        : Theme.of(context).colorScheme.primary)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSelected 
                                      ? (isSubmitted 
                                          ? (isCorrect ? Colors.green : Colors.red)
                                          : Theme.of(context).colorScheme.primary)
                                      : Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              child: isSelected 
                                  ? Icon(isSubmitted && !isCorrect ? Icons.close : Icons.check, size: 16, color: Colors.white)
                                  : Center(child: Text(String.fromCharCode(65 + cIdx), style: const TextStyle(fontSize: 12))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(choice, style: TextStyle(
                              color: isSubmitted && isCorrect ? Colors.green.shade700 : null,
                              fontWeight: isSubmitted && isCorrect ? FontWeight.bold : null,
                            ))),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: (idx * 100).ms).slideX(begin: 0.05, end: 0);
        }).toList(),
      ],
    );
  }
}

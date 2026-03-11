import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/quiz.dart';
import '../models/assignment.dart';
import '../models/submission.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import 'package:uuid/uuid.dart';

class QuizPlayerScreen extends StatefulWidget {
  final Assignment assignment;
  final Quiz quiz;
  final Submission? submission; // Null if taking the quiz, non-null for review

  const QuizPlayerScreen({
    super.key,
    required this.assignment,
    required this.quiz,
    this.submission,
  });

  @override
  State<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends State<QuizPlayerScreen> {
  final Map<int, int> _selectedAnswers = {}; // Map of item index -> selected choice index
  int _currentPageIndex = 0;
  final PageController _pageController = PageController();
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    if (widget.submission != null) {
      // Parse answers from submission content or just show correct ones
      // For now, let's assume we want to show the correct ones and what they picked
      // If we don't have detailed answer mapping in Submission, we just show correct ones.
    }
  }

  bool get isReviewMode => widget.submission != null;

  void _submitQuiz() async {
    // Show confirmation if not all questions answered
    if (_selectedAnswers.length < widget.quiz.items.length) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('Unfinished Quiz'),
          content: Text('You have answered ${_selectedAnswers.length} out of ${widget.quiz.items.length} questions. Do you want to submit anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go Back')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Submit Anyway', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // Calculate score
    int correctCount = 0;
    for (int i = 0; i < widget.quiz.items.length; i++) {
      if (_selectedAnswers[i] == widget.quiz.items[i].correctIndex) {
        correctCount++;
      }
    }

    final profile = Provider.of<ProfileProvider>(context, listen: false).profile!;
    
    // Create submission content (JSON of answers)
    final submissionContent = _selectedAnswers.entries.map((e) => {
      'questionIndex': e.key,
      'selectedChoice': e.value,
      'isCorrect': e.value == widget.quiz.items[e.key].correctIndex,
    }).toList();

    final submission = Submission(
      id: _uuid.v4(),
      assignmentId: widget.assignment.id,
      studentDeviceId: profile.deviceId,
      studentName: profile.displayName,
      content: 'Quiz Results', // Use the score for the main content or keep it simple
      submittedAt: DateTime.now(),
      score: correctCount.toDouble(),
      isReturned: true, // Auto-graded quizzes are effectively "returned"
    );

    final p2p = Provider.of<P2PProvider>(context, listen: false);
    await p2p.turnInAssignment(submission);

    if (mounted) {
      // Show results overlay or navigate back
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF4ECB71).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.checkCircle2, color: Color(0xFF4ECB71), size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Quiz Submitted!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your score: $correctCount / ${widget.quiz.items.length}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close dialog
                    Navigator.pop(context, true); // Return to detail screen with success
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Back to Class', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (widget.quiz.items.isEmpty) ? 0.0 : (_selectedAnswers.length / widget.quiz.items.length);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Exit Quiz?'),
                          content: const Text('Progress will not be saved. Are you sure you want to exit?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.pop(context);
                              },
                              child: const Text('Exit', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          widget.quiz.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Question ${_currentPageIndex + 1} of ${widget.quiz.items.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48), // Balance for back button
                ],
              ),
            ),

            // Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Question Area
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentPageIndex = index),
                itemCount: widget.quiz.items.length,
                itemBuilder: (context, index) {
                  final item = widget.quiz.items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              item.question,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                height: 1.4,
                              ),
                            ),
                          ).animate().fadeIn().slideY(begin: 0.1, end: 0),
                          const SizedBox(height: 32),
                          ...List.generate(item.choices.length, (ci) {
                            final isSelected = _selectedAnswers[index] == ci;
                            final label = String.fromCharCode(65 + ci);
                            
                            return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: isReviewMode
                            ? null
                            : () {
                                setState(() {
                                  _selectedAnswers[index] = ci;
                                });
                              },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isReviewMode 
                                    ? (ci == item.correctIndex ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1))
                                    : Theme.of(context).colorScheme.primary.withOpacity(0.1))
                                : (isReviewMode && ci == item.correctIndex ? Colors.green.withOpacity(0.1) : Colors.transparent),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? (isReviewMode 
                                      ? (ci == item.correctIndex ? Colors.green : Colors.red)
                                      : Theme.of(context).colorScheme.primary)
                                  : (isReviewMode && ci == item.correctIndex ? Colors.green : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
                              width: (isSelected || (isReviewMode && ci == item.correctIndex)) ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isReviewMode 
                                          ? (ci == item.correctIndex ? Colors.green : Colors.red)
                                          : Theme.of(context).colorScheme.primary)
                                      : (isReviewMode && ci == item.correctIndex ? Colors.green : Theme.of(context).colorScheme.surfaceContainerHighest),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: isReviewMode && ci == item.correctIndex 
                                    ? const Icon(LucideIcons.check, color: Colors.white, size: 16)
                                    : (isReviewMode && isSelected && ci != item.correctIndex
                                        ? const Icon(LucideIcons.x, color: Colors.white, size: 16)
                                        : Text(
                                            label,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: (isSelected || (isReviewMode && ci == item.correctIndex)) ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          )),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  item.choices[ci],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: (isSelected || (isReviewMode && ci == item.correctIndex)) ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected
                                        ? (isReviewMode 
                                            ? (ci == item.correctIndex ? Colors.green : Colors.red)
                                            : Theme.of(context).colorScheme.primary)
                                        : (isReviewMode && ci == item.correctIndex ? Colors.green : Theme.of(context).colorScheme.onSurface),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate(delay: (ci * 50).ms).fadeIn().slideX(begin: 0.05, end: 0);
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom Navigation
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPageIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _pageController.previousPage(duration: 300.ms, curve: Curves.easeOutCubic);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Previous'),
                      ),
                    )
                  else
                    const Spacer(),
                    
                  const SizedBox(width: 16),
                  
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPageIndex < widget.quiz.items.length - 1) {
                          _pageController.nextPage(duration: 300.ms, curve: Curves.easeOutCubic);
                        } else {
                          _submitQuiz();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPageIndex < widget.quiz.items.length - 1 ? 'Next Question' : 'Finish Quiz',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
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

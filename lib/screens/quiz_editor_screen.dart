import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../models/quiz.dart';
import '../models/assignment.dart';
import '../models/classroom.dart';
import '../providers/p2p_provider.dart';
import '../services/ai_chat_service.dart';
import '../services/database_service.dart';

class QuizEditorScreen extends StatefulWidget {
  final Quiz? quiz;

  const QuizEditorScreen({super.key, this.quiz});

  @override
  State<QuizEditorScreen> createState() => _QuizEditorScreenState();
}

class _QuizEditorScreenState extends State<QuizEditorScreen> {
  final DatabaseService _dbService = DatabaseService();
  final _uuid = const Uuid();

  late TextEditingController _titleController;
  late TextEditingController _descController;
  List<QuizItem> _items = [];
  bool _isSaving = false;
  late String _quizId;

  @override
  void initState() {
    super.initState();
    _quizId = widget.quiz?.id ?? _uuid.v4();
    _titleController = TextEditingController(text: widget.quiz?.title ?? '');
    _descController = TextEditingController(text: widget.quiz?.description ?? '');
    _items = List.from(widget.quiz?.items ?? []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _saveQuiz() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a quiz title.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Add at least one question to the quiz.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Re-index items
    final indexedItems = <QuizItem>[];
    for (int i = 0; i < _items.length; i++) {
      indexedItems.add(_items[i].copyWith(orderIndex: i, quizId: _quizId));
    }

    final quiz = Quiz(
      id: _quizId,
      title: title,
      description: _descController.text.trim(),
      createdAt: widget.quiz?.createdAt ?? DateTime.now(),
      items: indexedItems,
    );

    await _dbService.saveQuiz(quiz);

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Quiz saved!'),
          backgroundColor: const Color(0xFF4ECB71),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  void _addItemManually() {
    final questionCtrl = TextEditingController();
    final choiceCtrls = List.generate(4, (_) => TextEditingController());
    int correctIndex = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          final viewInsets = MediaQuery.of(ctx).viewInsets;
          return Container(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
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
                      const Text(
                        'Add Question',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(questionCtrl, 'Question'),
                  const SizedBox(height: 12),
                  ...List.generate(4, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => setModalState(() => correctIndex = i),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: correctIndex == i
                                    ? const Color(0xFF4ECB71)
                                    : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                                border: Border.all(
                                  color: correctIndex == i
                                      ? const Color(0xFF4ECB71)
                                      : Theme.of(context).colorScheme.outlineVariant,
                                ),
                              ),
                              child: correctIndex == i
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildTextField(choiceCtrls[i], 'Choice ${String.fromCharCode(65 + i)}'),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the circle to mark the correct answer',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      final q = questionCtrl.text.trim();
                      final choices = choiceCtrls.map((c) => c.text.trim()).toList();
                      if (q.isEmpty || choices.any((c) => c.isEmpty)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: const Text('Please fill in all fields.'),
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                        return;
                      }
                      final item = QuizItem(
                        id: _uuid.v4(),
                        quizId: _quizId,
                        question: q,
                        choices: choices,
                        correctIndex: correctIndex,
                        orderIndex: _items.length,
                      );
                      setState(() => _items.add(item));
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Add Question', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _editItem(int index) {
    final item = _items[index];
    final questionCtrl = TextEditingController(text: item.question);
    final choiceCtrls = List.generate(
      item.choices.length,
      (i) => TextEditingController(text: item.choices[i]),
    );
    // Ensure we always have 4 choices
    while (choiceCtrls.length < 4) {
      choiceCtrls.add(TextEditingController());
    }
    int correctIndex = item.correctIndex;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          final viewInsets = MediaQuery.of(ctx).viewInsets;
          return Container(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
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
                      const Text(
                        'Edit Question',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(questionCtrl, 'Question'),
                  const SizedBox(height: 12),
                  ...List.generate(4, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => setModalState(() => correctIndex = i),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: correctIndex == i
                                    ? const Color(0xFF4ECB71)
                                    : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                                border: Border.all(
                                  color: correctIndex == i
                                      ? const Color(0xFF4ECB71)
                                      : Theme.of(context).colorScheme.outlineVariant,
                                ),
                              ),
                              child: correctIndex == i
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildTextField(choiceCtrls[i], 'Choice ${String.fromCharCode(65 + i)}'),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      final q = questionCtrl.text.trim();
                      final choices = choiceCtrls.map((c) => c.text.trim()).toList();
                      if (q.isEmpty || choices.any((c) => c.isEmpty)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: const Text('Please fill in all fields.'),
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        _items[index] = item.copyWith(
                          question: q,
                          choices: choices,
                          correctIndex: correctIndex,
                        );
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Update Question', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  // ─── AI Generation ───

  void _showAiGenerateSheet() {
    final textCtrl = TextEditingController();
    PlatformFile? pdfFile;
    bool isGenerating = false;
    int numQuestions = 5;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          final viewInsets = MediaQuery.of(ctx).viewInsets;
          return Container(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
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
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Generate with AI',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Attach a PDF or paste text. The AI will generate multiple-choice questions from the content.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),

                  // PDF attach button
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf'],
                        allowMultiple: false,
                      );
                      if (result != null && result.files.isNotEmpty) {
                        setModalState(() => pdfFile = result.files.first);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: pdfFile != null
                            ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
                            : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: pdfFile != null
                              ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            pdfFile != null ? Icons.picture_as_pdf_rounded : Icons.attach_file_rounded,
                            color: pdfFile != null ? Colors.redAccent : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pdfFile?.name ?? 'Attach a PDF file',
                              style: TextStyle(
                                color: pdfFile != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pdfFile != null)
                            GestureDetector(
                              onTap: () => setModalState(() => pdfFile = null),
                              child: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Text(
                    'Or paste/type text:',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(textCtrl, 'Paste your text content here…', maxLines: 5),

                  const SizedBox(height: 16),
                  // Number of questions
                  Row(
                    children: [
                      Text('Questions:', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                              onPressed: numQuestions > 1
                                  ? () => setModalState(() => numQuestions--)
                                  : null,
                            ),
                            Text('$numQuestions', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                              onPressed: numQuestions < 10
                                  ? () => setModalState(() => numQuestions++)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: isGenerating
                        ? null
                        : () async {
                            final text = textCtrl.text.trim();
                            if (text.isEmpty && pdfFile == null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: const Text('Provide text or attach a PDF.'),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                              return;
                            }
                            setModalState(() => isGenerating = true);
                            try {
                              final generatedItems = await _generateQuizFromAi(
                                text: text,
                                pdfPath: pdfFile?.path,
                                numQuestions: numQuestions,
                              );
                              setState(() => _items.addAll(generatedItems));
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Generated ${generatedItems.length} question${generatedItems.length == 1 ? '' : 's'}!'),
                                    backgroundColor: const Color(0xFF4ECB71),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                );
                              }
                            } catch (e) {
                              setModalState(() => isGenerating = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('AI generation failed: ${e.toString()}'),
                                    backgroundColor: Colors.redAccent,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            }
                          },
                    icon: isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      isGenerating ? 'Generating…' : 'Generate Quiz',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<String> _extractPdfText(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final textExtractor = PdfTextExtractor(document);
    final buffer = StringBuffer();

    for (int i = 0; i < document.pages.count; i++) {
      final pageText = textExtractor.extractText(startPageIndex: i);
      if (pageText.isNotEmpty) {
        buffer.writeln(pageText);
      }
    }

    document.dispose();
    return buffer.toString().trim();
  }

  Future<List<QuizItem>> _generateQuizFromAi({
    required String text,
    String? pdfPath,
    required int numQuestions,
  }) async {
    final aiService = AiChatService();
    
    // Load saved token if available
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('hf_token');

    try {
      await aiService.init(hfToken: token);
    } catch (e) {
      throw Exception('Failed to initialize AI: $e');
    }

    if (!aiService.isModelLoaded) {
      aiService.dispose();
      throw Exception('AI model is not loaded. Please install it from the AI Assistant screen first.');
    }

    String sourceText = text;

    if (pdfPath != null) {
      try {
        final pdfText = await _extractPdfText(pdfPath);
        if (pdfText.isEmpty) {
          aiService.dispose();
          throw Exception('Could not extract text from the PDF.');
        }
        sourceText = pdfText;
      } catch (e) {
        aiService.dispose();
        throw Exception('Error reading PDF: $e');
      }
    }

    // Aggressively truncate — the 1B model has very limited context
    if (sourceText.length > 500) {
      sourceText = sourceText.substring(0, 500);
    }

    final items = <QuizItem>[];

    // Generate questions one at a time for reliability
    for (int q = 0; q < numQuestions; q++) {
      try {
        await aiService.clearHistory();

        final prompt =
            'Create exactly 1 multiple choice question based on the text. '
            'Respond STRICTLY in English characters only. '
            'Respond ONLY with the question, the 4 choices, and the correct answer. '
            'Do not add any conversational text. Use this exact format:\n'
            'Question: <question text>\n'
            'A) <choice 1>\n'
            'B) <choice 2>\n'
            'C) <choice 3>\n'
            'D) <choice 4>\n'
            'Answer: <A, B, C, or D>\n\n'
            'Text: $sourceText';

        final response = await aiService.generateResponse(prompt);

        final parsed = _tryParseQuestion(response);
        if (parsed != null) {
          items.add(QuizItem(
            id: _uuid.v4(),
            quizId: _quizId,
            question: parsed['question']!,
            choices: List<String>.from(parsed['choices'] as List),
            correctIndex: parsed['correctIndex'] as int,
            orderIndex: items.length,
          ));
        }
      } catch (_) {
        // Skip failed questions and continue
        continue;
      }
    }

    aiService.dispose();

    if (items.isEmpty) {
      throw Exception(
        'The AI could not generate quiz questions from this text. '
        'The on-device model has limited capacity. '
        'Try with very short text (1-2 paragraphs) or add questions manually.',
      );
    }

    return items;
  }

  /// Try to parse a single question from AI response text.
  /// Handles both JSON format and plain text numbered format.
  Map<String, dynamic>? _tryParseQuestion(String response) {
    if (response.trim().isEmpty) return null;

    // First try JSON parsing
    try {
      String jsonStr = response.trim();
      // Look for a JSON object
      final startBrace = jsonStr.indexOf('{');
      final endBrace = jsonStr.lastIndexOf('}');
      if (startBrace != -1 && endBrace > startBrace) {
        jsonStr = jsonStr.substring(startBrace, endBrace + 1);
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        final question = parsed['question']?.toString() ?? '';
        final choices = parsed['choices'];
        if (question.isNotEmpty && choices is List && choices.length >= 4) {
          return {
            'question': question,
            'choices': choices.take(4).map((c) => c.toString()).toList(),
            'correctIndex': ((parsed['correctIndex'] ?? parsed['correct_index'] ?? 0) as int).clamp(0, 3),
          };
        }
      }

      // Try JSON array
      final startBracket = jsonStr.indexOf('[');
      final endBracket = jsonStr.lastIndexOf(']');
      if (startBracket != -1 && endBracket > startBracket) {
        jsonStr = response.substring(startBracket, endBracket + 1);
        final parsed = jsonDecode(jsonStr) as List;
        if (parsed.isNotEmpty && parsed.first is Map) {
          final first = parsed.first as Map<String, dynamic>;
          final question = first['question']?.toString() ?? '';
          final choices = first['choices'];
          if (question.isNotEmpty && choices is List && choices.length >= 4) {
            return {
              'question': question,
              'choices': choices.take(4).map((c) => c.toString()).toList(),
              'correctIndex': ((first['correctIndex'] ?? first['correct_index'] ?? 0) as int).clamp(0, 3),
            };
          }
        }
      }
    } catch (_) {}

    // Fallback: try to parse plain text format like:
    // Question: What is X?
    // A) choice1  B) choice2  C) choice3  D) choice4
    // Answer: A
    try {
      final lines = response.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) return null;

      // Find where the choices start
      int firstChoiceIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (RegExp(r'^[A-D][\).\s]').hasMatch(line)) {
          firstChoiceIdx = i;
          break;
        }
      }

      if (firstChoiceIdx <= 0) return null;

      // The question is usually the line immediately before the choices
      String question = lines[firstChoiceIdx - 1].trim();
      
      // If the question line is empty or too short, look one line higher just in case
      if (question.length < 5 && firstChoiceIdx > 1) {
          question = lines[firstChoiceIdx - 2].trim();
      }

      question = question.replaceAll(RegExp(r'^(Question\s*\d*\s*[:.]?\s*)', caseSensitive: false), '').trim();
      int choiceStartIdx = firstChoiceIdx;

      if (question.isEmpty) return null;

      // Extract choices
      final choices = <String>[];
      int correctIndex = 0;
      for (int i = choiceStartIdx; i < lines.length && choices.length < 4; i++) {
        final line = lines[i].trim();
        final match = RegExp(r'^([A-D])[\).\s]+(.+)').firstMatch(line);
        if (match != null) {
          String choiceText = match.group(2)!.trim();
          // Check if marked as correct
          if (choiceText.contains('*') || choiceText.toLowerCase().contains('correct')) {
            correctIndex = choices.length;
            choiceText = choiceText.replaceAll('*', '').replaceAll(RegExp(r'\(correct\)', caseSensitive: false), '').trim();
          }
          choices.add(choiceText);
        }
      }

      // Look for "Answer: X" line
      for (final line in lines) {
        final answerMatch = RegExp(r'(?:Answer|Correct)\s*[:=]\s*([A-D])', caseSensitive: false).firstMatch(line);
        if (answerMatch != null) {
          correctIndex = answerMatch.group(1)!.codeUnitAt(0) - 'A'.codeUnitAt(0);
          correctIndex = correctIndex.clamp(0, 3);
          break;
        }
      }

      if (choices.length >= 4) {
        return {
          'question': question,
          'choices': choices.take(4).toList(),
          'correctIndex': correctIndex,
        };
      }
    } catch (_) {}

    return null;
  }

  // ─── Send to Classroom ───

  void _showSendToClassroomDialog() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Save the quiz first before sending.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // Load teacher's classrooms
    final profile = await _dbService.getProfile();
    if (profile == null) return;

    final classrooms = await _dbService.getClassroomsByTeacher(profile.deviceId);

    if (classrooms.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You have no classrooms yet. Create one first.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final selectedIds = <String>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Send to Classrooms',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select classrooms to send this quiz to:',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ...classrooms.map((classroom) {
                    final isSelected = selectedIds.contains(classroom.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              selectedIds.remove(classroom.id);
                            } else {
                              selectedIds.add(classroom.id);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
                                  : Theme.of(context).colorScheme.outlineVariant,
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
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  classroom.name,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: selectedIds.isEmpty
                        ? null
                        : () async {
                            await _sendQuizToClassrooms(
                              classrooms.where((c) => selectedIds.contains(c.id)).toList(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      selectedIds.isEmpty
                          ? 'Select classrooms'
                          : 'Send to ${selectedIds.length} classroom${selectedIds.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _sendQuizToClassrooms(List<Classroom> classrooms) async {
    // Build the quiz JSON to embed in the assignment description
    final indexedItems = <QuizItem>[];
    for (int i = 0; i < _items.length; i++) {
      indexedItems.add(_items[i].copyWith(orderIndex: i, quizId: _quizId));
    }
    final quiz = Quiz(
      id: _quizId,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      items: indexedItems,
    );
    final quizJson = jsonEncode(quiz.toJson());

    final p2p = Provider.of<P2PProvider>(context, listen: false);

    for (final classroom in classrooms) {
      final assignment = Assignment(
        id: _uuid.v4(),
        classroomId: classroom.id,
        title: '📝 Quiz: ${quiz.title}',
        description: quizJson,
        type: 'quiz',
        maxScore: _items.length.toDouble(),
      );
      await _dbService.saveAssignment(assignment);

      // If we are currently live in this classroom, broadcast it!
      if (p2p.state == P2PState.advertising && p2p.currentClassroom?.id == classroom.id) {
        p2p.broadcastNewAssignment(assignment);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quiz sent to ${classrooms.length} classroom${classrooms.length == 1 ? '' : 's'}!'),
          backgroundColor: const Color(0xFF4ECB71),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ─── Helper Widgets ───

  Widget _buildTextField(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final isNew = widget.quiz == null;

    return Scaffold(
      body: Container(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).colorScheme.onSurface),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        isNew ? 'Create Quiz' : 'Edit Quiz',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    // Send to classroom
                    IconButton(
                      icon: Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.primary),
                      tooltip: 'Send to classrooms',
                      onPressed: _showSendToClassroomDialog,
                    ),
                    // Save
                    TextButton.icon(
                      onPressed: _isSaving ? null : _saveQuiz,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.save_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                      label: Text('Save', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // Title
                    _buildTextField(_titleController, 'Quiz Title'),
                    const SizedBox(height: 10),
                    _buildTextField(_descController, 'Description (optional)', maxLines: 2),
                    const SizedBox(height: 20),

                    // Action buttons row
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.auto_awesome,
                            label: 'Generate with AI',
                            color: const Color(0xFF6C63FF),
                            onTap: _showAiGenerateSheet,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.add_circle_outline_rounded,
                            label: 'Add Manually',
                            color: const Color(0xFF00C9A7),
                            onTap: _addItemManually,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Questions header
                    Row(
                      children: [
                        Text(
                          'QUESTIONS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_items.length}',
                            style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.help_outline_rounded, size: 40,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3)),
                            const SizedBox(height: 12),
                            Text(
                              'No questions yet.\nUse AI or add them manually.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Question cards
                    ...List.generate(_items.length, (i) {
                      return _QuestionCard(
                        index: i,
                        item: _items[i],
                        onEdit: () => _editItem(i),
                        onDelete: () => _removeItem(i),
                      );
                    }),
                    const SizedBox(height: 80), // Space for FAB
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Action Button ───

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Question Card ───

class _QuestionCard extends StatelessWidget {
  final int index;
  final QuizItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _QuestionCard({
    required this.index,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: number + actions
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.question,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onEdit,
                  child: Icon(Icons.edit_rounded,
                      size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.redAccent.withValues(alpha: 0.6)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Choices
            ...List.generate(item.choices.length, (ci) {
              final isCorrect = ci == item.correctIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCorrect
                            ? const Color(0xFF4ECB71).withValues(alpha: 0.2)
                            : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.15),
                        border: Border.all(
                          color: isCorrect
                              ? const Color(0xFF4ECB71)
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      child: isCorrect
                          ? const Icon(Icons.check, size: 14, color: Color(0xFF4ECB71))
                          : Center(
                              child: Text(
                                String.fromCharCode(65 + ci),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.choices[ci],
                        style: TextStyle(
                          color: isCorrect
                              ? const Color(0xFF4ECB71)
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

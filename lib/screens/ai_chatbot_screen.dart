import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../services/ai_chat_service.dart';

class AiChatbotScreen extends StatefulWidget {
  const AiChatbotScreen({super.key});

  @override
  State<AiChatbotScreen> createState() => _AiChatbotScreenState();
}

class _AiChatbotScreenState extends State<AiChatbotScreen>
    with TickerProviderStateMixin {
  final AiChatService _aiService = AiChatService();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _hfTokenController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isGenerating = false;
  bool _modelInitFailed = false;
  bool _isDownloading = false;
  int _downloadProgress = 0;
  String? _errorMessage;
  StreamSubscription<String>? _responseSubscription;
  PlatformFile? _attachedPdf;

  String? _currentSummary;
  String? _documentName;

  static const _hfTokenKey = 'hf_token';

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
    _initModel();
  }

  Future<void> _loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_hfTokenKey);
    if (savedToken != null && savedToken.isNotEmpty) {
      _hfTokenController.text = savedToken;
    }
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hfTokenKey, token);
  }

  Future<void> _initModel() async {
    await _aiService.init();
    if (mounted) setState(() {});
  }

  Future<void> _startDownload() async {
    final token = _hfTokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your Hugging Face token.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      await _aiService.downloadAndInstallModel(
        hfToken: token,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );
      
      await _saveToken(token);
      
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        await _initModel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<String> _extractPdfText(File file) async {
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

  void _generateSummary() {
    final text = _textController.text.trim();
    final hasPdf = _attachedPdf != null;

    if (text.isEmpty && !hasPdf) return;
    if (_isGenerating) return;

    final pdfFile = hasPdf && _attachedPdf!.path != null
        ? File(_attachedPdf!.path!)
        : null;
    final pdfName = _attachedPdf?.name ?? '';

    setState(() {
      _currentSummary = '';
      _documentName = hasPdf ? pdfName : 'Text Input';
      _isGenerating = true;
      _textController.clear();
      _attachedPdf = null;
    });
    
    _scrollToBottom();
    _processSummary(text, pdfFile, pdfName);
  }

  Future<void> _processSummary(String text, File? pdfFile, String pdfName) async {
    String prompt;

    if (pdfFile != null) {
      try {
        String extractedText = await _extractPdfText(pdfFile);

        if (extractedText.isEmpty) {
          if (mounted) {
            setState(() {
              _currentSummary = 'I couldn\'t extract any text from this PDF. '
                  'It may be a scanned document or contain only images.';
              _isGenerating = false;
            });
            _scrollToBottom();
          }
          return;
        }

        if (extractedText.length > 500) {
          extractedText = '${extractedText.substring(0, 500)}\n[...text truncated]';
        }

        if (extractedText.length > 500) {
           await _aiService.clearHistory();
        }

        if (text.isEmpty) {
          prompt = 'Summarize the following document:\n$extractedText';
        } else {
          prompt = '$text\n\nDocument:\n$extractedText';
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _currentSummary = 'Failed to read the PDF: ${e.toString()}';
            _isGenerating = false;
          });
          _scrollToBottom();
        }
        return;
      }
    } else {
      prompt = 'Summarize: $text';
    }

    final buffer = StringBuffer();

    _responseSubscription =
        _aiService.generateResponseStream(prompt).listen(
      (token) {
        buffer.write(token);
        if (mounted) {
          setState(() {
            _currentSummary = buffer.toString();
          });
          _scrollToBottom();
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            if (buffer.isEmpty) {
              _currentSummary = 'I\'m sorry, I couldn\'t generate a summary. Please try again.';
            }
            _isGenerating = false;
          });
          _scrollToBottom();
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
             _currentSummary = 'Error: ${error.toString()}';
            _isGenerating = false;
          });
          _scrollToBottom();
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _responseSubscription?.cancel();
    _textController.dispose();
    _hfTokenController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _aiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          children: [
            _buildHeader(),
            Expanded(child: _buildMainContent()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF00C9A7)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Summarizer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _aiService.isModelLoaded
                            ? Colors.greenAccent
                            : (_aiService.isLoading
                                ? Colors.amberAccent
                                : Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _aiService.isModelLoaded
                          ? 'Gemma 3 1B • Ready'
                          : (_isDownloading
                              ? 'Downloading $_downloadProgress%…'
                              : (_aiService.isLoading
                                  ? 'Loading model…'
                                  : 'Model not installed')),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_modelInitFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 56, color: Colors.redAccent.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              const Text(
                'Failed to load AI model',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _modelInitFailed = false;
                    _errorMessage = null;
                  });
                  _initModel();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isDownloading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _downloadProgress / 100,
                    strokeWidth: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
                  ),
                ),
                Text(
                  '$_downloadProgress%',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Downloading Gemma 3 1B AI Model',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'This is a 1.2GB download and may take a while.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Please keep the app open.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_aiService.requiresDownload) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6C63FF).withValues(alpha: 0.2),
                      const Color(0xFF00C9A7).withValues(alpha: 0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.download_rounded,
                    size: 36, color: Colors.white.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 24),
              const Text(
                'AI Model Required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'To download Gemma 3, you must accept the license on Hugging Face (litert-community/Gemma3-1B-IT) and provide a read token. Data charges may apply.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _hfTokenController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Paste your Hugging Face Token (hf_...)',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    prefixIcon: Icon(Icons.key_rounded, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.file_download_rounded),
                  label: const Text(
                    'Download AI Model (~1.2GB)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_aiService.isModelLoaded && _aiService.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Loading Gemma 3 model…',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a moment on first launch',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_currentSummary == null && !_isGenerating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6C63FF).withValues(alpha: 0.2),
                      const Color(0xFF00C9A7).withValues(alpha: 0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.description_rounded,
                    size: 32,
                    color: Colors.white.withValues(alpha: 0.3)),
              ),
              const SizedBox(height: 20),
              Text(
                'Ready to Summarize',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Attach a PDF or paste some text below\nto get an instant summary.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notes_rounded, color: Colors.white.withValues(alpha: 0.5), size: 20),
              const SizedBox(width: 8),
              Text(
                 _documentName != null ? 'Summary of $_documentName' : 'Summary',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: _isGenerating && (_currentSummary == null || _currentSummary!.isEmpty)
                ? Row(
                    children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF))),
                      const SizedBox(width: 12),
                      Text('Analyzing document...', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15)),
                    ],
                  )
                : Text(
                    _currentSummary ?? '',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 15, height: 1.6),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPdfFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _attachedPdf = result.files.first;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not pick file: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Widget _buildAttachedPdfChip() {
    if (_attachedPdf == null) return const SizedBox.shrink();

    final fileName = _attachedPdf!.name;
    final fileSizeKb = (_attachedPdf!.size / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_rounded,
                color: Colors.redAccent.withValues(alpha: 0.8), size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${fileSizeKb} KB',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _attachedPdf = null;
                });
              },
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.6), size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAttachedPdfChip(),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            border: Border(
              top: _attachedPdf == null
                  ? BorderSide(
                      color: Colors.white.withValues(alpha: 0.06))
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _pickPdfFile,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _attachedPdf != null
                          ? const Color(0xFF6C63FF).withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _attachedPdf != null
                              ? const Color(0xFF6C63FF).withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      color: _attachedPdf != null
                          ? const Color(0xFF6C63FF)
                          : Colors.white.withValues(alpha: 0.4),
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _generateSummary(),
                    decoration: InputDecoration(
                      hintText: 'Enter text to summarize…',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.25)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _isGenerating ? null : _generateSummary,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: _isGenerating
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF6C63FF), Color(0xFF00C9A7)],
                            ),
                      color: _isGenerating
                          ? Colors.white.withValues(alpha: 0.06)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _isGenerating
                          ? Icons.hourglass_top_rounded
                          : Icons.auto_awesome,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

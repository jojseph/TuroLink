import 'dart:async';
import 'package:flutter_gemma/flutter_gemma.dart';

class AiChatService {
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _requiresDownload = false;

  bool get isModelLoaded => _isInitialized && _model != null;
  bool get isLoading => _isLoading;
  bool get requiresDownload => _requiresDownload;

  /// Initialize the FlutterGemma system and load the active model.
  /// The model must have been previously installed (e.g., via `FlutterGemma.installModel()`).
  /// Call this once when the chatbot screen is first opened.
  Future<void> init({String? hfToken}) async {
    if (_isInitialized || _isLoading) return;
    _isLoading = true;

    try {
      // Initialize the FlutterGemma system
      await FlutterGemma.initialize();

      // Check if our model is already installed - checking both ID and likely filenames
      final installedModels = await FlutterGemma.listInstalledModels();
      print('=== INSTALLED MODELS FOUND: $installedModels ===');
      
      final isModelInstalled = installedModels.any((m) => 
        m.toLowerCase().contains('gemma3-1b-it-int4') || 
        m.toLowerCase().contains('gemma3_1b_it_int4')
      );
      
      if (!isModelInstalled) {
        print('--- Model likely NOT installed according to list ---');
        _requiresDownload = true;
        _isLoading = false;
        return;
      }

      // Always ensure the Gemma model is active (in case the user had Llama active before)
      // We pass the token in case the repository gated-check triggers on activation
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromNetwork(
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
        token: hfToken,
      ).install();
      
      _requiresDownload = false;

      // Load the active model
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 8192,
      );

      // Create a chat session with recommended Gemma params
      _chat = await _model!.createChat(
        temperature: 1.0,
        topK: 64,
        topP: 0.95,
      );

      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      _model = null;
      _chat = null;
      // If model loading fails (e.g., corrupted or missing file),
      // fall back to offering the download again
      _requiresDownload = true;
    } finally {
      _isLoading = false;
    }
  }

  /// Downloads and installs the Gemma3-1B-IT model directly from HuggingFace.
  Future<void> downloadAndInstallModel({required String hfToken, required void Function(int) onProgress}) async {
    try {
      // Ensure initialized before installing
      await FlutterGemma.initialize();
      
      await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
            fileType: ModelFileType.task,
          )
          .fromNetwork(
            'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
            token: hfToken,
          )
          .withProgress(onProgress)
          .install();
          
      _requiresDownload = false;
    } catch (e) {
      rethrow;
    }
  }

  /// Send a message and get a streaming response from the model.
  /// Returns a Stream of text tokens (extracted from ModelResponse).
  Stream<String> generateResponseStream(String prompt) async* {
    if (!isModelLoaded || _chat == null) {
      throw Exception('Model not initialized. Call init() first.');
    }

    try {
      // Clear previous conversation to free up context window for the new prompt
      await _chat!.clearHistory();

      // Add the user's message to the chat.
      // Ensure we explicitly guide the model to respond in English.
      final fullPrompt = 'Respond strictly in English characters only. $prompt';
      await _chat!.addQueryChunk(Message.text(text: fullPrompt, isUser: true))
          .timeout(const Duration(seconds: 60));

      // Get the streaming response and extract text tokens.
      await for (final response in _chat!.generateChatResponseAsync()
          .timeout(const Duration(seconds: 120))) {
        if (response is TextResponse) {
          yield response.token;
        }
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('The AI model took too long to process (Timeout). The request might be too long for your device\'s memory limits.');
      }
      throw Exception('Generation failed: $e');
    }
  }

  /// Send a message and get a full (non-streaming) response from the model.
  Future<String> generateResponse(String prompt) async {
    if (!isModelLoaded || _chat == null) {
      throw Exception('Model not initialized. Call init() first.');
    }

    // Add the user's message to the chat
    await _chat!.addQueryChunk(Message.text(text: prompt, isUser: true));

    // Get the full response
    final response = await _chat!.generateChatResponse();
    if (response is TextResponse) {
      return response.token;
    }
    return '';
  }

  /// Stop the ongoing text generation stream immediately.
  Future<void> stopGeneration() async {
    await _chat?.stopGeneration();
  }

  /// Clear chat history and start a fresh conversation.
  Future<void> clearHistory() async {
    await _chat?.clearHistory();
  }

  void dispose() {
    _model?.close();
    _model = null;
    _chat = null;
    _isInitialized = false;
  }
}

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
  Future<void> init() async {
    if (_isInitialized || _isLoading) return;
    _isLoading = true;

    try {
      // Initialize the FlutterGemma system
      FlutterGemma.initialize();

      // Check if a model is already installed
      if (!FlutterGemma.hasActiveModel()) {
        _requiresDownload = true;
        _isLoading = false;
        return;
      }
      
      _requiresDownload = false;

      // Load the active model
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
      );

      // Create a chat session
      _chat = await _model!.createChat(
        temperature: 0.7,
        topK: 40,
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
      FlutterGemma.initialize();
      
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
      // Add the user's message to the chat. If it takes more than 30s, it's hung.
      await _chat!.addQueryChunk(Message.text(text: prompt, isUser: true))
          .timeout(const Duration(seconds: 30));

      // Get the streaming response and extract text tokens.
      // Timeout if the model doesn't emit any token for 30s.
      await for (final response in _chat!.generateChatResponseAsync()
          .timeout(const Duration(seconds: 45))) {
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

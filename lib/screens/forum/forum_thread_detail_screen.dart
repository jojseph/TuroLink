import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../../models/forum_thread.dart';
import '../../models/forum_reply.dart';
import '../../models/attachment.dart';
import '../../services/database_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/p2p_provider.dart';

class ForumThreadDetailScreen extends StatefulWidget {
  final ForumThread thread;
  final bool isTeacher;

  const ForumThreadDetailScreen({
    super.key,
    required this.thread,
    required this.isTeacher,
  });

  @override
  State<ForumThreadDetailScreen> createState() => _ForumThreadDetailScreenState();
}

class _ForumThreadDetailScreenState extends State<ForumThreadDetailScreen> {
  final DatabaseService _dbService = DatabaseService();
  final _replyController = TextEditingController();
  bool _isPosting = false;
  List<PlatformFile> _selectedFiles = [];
  
  // Use a ScrollController to scroll to bottom when new reply is added
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadReplies() async {
    // We now get replies from P2PProvider!
  }

  void _postReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty && _selectedFiles.isEmpty) return;

    setState(() => _isPosting = true);

    final profile = Provider.of<ProfileProvider>(context, listen: false).profile!;
    final p2pProvider = Provider.of<P2PProvider>(context, listen: false);

    await p2pProvider.createForumReply(
      widget.thread.id,
      content,
      profile.deviceId,
      profile.displayName,
      widget.isTeacher,
      filePaths: _selectedFiles.map((f) => f.path!).where((p) => p != null).toList(),
    );
    
    _replyController.clear();
    _selectedFiles.clear();
    
    if (mounted) {
      setState(() => _isPosting = false);
      // Optional: scroll to bottom
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _openAttachment(Attachment attachment) async {
    final file = File(attachment.filePath);
    if (await file.exists()) {
      final result = await OpenFilex.open(attachment.filePath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found locally.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Discussion'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Consumer<P2PProvider>(
        builder: (context, p2p, child) {
          final replies = p2p.getRepliesForThread(widget.thread.id);
          // Get the latest thread instance from provider to see updates (like attachments)
          final thread = p2p.forumThreads.firstWhere(
            (t) => t.id == widget.thread.id,
            orElse: () => widget.thread,
          );

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(20),
                        itemCount: replies.length + 1, // +1 for the original thread
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildOriginalThread(thread);
                          }
                          final reply = replies[index - 1];
                          return _buildReplyCard(reply);
                        },
                      ),
              ),
              _buildReplyBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOriginalThread(ForumThread thread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                child: Text(
                  thread.authorName[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.authorName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      _formatTime(thread.createdAt),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            thread.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            thread.content,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, height: 1.5),
          ),
          if (thread.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: thread.attachments.map((a) => _buildAttachmentChip(a)).toList(),
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildReplyCard(ForumReply reply) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: reply.isTeacher 
            ? Colors.orange.withOpacity(0.1) 
            : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: reply.isTeacher 
              ? Colors.orange.withOpacity(0.3) 
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                reply.authorName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: reply.isTeacher ? Colors.orange : Theme.of(context).colorScheme.primary,
                ),
              ),
              if (reply.isTeacher) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded, size: 14, color: Colors.orange),
              ],
              const Spacer(),
              Text(
                _formatTime(reply.createdAt),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reply.content,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (reply.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reply.attachments.map((a) => _buildAttachmentChip(a)).toList(),
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildAttachmentChip(Attachment a) {
    return ActionChip(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      labelStyle: const TextStyle(fontSize: 12),
      avatar: const Icon(Icons.attach_file_rounded, size: 16),
      label: Text(a.fileName),
      onPressed: () => _openAttachment(a),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedFiles.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_selectedFiles.length, (index) {
                return Chip(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  label: Text(_selectedFiles[index].name, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => _selectedFiles.removeAt(index)),
                );
              }),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file_rounded),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
                  if (result != null) {
                    setState(() => _selectedFiles.addAll(result.files));
                  }
                },
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _replyController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Type a reply...',
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _isPosting 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                onPressed: _isPosting ? null : _postReply,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

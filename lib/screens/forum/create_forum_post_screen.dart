import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../models/classroom.dart';
import '../../models/forum_thread.dart';
import '../../models/attachment.dart';
import '../../services/database_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/p2p_provider.dart';

class CreateForumPostScreen extends StatefulWidget {
  final Classroom classroom;
  final bool isTeacher;

  const CreateForumPostScreen({
    super.key,
    required this.classroom,
    required this.isTeacher,
  });

  @override
  State<CreateForumPostScreen> createState() => _CreateForumPostScreenState();
}

class _CreateForumPostScreenState extends State<CreateForumPostScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final DatabaseService _dbService = DatabaseService();
  bool _isPosting = false;
  List<PlatformFile> _selectedFiles = [];

  void _createPost() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and body are required')),
      );
      return;
    }

    setState(() => _isPosting = true);

    final profile = Provider.of<ProfileProvider>(context, listen: false).profile!;
    final p2pProvider = Provider.of<P2PProvider>(context, listen: false);

    await p2pProvider.createForumThread(
      title,
      content,
      profile.deviceId,
      profile.displayName,
      filePaths: _selectedFiles.map((f) => f.path!).where((p) => p != null).toList(),
    );

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask a Question'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _createPost,
            child: _isPosting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Post', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Question Title',
                hintStyle: TextStyle(color: Colors.black.withOpacity(0.5), fontSize: 18),
                border: InputBorder.none,
              ),
            ),
            const Divider(color: Colors.white24),
            TextField(
              controller: _contentController,
              maxLines: 10,
              minLines: 5,
              style: const TextStyle(color: Colors.black, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Explain your question or topic...',
                hintStyle: TextStyle(color: Colors.black.withOpacity(0.5)),
                border: InputBorder.none,
              ),
            ),
            
            if (_selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Attachments', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_selectedFiles.length, (index) {
                  return Chip(
                    label: Text(_selectedFiles[index].name, style: const TextStyle(fontSize: 12)),
                    onDeleted: () {
                      setState(() {
                        _selectedFiles.removeAt(index);
                      });
                    },
                  );
                }),
              ),
            ],

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true);
                if (result != null) {
                  setState(() {
                    _selectedFiles.addAll(result.files);
                  });
                }
              },
              icon: const Icon(Icons.attach_file_rounded),
              label: const Text('Add Attachment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

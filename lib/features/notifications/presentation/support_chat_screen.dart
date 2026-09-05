import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../models/support_message.dart';
import '../../../providers/user_provider.dart';

class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _textController = TextEditingController();
  File? _attachment;

  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() => _attachment = File(pickedFile.path));
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _attachment == null) return;

    final user = ref.read(userProvider).value;
    if (user == null) return;

    String? attachmentUrl;
    if (_attachment != null) {
      attachmentUrl = await ref.read(firebaseServiceProvider).uploadAttachment(_attachment!);
    }

    final message = SupportMessage(
      id: '',
      senderId: user.uid,
      text: text,
      attachmentUrl: attachmentUrl,
      timestamp: DateTime.now(),
      isAdmin: false,
    );

    await ref.read(firebaseServiceProvider).sendSupportMessage(user.uid, message);

    _textController.clear();
    setState(() => _attachment = null);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider).value;
    if (user == null) return const Scaffold(body: Center(child: Text("Please log in")));

    final messagesStream = ref.watch(supportMessagesProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text("Customer Support")),
      body: Column(
        children: [
          Expanded(
            child: messagesStream.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text("How can we help you today?"));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _ChatBubble(message: msg, isMe: !msg.isAdmin);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text("Error: $err")),
            ),
          ),
          if (_attachment != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white10,
              child: Row(
                children: [
                  Image.file(_attachment!, height: 50, width: 50, fit: BoxFit.cover),
                  const SizedBox(width: 8),
                  const Text("Image attached"),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _attachment = null)),
                ],
              ),
            ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.attach_file), onPressed: _pickAttachment),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: "Type a message...",
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.purpleAccent),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

final supportMessagesProvider = StreamProvider.family<List<SupportMessage>, String>((ref, uid) {
  return ref.watch(firebaseServiceProvider).getSupportMessages(uid);
});

class _ChatBubble extends StatelessWidget {
  final SupportMessage message;
  final bool isMe;

  const _ChatBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.purpleAccent : Colors.white10,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
          ),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachmentUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(message.attachmentUrl!),
                ),
              ),
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: const TextStyle(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

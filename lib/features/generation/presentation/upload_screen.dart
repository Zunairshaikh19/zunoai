import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../models/image_prompt.dart';
import '../../../providers/user_provider.dart';
import '../../../services/api_service.dart';
import '../../../models/history_item.dart';
import '../../../core/theme/app_colors.dart';

class UploadScreen extends ConsumerStatefulWidget {
  final ImagePrompt prompt;
  const UploadScreen({super.key, required this.prompt});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  File? _image;
  bool _isGenerating = false;
  String? _resultUrl;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
    }
  }

  Future<void> _generate() async {
    if (_image == null) return;
    setState(() => _isGenerating = true);
    
    final user = ref.read(userProvider).value;
    if (user == null) {
      setState(() => _isGenerating = false);
      return;
    }

    final apiKey = await ref.read(firebaseServiceProvider).getGenerationApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Service temporarily unavailable.")),
        );
      }
      return;
    }

    final success = await ref.read(userProvider.notifier).spendCoins(40);
    if (!success) {
      setState(() => _isGenerating = false);
      return;
    }

    final apiService = ApiService(apiKey);
    try {
      final result = await apiService.generateImage(
        prompt: widget.prompt.hiddenPrompt,
        referenceImage: _image!,
      );

      if (result != null) {
        final historyItem = HistoryItem(
          id: "", 
          outputUrl: result,
          promptCategory: widget.prompt.category,
          timestamp: DateTime.now(),
          status: HistoryStatus.success,
        );
        await ref.read(firebaseServiceProvider).saveToHistory(user.uid, historyItem);
      } else {
        await ref.read(userProvider.notifier).addCoins(40);
      }

      setState(() {
        _isGenerating = false;
        _resultUrl = result;
      });
    } catch (e) {
      await ref.read(userProvider.notifier).addCoins(40);
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resultUrl != null) {
      return _buildResultView();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Create Masterpiece", style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.chevronLeft, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPromptCard(),
            const SizedBox(height: 32),
            const Text(
              "Add Reference Image",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showPicker(context),
              child: Container(
                width: double.infinity,
                height: 300,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: _image == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FaIcon(FontAwesomeIcons.cloudArrowUp, size: 48, color: AppColors.electricLime.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          const Text("Tap to upload your photo", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.file(_image!, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 40),
            if (_isGenerating)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.electricLime),
                    SizedBox(height: 16),
                    Text("Zuno is visualizing...", style: TextStyle(color: AppColors.electricLime, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _image == null ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricLime,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text("Generate", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.electricLime, size: 20),
              const SizedBox(width: 8),
              Text(
                "Prompt: ${widget.prompt.category}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.prompt.hiddenPrompt.isEmpty 
                ? "Experience the magic of AI based on this theme."
                : widget.prompt.hiddenPrompt,
            style: const TextStyle(color: Colors.white70, height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Result Image", style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.chevronLeft, size: 20),
          onPressed: () => setState(() => _resultUrl = null),
        ),
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 20),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: CachedNetworkImage(
                  imageUrl: _resultUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: AppColors.surface),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Landscape imaginary tree in another realm with night sky view", // Mock text from screenshot
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _resultUrl = null),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.white10),
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.white.withOpacity(0.05),
                        ),
                        child: const Text("Re-generate", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const FaIcon(FontAwesomeIcons.download, size: 16),
                        label: const Text("Download"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.electricLime,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                          elevation: 8,
                          shadowColor: AppColors.electricLime.withOpacity(0.5),
                        ),
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

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.electricLime),
              title: const Text('Gallery'),
              onTap: () {
                _pickImage(ImageSource.gallery);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.electricLime),
              title: const Text('Camera'),
              onTap: () {
                _pickImage(ImageSource.camera);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

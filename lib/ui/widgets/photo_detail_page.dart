import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zvec_photo_search/services/vector_store.dart';

/// Full-screen photo preview with native share support.
class PhotoDetailPage extends StatefulWidget {
  final PhotoSearchResult result;

  const PhotoDetailPage({super.key, required this.result});

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  Uint8List? _fullBytes;
  bool _loading = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadFullImage();
  }

  Future<void> _loadFullImage() async {
    final path = widget.result.photoPath;

    // Android: real file path
    if (path.startsWith('/') && File(path).existsSync()) {
      final bytes = await File(path).readAsBytes();
      if (mounted) setState(() { _fullBytes = bytes; _loading = false; });
      return;
    }

    // iOS / asset ID: load via photo_manager
    final entity = await AssetEntity.fromId(path);
    if (entity == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final bytes = await entity.thumbnailDataWithSize(
      const ThumbnailSize(1200, 1200),
      format: ThumbnailFormat.jpeg,
      quality: 95,
    );
    if (mounted) setState(() { _fullBytes = bytes; _loading = false; });
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final path = widget.result.photoPath;
      File? shareFile;

      // Try to get the original file for best quality sharing
      if (path.startsWith('/') && File(path).existsSync()) {
        shareFile = File(path);
      } else {
        final entity = await AssetEntity.fromId(path);
        if (entity != null) {
          shareFile = await entity.file;
        }
      }

      if (shareFile != null && shareFile.existsSync()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(shareFile.path)],
          ),
        );
      } else if (_fullBytes != null) {
        // Fallback: share the in-memory thumbnail
        final tmp = await _writeTempFile(_fullBytes!);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tmp.path)],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<File> _writeTempFile(Uint8List bytes) async {
    final dir = Directory.systemTemp;
    final file = File(
        '${dir.path}/zvec_share_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (!_loading)
            IconButton(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded),
              tooltip: 'Share',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_fullBytes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Unable to load photo',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.memory(
          _fullBytes!,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:pocketsearch/services/vector_store.dart';
import 'package:pocketsearch/ui/widgets/photo_detail_page.dart';

/// Displays search results in a staggered grid layout.
class PhotoGrid extends StatelessWidget {
  final List<PhotoSearchResult> results;

  const PhotoGrid({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return _PhotoTile(result: result);
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final PhotoSearchResult result;

  const _PhotoTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoDetailPage(result: result),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    // If photoPath looks like a file path, try loading from disk (Android
    // persists real paths). Otherwise treat it as a PhotoKit / MediaStore
    // asset ID and load via photo_manager.
    final path = result.photoPath;
    if (path.startsWith('/') && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 300,
        errorBuilder: (_, __, ___) => _brokenPlaceholder(),
      );
    }
    // Load thumbnail by asset ID
    return FutureBuilder<Uint8List?>(
      future: _loadThumbnail(path),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            snap.data == null ||
            snap.data!.isEmpty) {
          return Container(color: Colors.grey[200]);
        }
        return Image.memory(
          snap.data!,
          fit: BoxFit.cover,
          cacheWidth: 300,
          errorBuilder: (_, __, ___) => _brokenPlaceholder(),
        );
      },
    );
  }

  static Future<Uint8List?> _loadThumbnail(String assetId) async {
    final entity = await AssetEntity.fromId(assetId);
    if (entity == null) return null;
    return entity.thumbnailDataWithSize(
      const ThumbnailSize.square(300),
      format: ThumbnailFormat.jpeg,
    );
  }

  static Widget _brokenPlaceholder() => Container(
        color: Colors.grey[300],
        child: const Icon(Icons.broken_image_rounded),
      );
}

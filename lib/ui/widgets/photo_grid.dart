import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zvec_photo_search/services/vector_store.dart';

/// Displays search results in a staggered grid layout.
class PhotoGrid extends StatelessWidget {
  final List<PhotoSearchResult> results;

  const PhotoGrid({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(result.photoPath),
            fit: BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image_rounded),
            ),
          ),
          // Score overlay
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(result.score * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

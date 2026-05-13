import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zvec_photo_search/services/index_service.dart';

/// Shows indexing progress as a compact status bar.
class IndexStatusBar extends StatefulWidget {
  final IndexService indexService;

  const IndexStatusBar({super.key, required this.indexService});

  @override
  State<IndexStatusBar> createState() => _IndexStatusBarState();
}

class _IndexStatusBarState extends State<IndexStatusBar> {
  StreamSubscription<IndexProgress>? _subscription;
  IndexProgress? _lastProgress;

  @override
  void initState() {
    super.initState();
    _subscription = widget.indexService.progressStream.listen((progress) {
      setState(() => _lastProgress = progress);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.indexService.status;

    if (status == IndexStatus.complete || status == IndexStatus.idle) {
      if (_lastProgress == null || !_lastProgress!.isComplete) {
        return const SizedBox.shrink();
      }
      // Show completed status briefly
      return _buildCompletedBar();
    }

    if (status == IndexStatus.error) {
      return _buildErrorBar();
    }

    if (_lastProgress == null) {
      return _buildIndexingBar(0, 'Preparing index...');
    }

    return _buildIndexingBar(
      _lastProgress!.progress,
      'Indexing photos: ${_lastProgress!.current}/${_lastProgress!.total}',
    );
  }

  Widget _buildIndexingBar(double progress, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress > 0 ? progress : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
          const SizedBox(width: 10),
          Text(
            '${_lastProgress!.total} photos indexed and ready to search',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 10),
          Text(
            'Photo access denied. Please grant permission in Settings.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

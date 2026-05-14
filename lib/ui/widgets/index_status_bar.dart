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

    final p = _lastProgress!;
    final failedSuffix = p.failedCount > 0 ? '  (${p.failedCount} failed)' : '';
    return _buildIndexingBar(
      p.progress,
      'Indexing photos: ${p.current}/${p.total}$failedSuffix',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
          if (_lastProgress?.lastError != null) ...[
            const SizedBox(height: 4),
            Text(
              'last error: ${_truncate(_lastProgress!.lastError!, 200)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red,
                    fontSize: 11,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletedBar() {
    final p = _lastProgress!;
    final hasFailures = p.failedCount > 0;
    final color = hasFailures ? Colors.orange : Colors.green;
    final icon = hasFailures
        ? Icons.warning_amber_rounded
        : Icons.check_circle_rounded;
    final label = hasFailures
        ? '${p.current} indexed, ${p.failedCount} failed (out of ${p.total})'
        : '${p.total} photos indexed and ready to search';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (hasFailures && p.lastError != null) ...[
            const SizedBox(height: 4),
            Text(
              'last error: ${_truncate(p.lastError!, 200)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red,
                    fontSize: 11,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

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

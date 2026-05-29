import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pocketsearch/services/index_service.dart';

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
    // Seed from the service's cached last event. `progressStream` is a
    // broadcast stream and does NOT buffer, so if startIndexing() emitted
    // before this widget mounted (e.g. on iOS where the gallery is fully
    // cached and the early-progress event fires very quickly), a fresh
    // subscriber would otherwise sit on `null` indefinitely and the bar
    // would never appear.
    _lastProgress = widget.indexService.lastProgress;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              value: progress > 0 ? progress : null,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedBar() {
    final p = _lastProgress!;
    final hasFailures = p.failedCount > 0;
    final label = hasFailures
        ? '${p.current} indexed, ${p.failedCount} failed'
        : '${p.total} photos indexed';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Icon(
            hasFailures ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            size: 14,
            color: hasFailures ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: Colors.red),
          const SizedBox(width: 8),
          Text(
            'Photo access denied. Grant permission in Settings.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

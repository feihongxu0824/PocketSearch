import 'dart:math';

import 'package:flutter/material.dart';

/// Displays suggestion query chips for user to try.
class SuggestionChips extends StatelessWidget {
  final void Function(String query) onTap;

  const SuggestionChips({super.key, required this.onTap});

  static const _allSuggestions = [
    'sunset',
    'cat',
    'food',
    'beach',
    'selfie',
    'city skyline',
    'flowers',
    'snow',
    'coffee',
    'mountains',
    'dog',
    'night sky',
    'books',
    'birthday cake',
    'car',
    'trees',
    'rain',
    'concert',
    'cooking',
    'airplane',
  ];

  @override
  Widget build(BuildContext context) {
    // Pick 8 random suggestions
    final random = Random();
    final suggestions = List<String>.from(_allSuggestions)..shuffle(random);
    final displayed = suggestions.take(8).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Icon(
            Icons.auto_awesome_rounded,
            size: 32,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'Try searching for...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: displayed.map((query) {
              return ActionChip(
                label: Text(query),
                onPressed: () => onTap(query),
                avatar: const Icon(Icons.search, size: 16),
              );
            }).toList(),
          ),
          const Spacer(),
          Center(
            child: Text(
              'Powered by zvec + MobileCLIP\nFully on-device \u2022 No cloud \u2022 Private',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

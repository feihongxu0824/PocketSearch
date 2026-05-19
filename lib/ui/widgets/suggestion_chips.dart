import 'dart:math';

import 'package:flutter/material.dart';

/// Displays suggestion query chips for user to try.
class SuggestionChips extends StatelessWidget {
  final void Function(String query) onTap;

  const SuggestionChips({super.key, required this.onTap});

  static const _allSuggestions = [
    'a cat sleeping in the sunlight',
    'people having coffee at an outdoor cafe',
    'sunset over the ocean with clouds',
    'snowy mountain peaks under blue sky',
    'colorful flowers in a garden',
    'city skyline at night with lights',
    'a dog playing on the beach',
    'food on a plate at a restaurant',
    'rain falling on a quiet street',
    'person reading a book by the window',
    'airplane flying above the clouds',
    'birthday cake with candles',
    'autumn leaves on a forest path',
    'a couple walking on the beach',
    'car driving on a mountain road',
    'neon signs on a busy street',
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
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
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
            ),
          ),
          const SizedBox(height: 16),
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

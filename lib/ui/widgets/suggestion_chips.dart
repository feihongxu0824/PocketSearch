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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            'Try searching for...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 10,
                children: displayed.map((query) {
                  return GestureDetector(
                    onTap: () => onTap(query),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        query,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF3C3C43),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Powered by zvec + MobileCLIP\nFully on-device \u2022 No cloud \u2022 Private',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[350],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pocketsearch/models/personal_source_document.dart';
import 'package:pocketsearch/services/vector_store.dart';
import 'package:pocketsearch/ui/widgets/photo_detail_page.dart';
import 'package:pocketsearch/ui/widgets/photo_grid.dart';

class SearchResultsView extends StatelessWidget {
  final List<PhotoSearchResult> photoResults;
  final List<TextSearchResult> textResults;

  const SearchResultsView({
    super.key,
    required this.photoResults,
    required this.textResults,
  });

  @override
  Widget build(BuildContext context) {
    if (textResults.isEmpty) {
      return _PhotoGrid(results: photoResults);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (textResults.isNotEmpty) ...[
          _SectionHeader(label: 'Personal sources'),
          ...textResults.map((result) => _TextResultTile(result: result)),
        ],
        if (photoResults.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionHeader(label: 'Photos'),
          _PhotoGrid(results: photoResults, shrinkWrap: true),
        ],
      ],
    );
  }
}

class _TextResultTile extends StatelessWidget {
  final TextSearchResult result;

  const _TextResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final doc = result.document;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 0,
      color: const Color(0xFFF7F7FA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          child: Icon(doc.sourceType.icon, size: 20),
        ),
        title: Text(
          doc.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${doc.sourceType.label} · ${doc.sourceName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            if (result.snippet.isNotEmpty) ...[
              const SizedBox(height: 6),
              _HighlightedText(
                text: result.snippet,
                ranges: result.highlightRanges,
              ),
            ],
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TextResultDetailPage(result: result),
          ),
        ),
      ),
    );
  }
}

class TextResultDetailPage extends StatelessWidget {
  final TextSearchResult result;

  const TextResultDetailPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final doc = result.document;
    return Scaffold(
      appBar: AppBar(title: Text(doc.sourceType.label)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Icon(doc.sourceType.icon, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.sourceName,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            doc.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (doc.startAt != null)
            Text(
              _formatRange(doc.startAt!, doc.endAt),
              style: TextStyle(color: Colors.grey[700]),
            ),
          const SizedBox(height: 20),
          _HighlightedText(
            text: doc.body.isEmpty ? result.snippet : doc.body,
            ranges: TextSearchResultHighlighter.rangesForFullText(
              doc.body.isEmpty ? result.snippet : doc.body,
              result.snippet,
              result.highlightRanges,
            ),
            fontSize: 15,
          ),
          const SizedBox(height: 24),
          Text(
            'Matched ${result.matchedFields.join(', ')} · score ${result.score.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _formatRange(DateTime start, DateTime? end) {
    final left =
        '${start.year}-${_two(start.month)}-${_two(start.day)} '
        '${_two(start.hour)}:${_two(start.minute)}';
    if (end == null) return left;
    final right =
        '${end.year}-${_two(end.month)}-${_two(end.day)} '
        '${_two(end.hour)}:${_two(end.minute)}';
    return '$left - $right';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final List<TextRange> ranges;
  final double fontSize;

  const _HighlightedText({
    required this.text,
    required this.ranges,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    if (ranges.isEmpty) {
      return Text(
        text,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: fontSize, color: Colors.grey[800]),
      );
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.start < cursor || range.end > text.length) continue;
      if (range.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, range.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFE58A),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = range.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.grey[800],
          height: 1.35,
        ),
        children: spans,
      ),
    );
  }
}

class TextSearchResultHighlighter {
  static List<TextRange> rangesForFullText(
    String fullText,
    String snippet,
    List<TextRange> snippetRanges,
  ) {
    if (fullText.isEmpty || snippetRanges.isEmpty) return snippetRanges;
    final cleanSnippet = snippet.replaceAll('...', '');
    final offset = fullText.indexOf(cleanSnippet);
    if (offset < 0) return const [];
    return snippetRanges
        .map((r) => TextRange(start: r.start + offset, end: r.end + offset))
        .where((r) => r.start >= 0 && r.end <= fullText.length)
        .toList();
  }
}

class _PhotoGrid extends StatelessWidget {
  final List<PhotoSearchResult> results;
  final bool shrinkWrap;

  const _PhotoGrid({required this.results, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PhotoDetailPage(result: result)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PhotoResultImage(photoPath: result.photoPath),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Colors.grey[700],
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

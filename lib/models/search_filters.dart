/// Structured metadata filters extracted by the LLM query rewriter.
///
/// When the user types something like "去年夏天海边玩的照片", the LLM
/// produces *both* a visual description ("people playing on a sunny beach")
/// *and* filter constraints (date range: 2025-06 to 2025-09). This class
/// carries the filter half; the visual description stays in
/// [RewriteResult.effectiveQuery].
class SearchFilters {
  /// Inclusive lower bound on photo creation timestamp (epoch milliseconds).
  final int? dateStartMs;

  /// Exclusive upper bound on photo creation timestamp (epoch milliseconds).
  final int? dateEndMs;

  /// Bounding-box for GPS latitude (inclusive).
  final double? latMin;
  final double? latMax;

  /// Bounding-box for GPS longitude (inclusive).
  final double? lngMin;
  final double? lngMax;

  const SearchFilters({
    this.dateStartMs,
    this.dateEndMs,
    this.latMin,
    this.latMax,
    this.lngMin,
    this.lngMax,
  });

  /// True when at least one filter dimension is present.
  bool get hasAny =>
      dateStartMs != null ||
      dateEndMs != null ||
      latMin != null ||
      latMax != null ||
      lngMin != null ||
      lngMax != null;

  /// Build a zvec scalar-filter expression string.
  ///
  /// Returns `null` when no filter fields are set — the caller should
  /// simply omit the `filter` parameter on [VectorQuery].
  String? toZvecFilter() {
    final parts = <String>[];
    if (dateStartMs != null) parts.add('created_at >= $dateStartMs');
    if (dateEndMs != null) parts.add('created_at < $dateEndMs');
    if (latMin != null && latMax != null) {
      parts.add('latitude >= $latMin');
      parts.add('latitude <= $latMax');
    }
    if (lngMin != null && lngMax != null) {
      parts.add('longitude >= $lngMin');
      parts.add('longitude <= $lngMax');
    }
    return parts.isEmpty ? null : parts.join(' AND ');
  }

  /// Parse filter fields from the LLM rewriter JSON output.
  ///
  /// Accepts ISO-8601 date strings (`"2025-06-01"`) or epoch-ms integers
  /// for date fields. Missing or malformed fields are silently ignored so
  /// a partially-correct LLM response still yields usable filters.
  factory SearchFilters.fromLlmJson(Map<String, dynamic> json) {
    int? dateStartMs;
    int? dateEndMs;
    double? latMin, latMax, lngMin, lngMax;

    dateStartMs = _parseDateMs(json['date_start']);
    dateEndMs = _parseDateMs(json['date_end']);

    final geo = json['geo'];
    if (geo is Map<String, dynamic>) {
      latMin = _toDouble(geo['lat_min']);
      latMax = _toDouble(geo['lat_max']);
      lngMin = _toDouble(geo['lng_min']);
      lngMax = _toDouble(geo['lng_max']);
    }

    return SearchFilters(
      dateStartMs: dateStartMs,
      dateEndMs: dateEndMs,
      latMin: latMin,
      latMax: latMax,
      lngMin: lngMin,
      lngMax: lngMax,
    );
  }

  /// Human-readable summary for the UI, e.g. "2025-06 ~ 2025-09 · Beijing".
  String toDisplayString() {
    final parts = <String>[];
    if (dateStartMs != null || dateEndMs != null) {
      final start = dateStartMs != null ? _formatDate(dateStartMs!) : '...';
      final end = dateEndMs != null ? _formatDate(dateEndMs!) : '...';
      parts.add('$start ~ $end');
    }
    if (latMin != null && latMax != null && lngMin != null && lngMax != null) {
      parts.add(
        'lat ${latMin!.toStringAsFixed(1)}~${latMax!.toStringAsFixed(1)}, '
        'lng ${lngMin!.toStringAsFixed(1)}~${lngMax!.toStringAsFixed(1)}',
      );
    }
    return parts.join(' · ');
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Parse an ISO-8601 date string or epoch-ms integer into epoch ms.
  static int? _parseDateMs(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
      // Try parsing as a plain number string.
      final n = int.tryParse(v);
      if (n != null) return n;
    }
    return null;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'SearchFilters(${toZvecFilter() ?? 'none'})';
}

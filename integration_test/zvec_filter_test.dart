// Integration test: verify PocketSearch's zvec scalar-filter contract.
//
// zvec currently treats documents with missing scalar fields as candidates
// even when the filter references that field. PocketSearch therefore always
// writes sentinel metadata values (created_at=0, latitude=0, longitude=0)
// for filterable fields. These tests protect that app-level contract.
//
// This must run on a real device because zvec is an FFI plugin.
//   flutter test integration_test/zvec_filter_test.dart -d <device_id>

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zvec/zvec.dart';

Float32List _randomUnitVector(int seed) {
  final rng = Random(seed);
  final v = Float32List(512);
  double norm = 0;
  for (int i = 0; i < 512; i++) {
    v[i] = rng.nextDouble() - 0.5;
    norm += v[i] * v[i];
  }
  norm = sqrt(norm);
  for (int i = 0; i < 512; i++) {
    v[i] /= norm;
  }
  return v;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String dbPath;
  late Collection collection;

  setUp(() async {
    if (!Zvec.isInitialized) Zvec.initialize();
    final appDir = await getApplicationDocumentsDirectory();
    dbPath =
        '${appDir.path}/zvec_filter_${DateTime.now().millisecondsSinceEpoch}';

    final schema = CollectionSchema(
      name: 'test_filter',
      fields: [
        VectorSchema('embedding', 512, indexParams: HnswIndexParams()),
        FieldSchema(name: 'photo_id', dataType: DataType.string),
        FieldSchema(name: 'created_at', dataType: DataType.int64),
        FieldSchema(name: 'latitude', dataType: DataType.float64),
        FieldSchema(name: 'longitude', dataType: DataType.float64),
      ],
    );
    collection = Collection.createAndOpen(dbPath, schema);
    schema.destroy();
  });

  tearDown(() {
    try {
      collection.close();
    } catch (_) {}
    if (Directory(dbPath).existsSync()) {
      Directory(dbPath).deleteSync(recursive: true);
    }
  });

  testWidgets('GEO filter: sentinel lat/lng docs must NOT be recalled', (
    tester,
  ) async {
    // Doc A: has GPS in Macau bbox
    final docA = Doc(id: 'macau_gps')
      ..setVector('embedding', _randomUnitVector(1))
      ..setField('photo_id', 'macau_gps')
      ..setField('created_at', 1700000000000)
      ..setField('latitude', 22.2)
      ..setField('longitude', 113.55);

    // Doc B: GPS in Shanghai (far from Macau)
    final docB = Doc(id: 'shanghai_gps')
      ..setVector('embedding', _randomUnitVector(2))
      ..setField('photo_id', 'shanghai_gps')
      ..setField('created_at', 1700000000000)
      ..setField('latitude', 31.2)
      ..setField('longitude', 121.5);

    // Doc C: no real GPS. PocketSearch writes sentinel 0.0 values instead
    // of omitting the fields, because missing fields pass zvec filters.
    final docC = Doc(id: 'no_gps')
      ..setVector('embedding', _randomUnitVector(3))
      ..setField('photo_id', 'no_gps')
      ..setField('created_at', 1700000000000)
      ..setField('latitude', 0.0)
      ..setField('longitude', 0.0);

    collection.insert([docA, docB, docC]);
    collection.optimize();
    for (final d in [docA, docB, docC]) {
      d.destroy();
    }

    final filter =
        'latitude >= 22.1 AND latitude <= 22.5 '
        'AND longitude >= 113.4 AND longitude <= 113.8';

    // Use a query vector chosen to be near every doc by L2 distance, so we
    // know lack of recall is due to filter, not vector ranking.
    final query = VectorQuery(
      fieldName: 'embedding',
      vector: Float32List(512),
      topk: 100,
      outputFields: ['photo_id'],
      filter: filter,
    );

    final results = collection.query(query);
    query.destroy();

    final ids = results.map((r) => r.getString('photo_id') ?? r.pk).toList();
    // ignore: avoid_print
    print('====================================================');
    // ignore: avoid_print
    print('FILTER: $filter');
    // ignore: avoid_print
    print('RESULTS (${ids.length}): $ids');
    // ignore: avoid_print
    print('====================================================');

    expect(ids, contains('macau_gps'));
    expect(ids, isNot(contains('shanghai_gps')));
    expect(
      ids,
      isNot(contains('no_gps')),
      reason: 'Doc with sentinel latitude/longitude must not pass geo filter',
    );
  });

  testWidgets(
    'Without filter: all docs (including no-gps) should be recalled',
    (tester) async {
      final docA = Doc(id: 'has_gps')
        ..setVector('embedding', _randomUnitVector(20))
        ..setField('photo_id', 'has_gps')
        ..setField('latitude', 22.2)
        ..setField('longitude', 113.55);

      final docB = Doc(id: 'no_gps')
        ..setVector('embedding', _randomUnitVector(21))
        ..setField('photo_id', 'no_gps')
        ..setField('latitude', 0.0)
        ..setField('longitude', 0.0);

      collection.insert([docA, docB]);
      collection.optimize();
      docA.destroy();
      docB.destroy();

      final query = VectorQuery(
        fieldName: 'embedding',
        vector: Float32List(512),
        topk: 100,
        outputFields: ['photo_id'],
      );

      final results = collection.query(query);
      query.destroy();

      final ids = results.map((r) => r.getString('photo_id') ?? r.pk).toSet();
      // ignore: avoid_print
      print('NO-FILTER RESULTS: $ids');

      expect(ids, contains('has_gps'));
      expect(
        ids,
        contains('no_gps'),
        reason: 'Without filter both docs should be recalled',
      );
    },
  );

  testWidgets('DATE filter: sentinel created_at docs must NOT be recalled', (
    tester,
  ) async {
    final docA = Doc(id: 'may_2026')
      ..setVector('embedding', _randomUnitVector(30))
      ..setField('photo_id', 'may_2026')
      ..setField('created_at', 1779148800000); // 2026-05-19

    final docB = Doc(id: 'jan_2024')
      ..setVector('embedding', _randomUnitVector(31))
      ..setField('photo_id', 'jan_2024')
      ..setField('created_at', 1704067200000); // 2024-01-01

    final docC = Doc(id: 'no_date')
      ..setVector('embedding', _randomUnitVector(32))
      ..setField('photo_id', 'no_date')
      ..setField('created_at', 0);

    collection.insert([docA, docB, docC]);
    collection.optimize();
    for (final d in [docA, docB, docC]) {
      d.destroy();
    }

    // Filter: only May 2026
    final filter = 'created_at >= 1778832000000 AND created_at < 1781510400000';
    final query = VectorQuery(
      fieldName: 'embedding',
      vector: Float32List(512),
      topk: 100,
      outputFields: ['photo_id'],
      filter: filter,
    );

    final results = collection.query(query);
    query.destroy();

    final ids = results.map((r) => r.getString('photo_id') ?? r.pk).toSet();
    // ignore: avoid_print
    print('DATE FILTER RESULTS: $ids');

    expect(ids, contains('may_2026'));
    expect(ids, isNot(contains('jan_2024')));
    expect(
      ids,
      isNot(contains('no_date')),
      reason: 'Doc with sentinel created_at must not pass date filter',
    );
  });
}

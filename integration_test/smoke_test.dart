// End-to-end smoke tests that exercise the REAL native stack:
//   - MNN FFI (image & text encoders)
//   - zvec FFI (HNSW vector store)
//   - Flutter asset bundle
//
// These tests must be run on a real device or emulator, e.g.:
//   flutter test integration_test/smoke_test.dart
//
// They intentionally skip anything that requires OS permissions
// (photo gallery, camera) — covered by manual QA.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mnn/mnn.dart' as mnn;
import 'package:path_provider/path_provider.dart';

import 'package:pocketsearch/services/clip_service.dart';
import 'package:pocketsearch/services/index_service.dart';
import 'package:pocketsearch/services/tokenizer.dart';
import 'package:pocketsearch/services/vector_store.dart';
import 'package:pocketsearch/utils/vec_math.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ClipService clip;
  late Tokenizer tokenizer;
  late VectorStore store;

  setUpAll(() async {
    final appDir = await getApplicationDocumentsDirectory();

    final imageModel = await rootBundle.load(
      'assets/models/mobileclip_s1_image_encoder.mnn',
    );
    final textModel = await rootBundle.load(
      'assets/models/mobileclip_s1_text_encoder.mnn',
    );

    clip = ClipService.instance;
    await clip.initialize(
      imageModelData: imageModel.buffer.asUint8List(),
      textModelData: textModel.buffer.asUint8List(),
    );

    // Dump raw native tensor shape/dtype so we can see what the MNN graph
    // actually expects — critical for diagnosing encoder bugs.
    final _imgNet = mnn.Interpreter.fromBuffer(imageModel.buffer.asUint8List());
    _imgNet.setSessionMode(mnn.SessionMode.Session_Backend_Auto);
    final _sess = _imgNet.createSession(
        config: mnn.ScheduleConfig.create(type: mnn.ForwardType.MNN_FORWARD_AUTO));
    final _input = _imgNet.getSessionInput(_sess);
    final _output = _imgNet.getSessionOutput(_sess);
    // ignore: avoid_print
    print('=== IMAGE MODEL NATIVE TENSORS ===');
    // ignore: avoid_print
    print('input:  shape=${_input?.shape} type=${_input?.type}');
    // ignore: avoid_print
    print('output: shape=${_output?.shape} type=${_output?.type}');
    final _allOut = _imgNet.getSessionOutputAll(_sess);
    // ignore: avoid_print
    print('image outputs (${_allOut.length}): '
        '${_allOut.entries.map((e) => "${e.key}=${e.value.shape}").join(", ")}');

    // Also dump text encoder tensors.
    final _txtNet = mnn.Interpreter.fromBuffer(textModel.buffer.asUint8List());
    _txtNet.setSessionMode(mnn.SessionMode.Session_Backend_Auto);
    final _tsess = _txtNet.createSession(
        config: mnn.ScheduleConfig.create(type: mnn.ForwardType.MNN_FORWARD_AUTO));
    final _tin = _txtNet.getSessionInput(_tsess);
    final _tout = _txtNet.getSessionOutput(_tsess);
    final _tAll = _txtNet.getSessionOutputAll(_tsess);
    // ignore: avoid_print
    print('TEXT input: shape=${_tin?.shape} type=${_tin?.type}');
    // ignore: avoid_print
    print('TEXT output(default): shape=${_tout?.shape} type=${_tout?.type}');
    // ignore: avoid_print
    print('text outputs (${_tAll.length}): '
        '${_tAll.entries.map((e) => "${e.key}=${e.value.shape}").join(", ")}');
    tokenizer = Tokenizer();
    await tokenizer.load('assets/tokenizer/bpe_vocab.json');

    store = VectorStore();
    await store.initialize('${appDir.path}/zvec_smoke_${DateTime.now().millisecondsSinceEpoch}');
  });

  tearDownAll(() {
    store.dispose();
    clip.dispose();
  });

  testWidgets('CLIP image encoder returns 512-dim unit-norm embedding',
      (tester) async {
    final bytes = await rootBundle.load('assets/test_images/solid_red.png');
    final emb = clip.encodeImage(bytes.buffer.asUint8List());

    expect(emb.length, 512);

    double norm = 0;
    for (final x in emb) {
      norm += x * x;
    }
    expect(math.sqrt(norm), closeTo(1.0, 1e-4));
  });

  testWidgets('CLIP text encoder returns 512-dim unit-norm embedding',
      (tester) async {
    final ids = tokenizer.encode('a photo of a cat');
    final emb = clip.encodeText(ids);

    expect(emb.length, 512);

    double norm = 0;
    for (final x in emb) {
      norm += x * x;
    }
    expect(math.sqrt(norm), closeTo(1.0, 1e-4));
  });

  testWidgets('Text embeddings are deterministic (same input → same vector)',
      (tester) async {
    final ids = tokenizer.encode('a photo of a dog');
    final a = clip.encodeText(ids);
    final b = clip.encodeText(ids);

    final sim = VecMath.cosineSimilarity(a, b);
    expect(sim, closeTo(1.0, 1e-4));
  });

  // CRITICAL regression: reproduces the user-visible "every query returns
  // the same photos" symptom at the image-encoder layer. If three solid
  // images of different primary colors produce near-identical embeddings,
  // the image preprocessing pipeline (CHW layout, channel order, or
  // normalization) is collapsing inputs.
  testWidgets('Different images produce DIFFERENT image embeddings',
      (tester) async {
    final red = (await rootBundle.load('assets/test_images/solid_red.png'))
        .buffer.asUint8List();
    final green = (await rootBundle.load('assets/test_images/solid_green.png'))
        .buffer.asUint8List();
    final blue = (await rootBundle.load('assets/test_images/solid_blue.png'))
        .buffer.asUint8List();

    final er = clip.encodeImage(red);
    final eg = clip.encodeImage(green);
    final eb = clip.encodeImage(blue);

    final rg = VecMath.cosineSimilarity(er, eg);
    final rb = VecMath.cosineSimilarity(er, eb);
    final gb = VecMath.cosineSimilarity(eg, eb);
    // ignore: avoid_print
    print('image sims: red/green=${rg.toStringAsFixed(4)} '
        'red/blue=${rb.toStringAsFixed(4)} '
        'green/blue=${gb.toStringAsFixed(4)}');
    // Three solid primary colors must be distinguishable. If all sims are
    // > 0.99 the image encoder pipeline is broken.
    expect(rg, lessThan(0.99));
    expect(rb, lessThan(0.99));
    expect(gb, lessThan(0.99));
  });

  // DECISIVE regression: two REAL photos with very different content
  // (a cluttered product shelf vs a pure UI screenshot) MUST produce
  // embeddings that are distinguishable. If their cosine similarity is
  // > 0.95, the image encoder is collapsing all real photos into one
  // cluster — exactly matching the user-reported "every query returns
  // the same photos" symptom.
  testWidgets('REAL photos produce DIFFERENT image embeddings',
      (tester) async {
    final a = (await rootBundle.load('assets/test_images/real/photo_a.jpg'))
        .buffer.asUint8List();
    final b = (await rootBundle.load('assets/test_images/real/photo_b.jpg'))
        .buffer.asUint8List();
    final ea = clip.encodeImage(a);
    final eb = clip.encodeImage(b);
    final sim = VecMath.cosineSimilarity(ea, eb);
    // ignore: avoid_print
    print('REAL photo_a vs photo_b cosine = ${sim.toStringAsFixed(4)}');
    // Print first 8 dims of each embedding to eyeball whether the vectors
    // are truly distinct or just noise-perturbed near-copies.
    // ignore: avoid_print
    print('ea[0..7] = ${ea.sublist(0, 8).map((v) => v.toStringAsFixed(4)).join(",")}');
    // ignore: avoid_print
    print('eb[0..7] = ${eb.sublist(0, 8).map((v) => v.toStringAsFixed(4)).join(",")}');
    expect(sim, lessThan(0.95),
        reason: 'Two very different real photos should not produce near-identical embeddings');
  });

  // DECISIVE cross-modal diagnostic: print cosine(text, real_image) for a
  // variety of unrelated queries. If all queries score real photos in a
  // tight 0.15–0.25 band, text/image embeddings are in misaligned spaces.
  testWidgets('Diagnostic: cross-modal cosine distribution on real photos',
      (tester) async {
    final a = (await rootBundle.load('assets/test_images/real/photo_a.jpg'))
        .buffer.asUint8List();
    final b = (await rootBundle.load('assets/test_images/real/photo_b.jpg'))
        .buffer.asUint8List();
    final ea = clip.encodeImage(a);
    final eb = clip.encodeImage(b);

    for (final q in ['airplane', 'cat', 'shelf with bags and boxes',
        'screenshot of a user interface', 'mountain', 'coffee']) {
      final t = clip.encodeText(tokenizer.encode(q));
      final sa = VecMath.cosineSimilarity(t, ea);
      final sb = VecMath.cosineSimilarity(t, eb);
      // ignore: avoid_print
      print('text="$q"  photo_a(shelf)=${sa.toStringAsFixed(4)}  '
          'photo_b(UI-screenshot)=${sb.toStringAsFixed(4)}');
    }
  });

  // Cross-modal sanity: text "red"/"green"/"blue" must rank the matching
  // solid-color image as top-1. This is the strongest end-to-end check.
  testWidgets('Cross-modal: text color queries rank matching color image #1',
      (tester) async {
    final red = (await rootBundle.load('assets/test_images/solid_red.png'))
        .buffer.asUint8List();
    final green = (await rootBundle.load('assets/test_images/solid_green.png'))
        .buffer.asUint8List();
    final blue = (await rootBundle.load('assets/test_images/solid_blue.png'))
        .buffer.asUint8List();

    final er = clip.encodeImage(red);
    final eg = clip.encodeImage(green);
    final eb = clip.encodeImage(blue);

    final imgs = {'red': er, 'green': eg, 'blue': eb};
    for (final color in ['red', 'green', 'blue']) {
      final q = clip.encodeText(tokenizer.encode('a $color color'));
      final scored = imgs.entries
          .map((e) => MapEntry(e.key, VecMath.cosineSimilarity(q, e.value)))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('text "$color" -> ${scored.map((e) => "${e.key}=${e.value.toStringAsFixed(3)}").join(", ")}');
      expect(scored.first.key, color,
          reason: 'text "$color" must match $color image, got ${scored.first.key}');
    }
  });

  // CRITICAL regression: if two distinct queries produce near-identical
  // text embeddings, every query will return the same top-K from zvec.
  testWidgets('Different text queries produce DIFFERENT embeddings',
      (tester) async {
    final pairs = <List<String>>[
      ['a photo of a cat', 'a photo of a mountain landscape'],
      ['red car on the street', 'a cup of coffee on a table'],
      ['birthday cake with candles', 'snow covered trees at night'],
    ];
    for (final p in pairs) {
      final a = clip.encodeText(tokenizer.encode(p[0]));
      final b = clip.encodeText(tokenizer.encode(p[1]));
      final sim = VecMath.cosineSimilarity(a, b);
      // CLIP text embeddings for semantically distinct captions should
      // have cosine similarity well below 0.95. If this fails, the text
      // encoder or tokenizer is collapsing inputs.
      expect(sim, lessThan(0.95),
          reason: 'Queries "${p[0]}" vs "${p[1]}" should differ (sim=$sim)');
      // ignore: avoid_print
      print('sim("${p[0]}", "${p[1]}") = ${sim.toStringAsFixed(4)}');
    }
  });

  // CRITICAL regression: end-to-end semantic ranking must actually rank.
  // Insert N distinct random unit vectors as "photos", then for each
  // "query" vector closest to a specific photo, verify it ranks #1.
  // If this fails for different queries the reported "same results" bug
  // is reproduced at the VectorStore layer.
  testWidgets('VectorStore ranks different queries differently',
      (tester) async {
    final appDir = await getApplicationDocumentsDirectory();
    final s = VectorStore();
    await s.initialize(
        '${appDir.path}/zvec_rank_${DateTime.now().millisecondsSinceEpoch}');

    final rng = math.Random(42);
    Float32List randUnit() {
      final v = Float32List(512);
      for (var i = 0; i < v.length; i++) {
        v[i] = rng.nextDouble() * 2 - 1;
      }
      return VecMath.l2NormalizeInPlace(v);
    }

    final vectors = List.generate(10, (_) => randUnit());
    for (var i = 0; i < vectors.length; i++) {
      s.insert(photoId: 'p$i', vector: vectors[i], photoPath: '/t/$i.jpg');
    }
    s.optimize();

    // Each vector queried should return itself as top-1.
    for (var i = 0; i < vectors.length; i++) {
      final r = s.query(vectors[i], topK: 1);
      expect(r, isNotEmpty);
      expect(r.first.photoId, 'p$i',
          reason: 'Query of p$i must rank itself first');
    }
    s.dispose();
  });

  testWidgets('VectorStore insert → query round-trip returns the query vector '
      'as top-1', (tester) async {
    // Three distinct random unit vectors
    final rng = math.Random(7);
    Float32List randUnit() {
      final v = Float32List(512);
      for (var i = 0; i < v.length; i++) {
        v[i] = rng.nextDouble() * 2 - 1;
      }
      return VecMath.l2NormalizeInPlace(v);
    }

    final v1 = randUnit();
    final v2 = randUnit();
    final v3 = randUnit();

    store.insert(photoId: 'p1', vector: v1, photoPath: '/t/1.jpg');
    store.insert(photoId: 'p2', vector: v2, photoPath: '/t/2.jpg');
    store.insert(photoId: 'p3', vector: v3, photoPath: '/t/3.jpg');
    store.optimize();

    expect(store.count, greaterThanOrEqualTo(3));

    final results = store.query(v2, topK: 3);
    expect(results, isNotEmpty);
    expect(results.first.photoId, 'p2');
    expect(results.first.photoPath, '/t/2.jpg');
  });

  testWidgets('End-to-end: image + text embedding + vector store',
      (tester) async {
    final bytes = await rootBundle.load('assets/test_images/solid_red.png');
    final imgEmb = clip.encodeImage(bytes.buffer.asUint8List());

    store.insert(
      photoId: 'red_photo',
      vector: imgEmb,
      photoPath: '/t/red.png',
    );
    store.optimize();

    final textEmb = clip.encodeText(tokenizer.encode('red'));
    final results = store.query(textEmb, topK: 5);

    // We can't guarantee relevance for a synthetic 16x16 red PNG,
    // but we MUST get our inserted doc back somewhere in the candidate set.
    expect(results, isNotEmpty);
    expect(
      results.any((r) => r.photoId == 'red_photo'),
      isTrue,
      reason: 'Inserted photo must appear in query results',
    );
  });

  testWidgets('Encoding performance sanity check', (tester) async {
    final ids = tokenizer.encode('a photo of a sunset over mountains');

    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      clip.encodeText(ids);
    }
    sw.stop();

    final avgMs = sw.elapsedMilliseconds / 5;
    // Loose upper bound: text encoder should comfortably finish under 2s
    // on any reasonable device. Tighten later once we have baselines.
    expect(avgMs, lessThan(2000));
    // ignore: avoid_print
    print('Text encoder avg: ${avgMs.toStringAsFixed(1)} ms/call');
  });

  testWidgets('Image encoding benchmark (used to estimate full-gallery indexing time)',
      (tester) async {
    final bytes = (await rootBundle.load('assets/test_images/solid_red.png'))
        .buffer
        .asUint8List();

    // Warm up once (first call includes tensor allocation & session resize)
    clip.encodeImage(bytes);

    const iterations = 10;
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      clip.encodeImage(bytes);
    }
    sw.stop();

    final avgMs = sw.elapsedMilliseconds / iterations;
    expect(avgMs, lessThan(5000));
    // ignore: avoid_print
    print('Image encoder avg: ${avgMs.toStringAsFixed(1)} ms/call '
        '(over $iterations iterations, 16x16 input)');
  });

  // Regression: on second cold-start a real user hits an existing dbPath.
  // zvec's Collection.createAndOpen crashes with "path exists" in that case,
  // so VectorStore.initialize must fall back to Collection.open.
  testWidgets('VectorStore.initialize is idempotent across sessions',
      (tester) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath =
        '${appDir.path}/zvec_reopen_${DateTime.now().millisecondsSinceEpoch}';

    final a = VectorStore();
    await a.initialize(dbPath); // first session → create
    final rng = math.Random(11);
    final v = Float32List(512);
    for (var i = 0; i < v.length; i++) {
      v[i] = rng.nextDouble() * 2 - 1;
    }
    VecMath.l2NormalizeInPlace(v);
    a.insert(photoId: 'persist', vector: v, photoPath: '/t/persist.jpg');
    a.optimize();
    a.dispose();

    // Second "cold start": same path must be re-opened, not re-created.
    final b = VectorStore();
    await b.initialize(dbPath);
    expect(b.count, greaterThanOrEqualTo(1),
        reason: 'Re-opened collection must retain previously inserted docs');
    final res = b.query(v, topK: 1);
    expect(res, isNotEmpty);
    expect(res.first.photoId, 'persist');
    b.dispose();
  });

  // ---------------------------------------------------------------------------
  // Cold-start sync regression: VectorStore CRUD primitives that the
  // IndexService stale-cleanup path depends on. Locking these down
  // prevents the "deleted photos still appear in search" bug from
  // resurfacing after future zvec API upgrades.
  // ---------------------------------------------------------------------------

  testWidgets('VectorStore.getAllPhotoIds returns every inserted PK',
      (tester) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath =
        '${appDir.path}/zvec_listids_${DateTime.now().millisecondsSinceEpoch}';

    final s = VectorStore();
    await s.initialize(dbPath);
    expect(s.getAllPhotoIds(), isEmpty,
        reason: 'fresh store must report no photos');

    final rng = math.Random(7);
    final inserted = <String>{};
    for (var i = 0; i < 25; i++) {
      final v = Float32List(512);
      for (var j = 0; j < v.length; j++) {
        v[j] = rng.nextDouble() * 2 - 1;
      }
      VecMath.l2NormalizeInPlace(v);
      final pid = 'asset_$i';
      s.insert(photoId: pid, vector: v, photoPath: '/t/$pid.jpg');
      inserted.add(pid);
    }
    s.optimize();

    final ids = s.getAllPhotoIds();
    expect(ids.toSet(), equals(inserted),
        reason: 'every inserted PK must round-trip through getAllPhotoIds');
    expect(s.count, 25);
    s.dispose();
  });

  testWidgets('VectorStore.deleteByIds removes only the requested records',
      (tester) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath =
        '${appDir.path}/zvec_delete_${DateTime.now().millisecondsSinceEpoch}';

    final s = VectorStore();
    await s.initialize(dbPath);

    final rng = math.Random(13);
    Float32List makeVec() {
      final v = Float32List(512);
      for (var j = 0; j < v.length; j++) {
        v[j] = rng.nextDouble() * 2 - 1;
      }
      VecMath.l2NormalizeInPlace(v);
      return v;
    }

    for (var i = 0; i < 10; i++) {
      s.insert(photoId: 'p_$i', vector: makeVec(), photoPath: '/t/p_$i.jpg');
    }
    s.optimize();
    expect(s.count, 10);

    // Delete an arbitrary subset.
    s.deleteByIds(['p_0', 'p_3', 'p_7']);
    s.optimize();

    final remaining = s.getAllPhotoIds().toSet();
    expect(remaining.contains('p_0'), isFalse);
    expect(remaining.contains('p_3'), isFalse);
    expect(remaining.contains('p_7'), isFalse);
    expect(remaining.length, 7);
    expect(s.count, 7);

    // Empty list must be a no-op (no exceptions, no count change).
    s.deleteByIds(const []);
    expect(s.count, 7);
    s.dispose();
  });

  testWidgets(
      'IndexService.computeSyncPlan + VectorStore.deleteByIds end-to-end '
      'reproduces the stale-cleanup contract',
      (tester) async {
    // This is the FULL closed loop the cold-start sync depends on:
    //   1. Pre-fill DB with 5 "old" photo records.
    //   2. Pretend MediaStore now only contains 3 of them + 2 brand new IDs.
    //   3. Run computeSyncPlan to derive (stale, alreadyIndexed).
    //   4. Apply deleteByIds(stale) to the real zvec collection.
    //   5. Verify the DB ends up containing exactly the 3 surviving IDs
    //      and that getAllPhotoIds reflects the change.
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath =
        '${appDir.path}/zvec_sync_${DateTime.now().millisecondsSinceEpoch}';

    final s = VectorStore();
    await s.initialize(dbPath);

    final rng = math.Random(29);
    Float32List makeVec() {
      final v = Float32List(512);
      for (var j = 0; j < v.length; j++) {
        v[j] = rng.nextDouble() * 2 - 1;
      }
      VecMath.l2NormalizeInPlace(v);
      return v;
    }

    final original = ['old1', 'old2', 'survivor_a', 'old3', 'survivor_b'];
    for (final pid in original) {
      s.insert(photoId: pid, vector: makeVec(), photoPath: '/t/$pid.jpg');
    }
    s.optimize();

    // Live MediaStore: keeps 3 old, adds 2 new (which are NOT in DB yet).
    final liveIds = {'survivor_a', 'survivor_b', 'old3', 'fresh_x', 'fresh_y'};

    final plan = IndexService.computeSyncPlan(
      dbIds: s.getAllPhotoIds(),
      liveIds: liveIds,
    );
    expect(plan.staleIds.toSet(), equals({'old1', 'old2'}),
        reason: 'must plan to drop only the deleted-from-gallery records');
    expect(plan.alreadyIndexed,
        equals({'survivor_a', 'survivor_b', 'old3'}),
        reason: 'must mark all overlapping records as already-indexed');

    s.deleteByIds(plan.staleIds);
    s.optimize();

    final after = s.getAllPhotoIds().toSet();
    expect(after, equals({'survivor_a', 'survivor_b', 'old3'}),
        reason: 'DB must converge to gallery ∩ DB after applying plan');
    expect(s.count, 3);
    s.dispose();
  });
}

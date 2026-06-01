import 'dart:ffi';
import 'dart:typed_data';

import 'package:mnn/mnn.dart' as mnn;
import 'package:mnn/cv.dart' as cv;

import 'package:pocketsearch/utils/vec_math.dart';

/// Service for managing MNN CLIP model lifecycle and inference.
/// Models are loaded once at app startup and kept warm in memory.
class ClipService {
  static final ClipService instance = ClipService._();
  ClipService._();

  mnn.Interpreter? _imageNet;
  mnn.Interpreter? _textNet;
  mnn.Session? _imageSession;
  mnn.Session? _textSession;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Load both CLIP encoders into memory. Call once at app startup.
  Future<void> initialize({
    required Uint8List imageModelData,
    required Uint8List textModelData,
  }) async {
    if (_initialized) return;

    // Load image encoder from buffer
    _imageNet = mnn.Interpreter.fromBuffer(imageModelData);
    _imageNet!.setSessionMode(mnn.SessionMode.Session_Backend_Auto);
    final imageConfig = mnn.ScheduleConfig.create(
      type: mnn.ForwardType.MNN_FORWARD_AUTO,
    );
    _imageSession = _imageNet!.createSession(config: imageConfig);

    // Load text encoder from buffer
    _textNet = mnn.Interpreter.fromBuffer(textModelData);
    _textNet!.setSessionMode(mnn.SessionMode.Session_Backend_Auto);
    final textConfig = mnn.ScheduleConfig.create(
      type: mnn.ForwardType.MNN_FORWARD_AUTO,
    );
    _textSession = _textNet!.createSession(config: textConfig);

    _initialized = true;
  }

  /// Encode raw image bytes (JPEG/PNG) into a 512-dim embedding vector.
  /// Uses MNN's built-in image processing for resize + normalize.
  Float32List encodeImage(Uint8List imageBytes) {
    assert(_initialized, 'ClipService not initialized');

    final input = _imageNet!.getSessionInput(_imageSession!);
    if (input == null || input.isEmpty) {
      throw StateError('Cannot get image encoder input tensor');
    }

    // Resize input tensor to [1, 3, 256, 256]
    _imageNet!.resizeTensor(input, [1, 3, 256, 256]);
    _imageNet!.resizeSession(_imageSession!);

    // Decode, resize, normalize, and convert to planar (CHW) using MNN cv
    // MobileCLIP-S1 uses no per-channel normalization, just scale to [0,1]
    final im = cv.Image.fromBytes(
      imageBytes,
      desiredChannel: cv.StbiChannel.rgb,
    );
    final resized = im.resize(256, 256);
    const mean = [0.0, 0.0, 0.0];
    const std = [1.0, 1.0, 1.0];
    final normalized = resized.normalize(scale: 255.0, mean: mean, std: std);
    final planar = normalized.toPlanar();

    // Create host tensor and copy image data
    final hostTensor = mnn.Tensor.fromTensor(
      input,
      dimType: mnn.DimensionType.MNN_CAFFE,
    );
    hostTensor.setImage(0, planar);
    input.copyFromHost(hostTensor);
    hostTensor.dispose();

    // Run inference
    _imageNet!.runSession(_imageSession!);

    // Get output and extract embedding
    final output = _imageNet!.getSessionOutput(_imageSession!);
    if (output == null || output.isEmpty) {
      throw StateError('Cannot get image encoder output tensor');
    }

    return _extractAndNormalize(output);
  }

  /// Encode tokenized text (Int32List of token IDs) into a 512-dim embedding.
  Float32List encodeText(Int32List tokenIds) {
    assert(_initialized, 'ClipService not initialized');

    final input = _textNet!.getSessionInput(_textSession!);
    if (input == null || input.isEmpty) {
      throw StateError('Cannot get text encoder input tensor');
    }

    // Resize input tensor to [1, contextLength]
    _textNet!.resizeTensor(input, [1, tokenIds.length]);
    _textNet!.resizeSession(_textSession!);

    // Create host tensor and fill with token IDs.
    // IMPORTANT: the text encoder input tensor is INT32 (verified via
    // `input.type`); casting host memory as float32 and writing
    // `tokenIds[i].toDouble()` silently corrupts every token — the model
    // then reads huge garbage integers (bit-pattern reinterpret) and the
    // resulting text embedding is NOT in the same CLIP latent space as
    // the image embedding, which collapses all cross-modal searches
    // (every query returns the same top-K photos).
    final hostTensor = mnn.Tensor.fromTensor(
      input,
      dimType: mnn.DimensionType.MNN_CAFFE,
    );
    final dataPtr = hostTensor.host.cast<mnn.int32>();
    for (var i = 0; i < tokenIds.length; i++) {
      dataPtr[i] = tokenIds[i];
    }
    input.copyFromHost(hostTensor);
    hostTensor.dispose();

    // Run inference
    _textNet!.runSession(_textSession!);

    // Get output and extract embedding
    final output = _textNet!.getSessionOutput(_textSession!);
    if (output == null || output.isEmpty) {
      throw StateError('Cannot get text encoder output tensor');
    }

    return _extractAndNormalize(output);
  }

  /// Extract embedding from output tensor and L2-normalize.
  Float32List _extractAndNormalize(mnn.Tensor output) {
    final hostOutput = mnn.Tensor.fromTensor(
      output,
      dimType: mnn.DimensionType.MNN_CAFFE,
    );
    output.copyToHost(hostOutput);

    final size = hostOutput.getStride(0);
    final embeddingDim = size > 0 ? size : 512;
    final embedding = Float32List(embeddingDim);
    final dataPtr = hostOutput.host.cast<mnn.float32>();
    for (var i = 0; i < embeddingDim; i++) {
      embedding[i] = dataPtr[i];
    }
    hostOutput.dispose();

    // L2 normalize
    return VecMath.l2NormalizeInPlace(embedding);
  }

  void dispose() {
    _imageSession = null;
    _textSession = null;
    _imageNet = null;
    _textNet = null;
    _initialized = false;
  }
}

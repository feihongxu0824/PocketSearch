# MNN.dart `Tensor.host` returns Float32 view even when tensor is Int32

> Draft of an upstream issue to file at <https://github.com/rainyl/mnn.dart>
> (the Dart bindings published as `mnn` 0.1.3 on pub.dev). Until this
> is fixed, see Pitfall #1 in [`README.md`](../../README.md) for the
> required workaround.

## Summary

`Tensor.host` always returns a `Pointer<mnn.float32>`, with no way to
write the same buffer as `int32`. For a CLIP-style **text encoder
whose input is `int32` token ids**, this means writing the tokens via
`tokenIds[i].toDouble()` silently produces garbage — the bit pattern
of a `double` (or `float`) is reinterpreted by the runtime as an
integer, so token id `49406` becomes a 32-bit nonsense integer like
`1199957632`. The model accepts the input shape but the resulting
embedding lives in a different latent space than the image embedding,
and cross-modal cosine similarity collapses to a near-constant
~0.12 across all queries. There is **no error, no warning, no
exception** — just silently wrong results.

## Reproduction

```dart
final net = mnn.Interpreter.fromFile('text_encoder.mnn');
final session = net.createSession();
final input = session.getInput(); // shape: [1, 77], dtype: int32

// What looks correct but is wrong:
final hostF32 = input.host.cast<mnn.float32>();
for (var i = 0; i < tokenIds.length; i++) {
  hostF32[i] = tokenIds[i].toDouble(); // bit-pattern reinterpret
}
session.run();
// → embedding is garbage; cross-modal cosine ≈ 0.12 for every query
```

## Workaround (currently required)

Cast the host pointer to `mnn.int32` and write the raw integer:

```dart
final hostI32 = input.host.cast<mnn.int32>();
for (var i = 0; i < tokenIds.length; i++) {
  hostI32[i] = tokenIds[i]; // raw int write, correct bit pattern
}
```

This works in production (see
[`lib/services/clip_service.dart`](../../lib/services/clip_service.dart)
of zvec-photo-search), but the API surface of `Tensor.host` actively
encourages the wrong path for any tensor whose dtype is not float32.

## Suggested fix

Either of the following would close the foot-gun:

1. **Make `Tensor.host` dtype-aware.** Inspect the tensor's
   `getInfo().dtype` and return a typed pointer
   (`Pointer<mnn.int32>` / `Pointer<mnn.float32>` / etc.). Trying to
   read or write through the wrong type would then need an explicit
   `cast<>()`, which makes the dtype mismatch visible at the call
   site.

2. **Provide convenience writers.** Add `Tensor.copyFromInt32List`,
   `Tensor.copyFromFloat32List`, etc. (mirroring MNN C API's
   `Tensor::copyFromHostTensor`). These should `assert` the dtype
   matches and throw a clear error otherwise.

Either approach would have caught this issue at runtime instead of
producing silently-wrong embeddings that took several hours of
A/B-debugging to root-cause.

## Why this matters

CLIP / MobileCLIP family text encoders are by far the most common
on-device cross-modal use case. Every Dart user wiring up text input
to such a model will hit this trap, because the natural Dart idiom
("write a number into a tensor") goes through `host.cast<float32>()`
without any type signal that the tensor is integer-typed. Silent
garbage is the worst possible failure mode here, especially
combined with how `cosine ≈ 0.12` looks plausible to a casual eye.

## Environment

- `mnn` (Dart) `0.1.3`
- MNN `3.5.0`
- Flutter `3.27.x`, Dart `3.6.x`
- Reproduced on real iPhone (iOS 18) and real Android (API 34)

import 'dart:convert';
import 'dart:typed_data';

/// Packs ink samples as little-endian float32 `x, y, pressure` triplets.
///
/// Stored as base64 inside an op value so the log stays plain JSON. Large
/// strokes may move to a separate blob table later without changing callers.
abstract final class InkCodec {
  static const int stride = 3;

  static String encode(Float32List samples) {
    assert(samples.length % stride == 0);
    final bd = ByteData(samples.length * 4);
    for (var i = 0; i < samples.length; i++) {
      bd.setFloat32(i * 4, samples[i], Endian.little);
    }
    return base64Encode(bd.buffer.asUint8List());
  }

  static Float32List decode(String b64) {
    final bytes = base64Decode(b64);
    final bd = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return out;
  }
}

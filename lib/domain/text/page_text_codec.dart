import 'dart:typed_data';

import 'page_text.dart';

/// Compact binary form of a page's characters, for the on-disk cache.
///
/// Layout (little endian): `"AXT"`, version byte, uint32 count, then `count`
/// int32 code points, then `count * 4` float32 box values. Words and lines are
/// not stored; they are rebuilt from this on load.
class PageTextCodec {
  const PageTextCodec._();

  static const version = 1;
  static const _headerBytes = 8;

  static Uint8List encode(PageText t) {
    final n = t.length;
    final out = Uint8List(_headerBytes + n * 4 + n * 16);
    out[0] = 0x41; // A
    out[1] = 0x58; // X
    out[2] = 0x54; // T
    out[3] = version;
    final bd = ByteData.sublistView(out);
    bd.setUint32(4, n, Endian.little);
    var o = _headerBytes;
    for (var i = 0; i < n; i++, o += 4) {
      bd.setInt32(o, t.codes[i], Endian.little);
    }
    for (var i = 0; i < n * 4; i++, o += 4) {
      bd.setFloat32(o, t.boxes[i], Endian.little);
    }
    return out;
  }

  /// The page, or null if [bytes] is not a valid current-version encoding (a
  /// truncated write or an older format). The caller extracts again.
  static PageText? decode(Uint8List bytes) {
    if (bytes.length < _headerBytes ||
        bytes[0] != 0x41 ||
        bytes[1] != 0x58 ||
        bytes[2] != 0x54 ||
        bytes[3] != version) {
      return null;
    }
    final bd = ByteData.sublistView(bytes);
    final n = bd.getUint32(4, Endian.little);
    if (bytes.length != _headerBytes + n * 4 + n * 16) return null;
    final codes = Int32List(n);
    final boxes = Float32List(n * 4);
    var o = _headerBytes;
    for (var i = 0; i < n; i++, o += 4) {
      codes[i] = bd.getInt32(o, Endian.little);
    }
    for (var i = 0; i < n * 4; i++, o += 4) {
      boxes[i] = bd.getFloat32(o, Endian.little);
    }
    return PageText.build(codes, boxes);
  }
}

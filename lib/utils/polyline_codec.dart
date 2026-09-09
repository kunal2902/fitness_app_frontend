import '../models/route_models.dart';

/// Google's encoded polyline algorithm, precision 5.
///
/// Routes are stored and transported encoded, never as coordinate arrays. A
/// one-hour run at 1 Hz is 3,600 points; as `[{lat,lng},…]` JSON that is
/// hundreds of KB per activity and would dominate the database, where the same
/// route encodes to a few KB of ASCII.
///
/// The algorithm is exact at the stored precision: every coordinate is rounded
/// to five decimal places (about 1.1 m at the equator) and the deltas are
/// accumulated as integers, so `decode(encode(route))` returns the input
/// rounded to 5 dp, with no drift however long the route is.
class PolylineCodec {
  const PolylineCodec._();

  /// Five decimal places, the precision every consumer of this format assumes.
  static const int precision = 5;
  static const double _scale = 100000; // 10^precision

  static String encode(Iterable<RouteCoordinate> coordinates) {
    final StringBuffer out = StringBuffer();
    int previousLatitude = 0;
    int previousLongitude = 0;

    for (final RouteCoordinate c in coordinates) {
      final int latitude = _round(c.latitude);
      final int longitude = _round(c.longitude);
      _writeValue(out, latitude - previousLatitude);
      _writeValue(out, longitude - previousLongitude);
      previousLatitude = latitude;
      previousLongitude = longitude;
    }
    return out.toString();
  }

  /// Throws [FormatException] on malformed input rather than returning a
  /// half-decoded route — a truncated polyline is corrupt data, and silently
  /// dropping its tail would show the user a run that ends in the wrong place.
  static List<RouteCoordinate> decode(String encoded) {
    final List<RouteCoordinate> out = <RouteCoordinate>[];
    int index = 0;
    int latitude = 0;
    int longitude = 0;

    while (index < encoded.length) {
      final int start = index;
      final _Chunk latitudeDelta = _readValue(encoded, index, start);
      index = latitudeDelta.nextIndex;
      if (index >= encoded.length) {
        throw FormatException(
          'Encoded polyline ended after a latitude with no longitude.',
          encoded,
          start,
        );
      }
      final _Chunk longitudeDelta = _readValue(encoded, index, start);
      index = longitudeDelta.nextIndex;

      latitude += latitudeDelta.value;
      longitude += longitudeDelta.value;
      out.add(RouteCoordinate(latitude / _scale, longitude / _scale));
    }
    return out;
  }

  /// Rounds half away from zero, matching the reference implementation.
  /// Dart's [num.round] already does this; the helper exists so the intent is
  /// stated once rather than assumed at three call sites.
  static int _round(double value) => (value * _scale).round();

  static void _writeValue(StringBuffer out, int value) {
    // Zig-zag: shift left one bit and invert the whole thing when negative, so
    // small negative deltas stay short instead of turning into 64 set bits.
    int remaining = value < 0 ? ~(value << 1) : value << 1;
    while (remaining >= 0x20) {
      out.writeCharCode((0x20 | (remaining & 0x1f)) + 63);
      remaining >>= 5;
    }
    out.writeCharCode(remaining + 63);
  }

  static _Chunk _readValue(String encoded, int index, int errorOffset) {
    int result = 0;
    int shift = 0;
    int byte;
    do {
      if (index >= encoded.length) {
        throw FormatException(
          'Encoded polyline ended mid-value.',
          encoded,
          errorOffset,
        );
      }
      byte = encoded.codeUnitAt(index) - 63;
      index += 1;
      if (byte < 0 || shift > 30) {
        throw FormatException(
          'Encoded polyline contains an invalid character.',
          encoded,
          index - 1,
        );
      }
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    // Undo the zig-zag.
    return _Chunk(
      (result & 1) != 0 ? ~(result >> 1) : result >> 1,
      index,
    );
  }
}

class _Chunk {
  const _Chunk(this.value, this.nextIndex);

  final int value;
  final int nextIndex;
}

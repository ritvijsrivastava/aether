/// An automatic, never user-set label for a colour: the nearest of a short
/// list of ordinary colour names ("Coral", "Blue"). Used to head groups in
/// the Markdown export and to describe a colour to a screen reader.
String colourName(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  String best = _names.first.$1;
  var bestD = double.infinity;
  for (final (name, c) in _names) {
    final dr = r - ((c >> 16) & 0xFF),
        dg = g - ((c >> 8) & 0xFF),
        db = b - (c & 0xFF);
    // Weighted so green differences count most, as the eye does.
    final d = 0.30 * dr * dr + 0.59 * dg * dg + 0.11 * db * db;
    if (d < bestD) {
      bestD = d;
      best = name;
    }
  }
  return best;
}

const List<(String, int)> _names = [
  ('Coral', 0xFFF4877E),
  ('Amber', 0xFFF2C94C),
  ('Blue', 0xFF6FB1EE),
  ('Red', 0xFFD93A2F),
  ('Orange', 0xFFF28C28),
  ('Yellow', 0xFFFFE94A),
  ('Lime', 0xFFA6D93A),
  ('Green', 0xFF3FA65B),
  ('Teal', 0xFF2BA6A0),
  ('Sky', 0xFF8FD6F2),
  ('Navy', 0xFF2A4C9B),
  ('Purple', 0xFF8456C8),
  ('Lavender', 0xFFC3A9EC),
  ('Pink', 0xFFF29BC1),
  ('Brown', 0xFF8A5A3C),
  ('Black', 0xFF2B2723),
  ('Grey', 0xFF8E8A85),
  ('White', 0xFFFFFFFF),
];

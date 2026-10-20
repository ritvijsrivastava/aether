import 'package:aether/domain/marks/colour_name.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the three default swatches are named for what they are', () {
    expect(colourName(Swatch.coral), 'Coral');
    expect(colourName(Swatch.amber), 'Amber');
    expect(colourName(Swatch.blue), 'Blue');
  });

  test('other colours get the nearest ordinary name', () {
    expect(colourName(0xFF000000), 'Black');
    expect(colourName(0xFFFFFFFF), 'White');
    expect(colourName(0xFF22AA44), 'Green');
    expect(colourName(0xFFCC2222), 'Red');
    expect(colourName(0xFF9966DD), 'Purple');
  });

  test('transparency is ignored: only the colour is named', () {
    expect(colourName(0x00F4877E), colourName(0xFFF4877E));
  });
}

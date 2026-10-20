import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'color_disc.dart';

/// Asks for any colour: a saturation/brightness square, a hue bar, a hex
/// field and the [saved] colours to start from. Returns an opaque ARGB value,
/// or null if closed.
Future<int?> showColourPicker(
  BuildContext context, {
  required int initial,
  List<int> saved = const [],
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _PickerDialog(initial: initial, saved: saved),
  );
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({required this.initial, required this.saved});
  final int initial;
  final List<int> saved;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initial));
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(Color(widget.initial)),
  );

  static String _hexOf(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  int get _argb => 0xFF000000 | (_hsv.toColor().toARGB32() & 0xFFFFFF);

  void _set(HSVColor v) => setState(() {
    _hsv = v;
    _hex.text = _hexOf(v.toColor());
  });

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColour(int argb) => _set(HSVColor.fromColor(Color(argb)));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    return Dialog(
      backgroundColor: t.panel,
      insetPadding: const EdgeInsets.all(AetherTokens.s4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AetherTokens.rPanel),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(AetherTokens.s4),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Colour', style: text.panelTitle)),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: t.ink),
                    ),
                  ],
                ),
                _SvSquare(hsv: _hsv, onChanged: _set),
                const SizedBox(height: AetherTokens.s3),
                _HueBar(hsv: _hsv, onChanged: _set),
                const SizedBox(height: AetherTokens.s3),
                Row(
                  children: [
                    ColorDisc(_argb, size: 28),
                    const SizedBox(width: AetherTokens.s2),
                    Expanded(
                      child: TextField(
                        controller: _hex,
                        maxLength: 6,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[0-9a-fA-F]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          prefixText: '#',
                          counterText: '',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          if (v.length == 6) {
                            setState(
                              () => _hsv = HSVColor.fromColor(
                                Color(0xFF000000 | int.parse(v, radix: 16)),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (widget.saved.isNotEmpty) ...[
                  const SizedBox(height: AetherTokens.s3),
                  Text('Saved colours', style: text.label),
                  const SizedBox(height: AetherTokens.s1),
                  Wrap(
                    children: [
                      for (final c in widget.saved)
                        if (c != 0)
                          InkResponse(
                            radius: 24,
                            onTap: () => _setColour(c),
                            child: SizedBox(
                              width: AetherTokens.minTarget,
                              height: AetherTokens.minTarget,
                              child: Center(child: ColorDisc(c)),
                            ),
                          ),
                    ],
                  ),
                ],
                const SizedBox(height: AetherTokens.s3),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_argb),
                    child: const Text('Use colour'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SvSquare extends StatelessWidget {
  const _SvSquare({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Saturation and brightness',
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = 160.0;
          void at(Offset p) => onChanged(
            hsv
                .withSaturation((p.dx / w).clamp(0, 1))
                .withValue(1 - (p.dy / h).clamp(0, 1)),
          );
          return GestureDetector(
            onPanDown: (d) => at(d.localPosition),
            onPanUpdate: (d) => at(d.localPosition),
            child: CustomPaint(size: Size(w, h), painter: _SvPainter(hsv)),
          );
        },
      ),
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(r),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(r),
    );
    canvas.restore();
    final p = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      p,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      p,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_SvPainter o) => o.hsv != hsv;
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hue',
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          void at(Offset p) =>
              onChanged(hsv.withHue((p.dx / w).clamp(0, 1) * 359.99));
          return GestureDetector(
            onPanDown: (d) => at(d.localPosition),
            onPanUpdate: (d) => at(d.localPosition),
            child: CustomPaint(
              size: Size(w, 24),
              painter: _HuePainter(hsv.hue),
            ),
          );
        },
      ),
    );
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(12)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var i = 0; i <= 6; i++)
              HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
          ],
        ).createShader(r),
    );
    final x = hue / 360 * size.width;
    canvas.drawCircle(
      Offset(x, size.height / 2),
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(x, size.height / 2),
      12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_HuePainter o) => o.hue != hue;
}

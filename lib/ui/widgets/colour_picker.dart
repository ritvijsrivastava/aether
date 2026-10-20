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
  late int _argb = 0xFF000000 | (widget.initial & 0xFFFFFF);

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
                ColourPickerBody(
                  argb: _argb,
                  squareHeight: 160,
                  onChanged: (c) => setState(() => _argb = c),
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
                            onTap: () => setState(
                              () => _argb = 0xFF000000 | (c & 0xFFFFFF),
                            ),
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

/// The picker itself, without a frame: a saturation/brightness square, a hue
/// bar and red, green and blue fields. It reports every change as an opaque
/// ARGB value, and follows [argb] when the caller changes the colour (for
/// example a tap on a saved colour).
class ColourPickerBody extends StatefulWidget {
  const ColourPickerBody({
    super.key,
    required this.argb,
    required this.onChanged,
    this.squareHeight = 120,
  });

  final int argb;
  final ValueChanged<int> onChanged;
  final double squareHeight;

  @override
  State<ColourPickerBody> createState() => _ColourPickerBodyState();
}

class _ColourPickerBodyState extends State<ColourPickerBody> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.argb));
  final List<TextEditingController> _rgb = [
    for (var i = 0; i < 3; i++) TextEditingController(),
  ];
  final List<FocusNode> _focus = [for (var i = 0; i < 3; i++) FocusNode()];

  int get _argb => 0xFF000000 | (_hsv.toColor().toARGB32() & 0xFFFFFF);

  @override
  void initState() {
    super.initState();
    _syncFields();
  }

  @override
  void didUpdateWidget(ColourPickerBody old) {
    super.didUpdateWidget(old);
    // The colour changed from outside (a saved colour was tapped).
    if ((widget.argb & 0xFFFFFF) != (_argb & 0xFFFFFF)) {
      _hsv = HSVColor.fromColor(Color(widget.argb));
      _syncFields();
    }
  }

  void _syncFields() {
    final c = Color(_argb);
    final v = [c.r, c.g, c.b];
    for (var i = 0; i < 3; i++) {
      if (!_focus[i].hasFocus) _rgb[i].text = '${(v[i] * 255).round()}';
    }
  }

  void _set(HSVColor v) {
    setState(() => _hsv = v);
    _syncFields();
    widget.onChanged(_argb);
  }

  void _typed() {
    final v = [for (final c in _rgb) int.tryParse(c.text)];
    if (v.any((e) => e == null)) return;
    final c = Color.fromARGB(
      255,
      v[0]!.clamp(0, 255),
      v[1]!.clamp(0, 255),
      v[2]!.clamp(0, 255),
    );
    setState(() => _hsv = HSVColor.fromColor(c));
    widget.onChanged(_argb);
  }

  @override
  void dispose() {
    for (final c in _rgb) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    const labels = ['R', 'G', 'B'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SvSquare(hsv: _hsv, onChanged: _set, height: widget.squareHeight),
        const SizedBox(height: AetherTokens.s2),
        _HueBar(hsv: _hsv, onChanged: _set),
        const SizedBox(height: AetherTokens.s2),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: AetherTokens.s1),
              Expanded(
                child: TextField(
                  controller: _rgb[i],
                  focusNode: _focus[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 3,
                  style: text.label,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    prefixText: '${labels[i]} ',
                    prefixStyle: text.caption.copyWith(color: t.inkMuted),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => _typed(),
                  onEditingComplete: () {
                    _focus[i].unfocus();
                    _syncFields();
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SvSquare extends StatelessWidget {
  const _SvSquare({
    required this.hsv,
    required this.onChanged,
    required this.height,
  });
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Saturation and brightness',
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = height;
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
    final r = Rect.fromLTWH(0, size.height / 2 - 5, size.width, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(5)),
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
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(x, size.height / 2),
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_HuePainter o) => o.hue != hue;
}

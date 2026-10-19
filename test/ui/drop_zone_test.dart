import 'dart:io' show Platform;

import 'package:aether/app/drop_zone.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plays the Linux side of the `desktop_drop` plugin: GTK sends the dropped
/// items as newline-separated URIs.
Future<void> platformSays(String method, Object? args) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
}

Future<void> drop(WidgetTester tester, List<String> uris) async {
  await platformSays('entered', [10.0, 10.0]);
  await platformSays('performOperation_linux', [
    '${uris.join('\n')}\n',
    [10.0, 10.0],
  ]);
  await tester.pump();
}

void main() {
  final onLinux = Platform.isLinux ? null : 'drop handling is Linux only';

  late List<List<String>> received;
  var rejected = 0;

  Future<void> pumpZone(WidgetTester tester) async {
    received = [];
    rejected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AetherTokens.light),
        home: DropZone(
          onFiles: received.add,
          onRejected: () => rejected++,
          child: const Scaffold(body: Center(child: Text('library'))),
        ),
      ),
    );
  }

  test('only local files ending in .pdf count, in any case', () {
    expect(DropZone.isPdf('/home/me/paper.pdf'), isTrue);
    expect(DropZone.isPdf('/home/me/PAPER.PDF'), isTrue);
    expect(DropZone.isPdf('/home/me/notes.txt'), isFalse);
    expect(DropZone.isPdf('/home/me/pdf'), isFalse);
    expect(DropZone.isPdf('https://example.com/x.pdf'), isFalse);
    expect(DropZone.isPdf('smb://server/share/x.pdf'), isFalse);
  });

  testWidgets('dropping PDFs imports them, decoding the file URIs', (
    tester,
  ) async {
    await pumpZone(tester);
    await drop(tester, [
      'file:///home/me/My%20Paper.pdf',
      'file:///home/me/Other.PDF',
    ]);
    expect(received, [
      ['/home/me/My Paper.pdf', '/home/me/Other.PDF'],
    ]);
    expect(rejected, 0);
  }, skip: onLinux != null);

  testWidgets('non-PDFs in a mixed drop are left out', (tester) async {
    await pumpZone(tester);
    await drop(tester, [
      'file:///a/x.pdf',
      'file:///a/readme.txt',
      'file:///a/y.png',
    ]);
    expect(received.single, ['/a/x.pdf']);
    expect(rejected, 0);
  }, skip: onLinux != null);

  testWidgets('a drop with no PDF at all is rejected', (tester) async {
    await pumpZone(tester);
    await drop(tester, ['file:///a/readme.txt']);
    expect(received, isEmpty);
    expect(rejected, 1);
  }, skip: onLinux != null);

  testWidgets('remote URIs are rejected, not fetched', (tester) async {
    await pumpZone(tester);
    await drop(tester, [
      'https://example.com/paper.pdf',
      'smb://nas/share/paper.pdf',
    ]);
    expect(received, isEmpty);
    expect(rejected, 1);
  }, skip: onLinux != null);

  testWidgets('dragging over shows the drop hint, leaving hides it', (
    tester,
  ) async {
    await pumpZone(tester);
    expect(find.text('Drop PDFs to import'), findsNothing);
    await platformSays('entered', [10.0, 10.0]);
    await tester.pump();
    expect(find.text('Drop PDFs to import'), findsOneWidget);
    await platformSays('exited', null);
    await tester.pump();
    expect(find.text('Drop PDFs to import'), findsNothing);
  }, skip: onLinux != null);

  testWidgets('the hint disappears after a drop too', (tester) async {
    await pumpZone(tester);
    await drop(tester, ['file:///a/x.pdf']);
    expect(find.text('Drop PDFs to import'), findsNothing);
  }, skip: onLinux != null);
}

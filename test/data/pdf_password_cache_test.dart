import 'package:aether/data/pdf/pdf_password_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PdfPasswordCache cache;
  late List<String?> answers;
  var prompted = 0;
  Future<String?> prompt() async {
    prompted++;
    return answers.removeAt(0);
  }

  setUp(() {
    cache = PdfPasswordCache();
    answers = [];
    prompted = 0;
  });

  test(
    'with nothing remembered it prompts, and remembers what worked',
    () async {
      answers = ['secret'];
      final a = cache.attempt('h1', prompt);
      expect(await a.provide(), 'secret');
      a.accepted();
      expect(cache.of('h1'), 'secret');
      expect(prompted, 1);
    },
  );

  test('a later open uses the remembered password without asking', () async {
    answers = ['secret'];
    final first = cache.attempt('h1', prompt);
    await first.provide();
    first.accepted();

    final second = cache.attempt('h1', prompt);
    expect(await second.provide(), 'secret');
    expect(prompted, 1, reason: 'not asked again');
    expect(second.prompts, 0);
  });

  test('passwords are per document', () async {
    answers = ['a', 'b'];
    final one = cache.attempt('h1', prompt);
    await one.provide();
    one.accepted();
    final two = cache.attempt('h2', prompt);
    expect(await two.provide(), 'b', reason: 'h2 has its own, so it prompts');
    two.accepted();
    expect(cache.of('h1'), 'a');
    expect(cache.of('h2'), 'b');
  });

  test('a wrong guess is not remembered', () async {
    answers = ['nope', 'secret'];
    final a = cache.attempt('h1', prompt);
    await a.provide(); // wrong, pdfium asks again
    expect(cache.of('h1'), isNull);
    await a.provide();
    a.accepted();
    expect(cache.of('h1'), 'secret');
  });

  test(
    'a remembered password that stops working is dropped and the user is asked',
    () async {
      // Remember "old" through a successful attempt.
      answers = ['old'];
      final seed = cache.attempt('h2', prompt);
      await seed.provide();
      seed.accepted();

      answers = ['new'];
      final a = cache.attempt('h2', prompt);
      expect(await a.provide(), 'old'); // remembered, tried first
      expect(
        await a.provide(),
        'new',
        reason: 'it failed, so the user is asked',
      );
      expect(
        cache.of('h2'),
        isNull,
        reason: 'the stale one is gone until the new one is accepted',
      );
      a.accepted();
      expect(cache.of('h2'), 'new');
    },
  );

  test('giving up remembers nothing', () async {
    answers = [null];
    final a = cache.attempt('h1', prompt);
    expect(await a.provide(), isNull);
    a.accepted();
    expect(cache.of('h1'), isNull);
  });

  test('an empty password is never stored', () async {
    answers = [''];
    final a = cache.attempt('h1', prompt);
    await a.provide();
    a.accepted();
    expect(cache.of('h1'), isNull);
  });
}

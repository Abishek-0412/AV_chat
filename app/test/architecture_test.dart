import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Domain must stay pure Dart so it can be tested and reused anywhere.
void main() {
  test('lib/domain imports no Flutter or plugin packages', () {
    const allowed = [
      'package:av_chat/domain/',
      'package:av_chat/core/',
      'package:av_protocol/',
      'package:crypto/',
      'package:meta/',
      'dart:',
    ];
    final offenders = <String>[];
    final files = Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final imports = RegExp(
        r'''^import\s+['"]([^'"]+)['"]''',
        multiLine: true,
      ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!);
      for (final uri in imports) {
        final ok = !uri.contains(':') || allowed.any(uri.startsWith);
        if (!ok) offenders.add('${file.path}: $uri');
      }
    }
    expect(offenders, isEmpty);
  });
}

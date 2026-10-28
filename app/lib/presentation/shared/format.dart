/// Small, dependency-free formatting helpers.
abstract final class Format {
  static String time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String duration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p.characters.first).join();
    return letters.toUpperCase();
  }
}

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}

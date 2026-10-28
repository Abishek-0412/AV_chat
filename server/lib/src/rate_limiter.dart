/// Token bucket: allows short bursts, caps the sustained rate.
final class RateLimiter {
  RateLimiter({
    this.capacity = 60,
    this.refillPerSecond = 20,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _tokens = capacity.toDouble(),
       _last = (clock ?? DateTime.now)();

  final int capacity;
  final double refillPerSecond;
  final DateTime Function() _clock;
  double _tokens;
  DateTime _last;

  bool tryTake() {
    final now = _clock();
    final elapsed = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    _tokens = (_tokens + elapsed * refillPerSecond).clamp(
      0,
      capacity.toDouble(),
    );
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}

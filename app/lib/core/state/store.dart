import 'dart:async';

/// A value plus a broadcast stream of its changes. Pure Dart, so the
/// domain layer can expose observable state without Flutter.
final class Store<T> {
  Store(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast(sync: true);

  T get value => _value;

  set value(T next) {
    _value = next;
    _controller.add(next);
  }

  /// Emits the current value first, then every change.
  Stream<T> get stream => Stream.multi((listener) {
    listener.add(_value);
    final sub = _controller.stream.listen(
      listener.add,
      onDone: listener.close,
    );
    listener.onCancel = sub.cancel;
  });

  Future<void> close() => _controller.close();
}

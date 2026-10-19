import 'dart:async';

/// A value that changes over time. [stream] sends the current value first, then every change,
/// to each listener.
final class Latest<T> {
  Latest(this._value);

  T _value;
  final _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T value) {
    _value = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  Stream<T> get stream => Stream.multi((listener) {
    listener.add(_value);
    final subscription = _changes.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = subscription.cancel;
  });

  Future<void> close() => _changes.close();
}

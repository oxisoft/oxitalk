import 'dart:async';
import 'dart:math';

import '../../rust/api/sync.dart';
import '../../util/latest.dart';
import '../api/models.dart';

/// The app's sync policy on top of the SDK's sync service.
///
/// The SDK recovers from network trouble by itself (offline mode). When a sync ends in an
/// error anyway, this restarts it after [firstDelay], doubling up to [maxDelay] while the
/// errors go on.
final class SyncSupervisor {
  SyncSupervisor({
    required Stream<SyncState> states,
    required this._start,
    this.firstDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  }) {
    _subscription = states.listen(_onState);
  }

  final Future<void> Function() _start;
  final Duration firstDelay;
  final Duration maxDelay;
  final status = Latest(SyncStatus.connecting);
  late final StreamSubscription<SyncState> _subscription;
  Timer? _restart;
  late Duration _delay = firstDelay;

  void _onState(SyncState state) {
    switch (state) {
      case SyncState_Running():
        _delay = firstDelay;
        status.value = SyncStatus.online;
      case SyncState_Offline():
        status.value = SyncStatus.offline;
      case SyncState_Error():
        status.value = SyncStatus.connecting;
        _restart?.cancel();
        _restart = Timer(_delay, () => unawaited(_start()));
        _delay = Duration(
          microseconds: min(_delay.inMicroseconds * 2, maxDelay.inMicroseconds),
        );
      case SyncState_Idle() || SyncState_Terminated():
        status.value = SyncStatus.connecting;
    }
  }

  Future<void> close() async {
    _restart?.cancel();
    // Not awaited: a bridge stream's cancel waits for the next state, which may never come.
    unawaited(_subscription.cancel());
    await status.close();
  }
}

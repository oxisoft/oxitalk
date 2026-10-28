import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oxitalk/src/features/calls/call_controller.dart';
import 'package:oxitalk/src/features/calls/call_media.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';

/// The media of a call without LiveKit: connects at once, with this device's tile.
final class FakeCallMedia implements CallMedia {
  FakeCallMedia();

  /// Every media made, in order (the test reads the last).
  static final made = <FakeCallMedia>[];

  final keys = <CallMediaKey>[];
  String? url;
  String? token;
  bool closed = false;
  final _states = StreamController<CallMediaState>.broadcast();
  CallMediaState _state = const CallMediaState();
  AudioRoute route = const AudioRoute('default', 'Speakers');

  static FakeCallMedia create() {
    final media = FakeCallMedia();
    made.add(media);
    return media;
  }

  @override
  CallMediaState get state => _state;

  set state(CallMediaState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Stream<CallMediaState> get states => Stream.multi((listener) {
    listener.add(_state);
    final subscription = _states.stream.listen(listener.add);
    listener.onCancel = subscription.cancel;
  });

  @override
  Future<void> connect({
    required String url,
    required String token,
    required bool camera,
  }) async {
    this.url = url;
    this.token = token;
    state = CallMediaState(
      connection: CallConnection.connected,
      cameraOn: camera,
      tiles: [CallTile(identity: '@me:acme.com:FAKEDEVICE', isLocal: true)],
    );
  }

  /// Someone else's media arrives.
  void addRemote(String identity, {bool encrypted = true}) =>
      state = _state.copyWith(
        tiles: [
          ..._state.tiles,
          CallTile(identity: identity, isLocal: false),
        ],
        encrypted: encrypted,
      );

  @override
  Future<void> setKey(CallMediaKey key) async => keys.add(key);

  @override
  Future<void> setMicrophone(bool on) async =>
      state = _state.copyWith(micOn: on);

  @override
  Future<void> setCamera(bool on) async =>
      state = _state.copyWith(cameraOn: on);

  @override
  Future<bool> canSwitchCamera() async => false;

  @override
  Future<void> switchCamera() async {}

  @override
  Future<(List<AudioRoute>, AudioRoute?)> audioRoutes() async => (
    const [AudioRoute('default', 'Speakers'), AudioRoute('usb', 'Headset')],
    route,
  );

  @override
  Future<void> setAudioRoute(AudioRoute route) async => this.route = route;

  @override
  Widget videoView(CallTile tile, {BoxFit fit = BoxFit.cover}) =>
      const ColoredBox(color: Colors.black);

  @override
  Future<void> close() async => closed = true;
}

/// A ringer that counts instead of ringing.
final class FakeRinger implements Ringer {
  bool ringing = false;
  int starts = 0;

  @override
  Future<void> start() async {
    if (!ringing) starts++;
    ringing = true;
  }

  @override
  Future<void> stop() async => ringing = false;
}

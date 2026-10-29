import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../matrix/api/matrix.dart';
import '../../util/log.dart';

/// One person's picture in the call: their camera, or their name when it is off.
final class CallTile {
  const CallTile({
    required this.identity,
    required this.isLocal,
    this.hasVideo = false,
    this.micOn = true,
    this.speaking = false,
    this.video,
  });

  /// LiveKit identity, `@user:server:DEVICE`.
  final String identity;
  final bool isLocal;
  final bool hasVideo;
  final bool micOn;
  final bool speaking;

  /// The media layer's video track, for [CallMedia.videoView].
  final Object? video;

  /// `@user:server` of [identity].
  String get userId {
    final last = identity.lastIndexOf(':');
    final first = identity.indexOf(':');
    return last > first ? identity.substring(0, last) : identity;
  }
}

/// Where the call's sound comes out.
final class AudioRoute {
  const AudioRoute(this.id, this.label);

  final String id;
  final String label;

  static const earpiece = AudioRoute('earpiece', 'Phone');
  static const speaker = AudioRoute('speaker', 'Speaker');

  @override
  bool operator ==(Object other) => other is AudioRoute && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum CallConnection { idle, connecting, connected, reconnecting, disconnected }

/// What the media side of a call shows.
final class CallMediaState {
  const CallMediaState({
    this.connection = CallConnection.idle,
    this.tiles = const [],
    this.micOn = true,
    this.cameraOn = false,
    this.encrypted = false,
    this.error,
    this.serverVersion,
    this.serverRegion,
  });

  final CallConnection connection;

  /// This device first, then the others in the order they came.
  final List<CallTile> tiles;
  final bool micOn;
  final bool cameraOn;

  /// Media frames are end-to-end encrypted and the others' decrypt.
  final bool encrypted;
  final String? error;

  /// What the media server told about itself when it let this device in.
  final String? serverVersion;
  final String? serverRegion;

  CallMediaState copyWith({
    CallConnection? connection,
    List<CallTile>? tiles,
    bool? micOn,
    bool? cameraOn,
    bool? encrypted,
    String? error,
    String? serverVersion,
    String? serverRegion,
  }) => CallMediaState(
    connection: connection ?? this.connection,
    tiles: tiles ?? this.tiles,
    micOn: micOn ?? this.micOn,
    cameraOn: cameraOn ?? this.cameraOn,
    encrypted: encrypted ?? this.encrypted,
    error: error ?? this.error,
    serverVersion: serverVersion ?? this.serverVersion,
    serverRegion: serverRegion ?? this.serverRegion,
  );
}

/// The media of one call: connects to the SFU, publishes the microphone and camera, and
/// encrypts with the keys the Matrix side hands over. Tests use a fake.
abstract interface class CallMedia {
  CallMediaState get state;

  /// The current state, then every change.
  Stream<CallMediaState> get states;

  Future<void> connect({
    required String url,
    required String token,
    required bool camera,
  });

  /// A frame key for [CallMediaKey.identity]; keys may come before [connect].
  Future<void> setKey(CallMediaKey key);

  Future<void> setMicrophone(bool on);

  Future<void> setCamera(bool on);

  /// Whether there is another camera to switch to.
  Future<bool> canSwitchCamera();

  Future<void> switchCamera();

  /// Where the sound can go, and where it goes now (`null` when unknown).
  Future<(List<AudioRoute>, AudioRoute?)> audioRoutes();

  Future<void> setAudioRoute(AudioRoute route);

  /// The video of [tile] (its [CallTile.video]).
  Widget videoView(CallTile tile, {BoxFit fit = BoxFit.cover});

  Future<void> close();
}

/// Makes the media for each call; tests make fakes.
final callMediaFactoryProvider = Provider<CallMedia Function()>(
  (ref) => LiveKitCallMedia.new,
);

/// Applies frame keys one after the other, in the order they come. Each key goes into its
/// participant's key ring; a key of this device's own also moves the encryptors to its index.
/// livekit_client encrypts with the index that was latest when a track was published, so
/// without the move a new key (after someone left) would never be used.
final class FrameKeyRing {
  FrameKeyRing({required this.store, required this.encryptWith});

  /// Puts a key into the ring of [CallMediaKey.identity].
  final Future<void> Function(CallMediaKey key) store;

  /// Makes this device's encryptors use the key at this index.
  final Future<void> Function(int index) encryptWith;

  Future<void> _last = Future.value();

  /// The index this device encrypts with, once it has a key.
  int? get ownIndex => _ownIndex;
  int? _ownIndex;

  /// Key indexes there are: 0 to 255 (one byte in each frame; the key ring of 256 below and
  /// webrtc-sdk m150 `frame_crypto_transformer.h`, `MAX_KEYRING_SIZE`). The native ring would
  /// file a larger index modulo its size, over another key.
  static const slots = 256;

  /// Applies [key] after the keys before it; a failing key doesn't hold up the next.
  Future<void> add(CallMediaKey key) => _last = _last.then((_) async {
    if (key.index < 0 || key.index >= slots) {
      appLog(
        LogLevel.warn,
        'calls',
        'media key index ${key.index} of ${key.identity} has no slot',
      );
      return;
    }
    try {
      await store(key);
      if (key.isOwn) {
        _ownIndex = key.index;
        await encryptWith(key.index);
      }
    } on Object catch (error) {
      appLog(LogLevel.warn, 'calls', 'media key ${key.index}: $error');
    }
  });

  /// Done when every key added so far is applied.
  Future<void> get applied => _last;
}

/// livekit_client's frame encryption, set up as its `E2EEManager` does (an encryptor for each
/// published track, a decryptor for each subscribed one), with two changes: the state callback
/// is in place before a cryptor starts, and the key index is set before it starts.
/// livekit_client 2.13.2 sets the callback only after two platform calls, by which time the
/// first change, often the only `ok`, may have gone by unseen (`e2ee_manager.dart`,
/// `_addRtpSender`). Data packets are not encrypted (Element Call doesn't either).
final class FrameCryptors extends lk.E2EEManager {
  FrameCryptors(this._provider, {required this.onState}) : super(_provider);

  final lk.BaseKeyProvider _provider;

  /// A cryptor's state changed; [local] for this device's encryptors.
  final void Function(
    String identity,
    String sid,
    lk.E2EEState state, {
    required bool local,
  })
  onState;

  final _cryptors = <(String, String), rtc.FrameCryptor>{};
  final _running = <String, Completer<void>>{};
  lk.EventsListener<lk.RoomEvent>? _listener;
  lk.Room? _room;
  bool _on = true;

  @override
  Future<void> setup(lk.Room room) async {
    if (_room == room) return;
    await close();
    _room = room;
    _listener = room.createListener()
      ..on<lk.LocalTrackPublishedEvent>((event) async {
        final publication = event.publication;
        final sender = publication.track?.sender;
        if (sender == null ||
            !_encrypted(publication, publication.track?.codec)) {
          return;
        }
        final cryptor = await rtc.frameCryptorFactory
            .createFrameCryptorForRtpSender(
              participantId: event.participant.identity,
              sender: sender,
              algorithm: rtc.Algorithm.kAesGcm,
              keyProvider: _provider.keyProvider,
            );
        await _start(
          cryptor,
          event.participant.identity,
          publication.sid,
          local: true,
        );
        (_running[publication.sid] ??= Completer<void>()).tryComplete();
      })
      ..on<lk.TrackSubscribedEvent>((event) async {
        final publication = event.publication;
        final receiver = event.track.receiver;
        final codec = publication.mimeType.split('/').last;
        if (receiver == null || !_encrypted(publication, codec)) return;
        final cryptor = await rtc.frameCryptorFactory
            .createFrameCryptorForRtpReceiver(
              participantId: event.participant.identity,
              receiver: receiver,
              algorithm: rtc.Algorithm.kAesGcm,
              keyProvider: _provider.keyProvider,
            );
        await _start(
          cryptor,
          event.participant.identity,
          publication.sid,
          local: false,
        );
      })
      ..on<lk.LocalTrackUnpublishedEvent>(
        (event) => _stop(event.participant.identity, event.publication.sid),
      )
      ..on<lk.TrackUnsubscribedEvent>(
        (event) => _stop(event.participant.identity, event.publication.sid),
      );
  }

  static bool _encrypted(lk.TrackPublication publication, String? codec) =>
      publication.encryptionType != lk.EncryptionType.kNone &&
      codec?.toLowerCase() != 'av1';

  Future<void> _start(
    rtc.FrameCryptor cryptor,
    String identity,
    String sid, {
    required bool local,
  }) async {
    // Before anything can change: the cryptor is off until setEnabled.
    cryptor.onFrameCryptorStateChanged = (_, state) =>
        onState(identity, sid, _state(state), local: local);
    _cryptors[(identity, sid)] = cryptor;
    await cryptor.setKeyIndex(_provider.getLatestIndex(identity));
    await cryptor.setEnabled(_on);
  }

  Future<void> _stop(String identity, String sid) async {
    final cryptor = _cryptors.remove((identity, sid));
    _running.remove(sid);
    if (cryptor == null) return;
    await cryptor.setEnabled(false);
    await cryptor.dispose();
  }

  /// Done when this device's encryptor for the published track [sid] runs.
  Future<void> encrypting(String sid) =>
      (_running[sid] ??= Completer<void>()).future;

  static lk.E2EEState _state(rtc.FrameCryptorState state) => switch (state) {
    rtc.FrameCryptorState.FrameCryptorStateNew => lk.E2EEState.kNew,
    rtc.FrameCryptorState.FrameCryptorStateOk => lk.E2EEState.kOk,
    rtc.FrameCryptorState.FrameCryptorStateMissingKey =>
      lk.E2EEState.kMissingKey,
    rtc.FrameCryptorState.FrameCryptorStateEncryptionFailed =>
      lk.E2EEState.kEncryptionFailed,
    rtc.FrameCryptorState.FrameCryptorStateDecryptionFailed =>
      lk.E2EEState.kDecryptionFailed,
    rtc.FrameCryptorState.FrameCryptorStateInternalError =>
      lk.E2EEState.kInternalError,
    rtc.FrameCryptorState.FrameCryptorStateKeyRatcheted =>
      lk.E2EEState.kKeyRatcheted,
  };

  @override
  Future<void> setEnabled(bool enabled) async {
    _on = enabled;
    for (final cryptor in _cryptors.values.toList()) {
      await cryptor.setEnabled(enabled);
    }
  }

  @override
  Future<void> setKeyIndex(int keyIndex, {String? participantIdentity}) async {
    final identity = participantIdentity ?? _room?.localParticipant?.identity;
    for (final MapEntry(:key, :value) in _cryptors.entries.toList()) {
      if (key.$1 == identity) await value.setKeyIndex(keyIndex);
    }
  }

  @override
  Future<int> getKeyIndex(String? participantIdentity) async {
    final identity = participantIdentity ?? _room?.localParticipant?.identity;
    for (final MapEntry(:key, :value) in _cryptors.entries.toList()) {
      if (key.$1 == identity) return value.keyIndex;
    }
    return -1;
  }

  @override
  bool get isDataChannelEncryptionEnabled => false;

  @override
  Future<Uint8List?> handleEncryptedData({
    required Uint8List data,
    required Uint8List iv,
    required String participantIdentity,
    required int keyIndex,
  }) async => null;

  Future<void> close() async {
    await _listener?.dispose();
    _listener = null;
    _room = null;
    for (final cryptor in _cryptors.values.toList()) {
      await cryptor.dispose();
    }
    _cryptors.clear();
    _running.clear();
  }
}

extension on Completer<void> {
  void tryComplete() {
    if (!isCompleted) complete();
  }
}

/// LiveKit with frame encryption as Element Call sets it up, so its frames decrypt here and
/// ours there: a key per participant, derived with HKDF, a key ring of 256, ratchet window 10
/// (Element Call `sdk/src/media-backend/livekit/MatrixKeyProvider.ts`; salt, magic bytes and
/// failure tolerance are livekit-client's defaults).
final class LiveKitCallMedia implements CallMedia {
  LiveKitCallMedia() {
    _keys = FrameKeyRing(
      store: (key) async {
        final provider = await _keyProvider;
        await provider.setRawKey(
          key.key,
          participantId: key.identity,
          keyIndex: key.index,
        );
        appLog(
          LogLevel.info,
          'calls',
          'media key ${key.index} for '
              '${key.isOwn ? 'this device' : key.identity}',
        );
      },
      encryptWith: (index) async {
        final cryptors = _cryptors;
        if (cryptors == null) return;
        await cryptors.setKeyIndex(index);
        appLog(LogLevel.info, 'calls', 'encrypting with key $index');
      },
    );
  }

  lk.Room? _room;
  late final FrameKeyRing _keys;
  late final Future<lk.BaseKeyProvider> _keyProvider = _createKeyProvider();
  lk.EventsListener<lk.RoomEvent>? _events;
  final _states = StreamController<CallMediaState>.broadcast();
  CallMediaState _state = const CallMediaState();

  /// Per remote participant: their frames decrypt here (`true`), don't (`false`); absent
  /// until their decryptor says.
  final _decrypts = <String, bool>{};
  bool _localFailed = false;
  FrameCryptors? _cryptors;
  bool _closed = false;

  /// The LiveKit room while connected, for checks on a real call.
  @visibleForTesting
  lk.Room? get room => _room;

  @override
  CallMediaState get state => _state;

  @override
  Stream<CallMediaState> get states => Stream.multi((listener) {
    listener.add(_state);
    final subscription = _states.stream.listen(listener.add);
    listener.onCancel = subscription.cancel;
  });

  void _set(CallMediaState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  static Future<lk.BaseKeyProvider> _createKeyProvider() async {
    final options = rtc.KeyProviderOptions(
      sharedKey: false,
      ratchetSalt: utf8.encode(lk.defaultRatchetSalt),
      ratchetWindowSize: 10,
      uncryptedMagicBytes: utf8.encode(lk.defaultMagicBytes),
      keyRingSize: 256,
      // livekit-client's default (`DECRYPTION_FAILURE_TOLERANCE`): after 10 frames that
      // don't decrypt, the key counts as wrong and the state says so.
      failureTolerance: 10,
      keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
    );
    return lk.BaseKeyProvider(
      await rtc.frameCryptorFactory.createDefaultKeyProvider(options),
      options,
    );
  }

  @override
  Future<void> setKey(CallMediaKey key) => _keys.add(key);

  @override
  Future<void> connect({
    required String url,
    required String token,
    required bool camera,
  }) async {
    _set(_state.copyWith(connection: CallConnection.connecting));
    final provider = await _keyProvider;
    // Tracks published from here on encrypt with the latest own key.
    await _keys.applied;
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        encryption: lk.E2EEOptions(keyProvider: provider),
      ),
    );
    _room = room;
    // Ours instead of the one the room would make (see [FrameCryptors]).
    final cryptors = FrameCryptors(provider, onState: _onCryptorState);
    _cryptors = cryptors;
    await cryptors.setup(room);
    // The one way in (livekit_client 2.13.2, pinned): connect uses the engine's manager when
    // it has one, and makes its own otherwise.
    // ignore: invalid_use_of_internal_member
    room.engine.setE2eeManager(cryptors);
    final events = room.createListener();
    _events = events;
    events
      ..on<lk.RoomDisconnectedEvent>((event) {
        _set(
          _state.copyWith(
            connection: CallConnection.disconnected,
            error: event.reason?.name,
          ),
        );
      })
      ..on<lk.RoomReconnectingEvent>(
        (_) => _set(_state.copyWith(connection: CallConnection.reconnecting)),
      )
      ..on<lk.RoomReconnectedEvent>(
        (_) => _set(_state.copyWith(connection: CallConnection.connected)),
      )
      ..listen((_) => _refresh());
    try {
      await room.connect(url, token);
    } on Object {
      // A room that failed to connect isn't used again; a retry makes a new one.
      await events.dispose();
      await cryptors.close();
      await room.dispose();
      if (_room == room) {
        _room = null;
        _events = null;
        _cryptors = null;
      }
      rethrow;
    }
    appLog(
      LogLevel.info,
      'calls',
      'connected to $url as ${room.localParticipant?.identity}',
    );
    _set(
      _state.copyWith(
        connection: CallConnection.connected,
        serverVersion: room.serverVersion,
        serverRegion: room.serverRegion,
      ),
    );
    try {
      await _enable(lk.TrackSource.microphone);
    } on Object catch (error) {
      appLog(LogLevel.warn, 'calls', 'microphone: $error');
      _set(_state.copyWith(micOn: false, error: 'microphone'));
    }
    if (camera) await setCamera(true);
    _refresh();
  }

  void _onCryptorState(
    String identity,
    String sid,
    lk.E2EEState state, {
    required bool local,
  }) {
    appLog(
      LogLevel.info,
      'calls',
      'E2EE ${local ? 'encryptor' : 'decryptor'} $identity: ${state.name}',
    );
    if (state == lk.E2EEState.kNew || _closed) return;
    final ok = state == lk.E2EEState.kOk || state == lk.E2EEState.kKeyRatcheted;
    if (local) {
      _localFailed = !ok;
    } else {
      _decrypts[identity] = ok;
    }
    _refresh();
  }

  void _refresh() {
    final room = _room;
    if (room == null || _closed) return;
    CallTile tile(lk.Participant participant, {required bool local}) {
      final video = participant.videoTrackPublications
          .where((p) => p.source == lk.TrackSource.camera && !p.muted)
          .map((p) => p.track)
          .whereType<lk.VideoTrack>()
          .firstOrNull;
      return CallTile(
        identity: participant.identity,
        isLocal: local,
        hasVideo: video != null,
        micOn: participant.isMicrophoneEnabled(),
        speaking: participant.isSpeaking,
        video: video,
      );
    }

    final local = room.localParticipant;
    final remote = room.remoteParticipants.values.toList();
    _set(
      _state.copyWith(
        tiles: [
          if (local != null) tile(local, local: true),
          for (final participant in remote) tile(participant, local: false),
        ],
        micOn: local?.isMicrophoneEnabled() ?? _state.micOn,
        cameraOn: local?.isCameraEnabled() ?? _state.cameraOn,
        // Ours go out encrypted (a track without its key drops its frames), there is
        // someone else, and every other participant's media decrypts here.
        encrypted:
            _cryptors != null &&
            _keys.ownIndex != null &&
            !_localFailed &&
            remote.isNotEmpty &&
            remote.every((p) => _decrypts[p.identity] ?? false),
      ),
    );
  }

  /// Turns the microphone or camera on: unmutes its track, or publishes a new one so that
  /// its first frames don't go out in the clear. A track's encryptor can only be attached
  /// once the track is published (livekit_client's publish makes the sender), and until it
  /// runs frames pass through as they are. So a new track goes out muted (silence or black,
  /// and the SFU forwards nothing from a muted track) and unmutes once its encryptor runs.
  Future<void> _enable(lk.TrackSource source) async {
    final room = _room;
    final local = room?.localParticipant;
    if (room == null || local == null) return;
    if (room.e2eeManager == null ||
        local.getTrackPublicationBySource(source) != null) {
      await local.setSourceEnabled(source, true);
      return;
    }
    final lk.LocalTrack track = source == lk.TrackSource.camera
        ? await lk.LocalVideoTrack.createCameraTrack(
            room.roomOptions.defaultCameraCaptureOptions,
          )
        : await lk.LocalAudioTrack.create(
            room.roomOptions.defaultAudioCaptureOptions,
          );
    try {
      await track.mute(stopOnMute: false);
      final publication = switch (track) {
        final lk.LocalVideoTrack video => await local.publishVideoTrack(video),
        final lk.LocalAudioTrack audio => await local.publishAudioTrack(audio),
        _ => throw StateError('not a camera or microphone'),
      };
      await _untilEncrypting(publication.sid);
      await track.unmute(stopOnMute: false);
    } on Object {
      await track.stop();
      rethrow;
    }
  }

  /// Until the encryptor of the local track [sid] runs, or a few seconds at most.
  Future<void> _untilEncrypting(String sid) async {
    final cryptors = _cryptors;
    if (cryptors == null) return;
    await cryptors
        .encrypting(sid)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              appLog(LogLevel.warn, 'calls', 'no encryptor for $sid after 5 s'),
        );
  }

  @override
  Future<void> setMicrophone(bool on) async {
    if (on) {
      await _enable(lk.TrackSource.microphone);
    } else {
      await _room?.localParticipant?.setMicrophoneEnabled(false);
    }
    _set(_state.copyWith(micOn: on));
    _refresh();
  }

  @override
  Future<void> setCamera(bool on) async {
    try {
      if (on) {
        await _enable(lk.TrackSource.camera);
      } else {
        await _room?.localParticipant?.setCameraEnabled(false);
      }
      _set(_state.copyWith(cameraOn: on));
    } on Object catch (error) {
      appLog(LogLevel.warn, 'calls', 'camera: $error');
      _set(_state.copyWith(cameraOn: false, error: 'camera'));
    }
    _refresh();
  }

  @override
  Future<bool> canSwitchCamera() async =>
      (await lk.Hardware.instance.videoInputs()).length > 1;

  @override
  Future<void> switchCamera() async {
    final room = _room;
    if (room == null) return;
    final cameras = await lk.Hardware.instance.videoInputs();
    if (cameras.length < 2) return;
    final current = room.roomOptions.defaultCameraCaptureOptions.deviceId;
    final index = cameras.indexWhere((c) => c.deviceId == current);
    await room.setVideoInputDevice(cameras[(index + 1) % cameras.length]);
  }

  static bool get _phone => Platform.isAndroid || Platform.isIOS;

  @override
  Future<(List<AudioRoute>, AudioRoute?)> audioRoutes() async {
    if (_phone) {
      return (
        const [AudioRoute.earpiece, AudioRoute.speaker],
        lk.AudioManager.instance.isSpeakerOutputPreferred
            ? AudioRoute.speaker
            : AudioRoute.earpiece,
      );
    }
    final outputs = await lk.Hardware.instance.audioOutputs();
    final selected = lk.Hardware.instance.selectedAudioOutput;
    return (
      [for (final o in outputs) AudioRoute(o.deviceId, o.label)],
      selected == null ? null : AudioRoute(selected.deviceId, selected.label),
    );
  }

  @override
  Future<void> setAudioRoute(AudioRoute route) async {
    if (_phone) {
      await lk.AudioManager.instance.setSpeakerOutputPreferred(
        route == AudioRoute.speaker,
      );
      return;
    }
    final outputs = await lk.Hardware.instance.audioOutputs();
    final device = outputs.where((o) => o.deviceId == route.id).firstOrNull;
    if (device != null) await _room?.setAudioOutputDevice(device);
  }

  @override
  Widget videoView(CallTile tile, {BoxFit fit = BoxFit.cover}) {
    final track = tile.video;
    if (track is! lk.VideoTrack) return const SizedBox.shrink();
    return lk.VideoTrackRenderer(
      track,
      fit: fit == BoxFit.contain
          ? lk.VideoViewFit.contain
          : lk.VideoViewFit.cover,
      mirrorMode: tile.isLocal
          ? lk.VideoViewMirrorMode.mirror
          : lk.VideoViewMirrorMode.off,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _events?.dispose();
    final room = _room;
    _room = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
    await _cryptors?.close();
    _set(_state.copyWith(connection: CallConnection.disconnected));
    await _states.close();
  }
}

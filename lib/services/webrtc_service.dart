import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/call_models.dart';

/// Owns exactly one peer connection at a time.
///
/// The signalling half lives in `CallBloc` — this class knows nothing
/// about sockets or call state. It offers and answers, and reports what
/// the connection is doing. Keeping the two apart is what makes the call
/// state machine testable without a network.
class WebRtcService {
  WebRtcService();

  RTCPeerConnection? _peer;
  MediaStream? _localStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  /// Candidates that arrived before the remote description was set.
  ///
  /// This buffer is not optional. With trickle ICE the far end starts
  /// sending candidates the moment it creates its offer, which routinely
  /// beats our `setRemoteDescription`. `addCandidate` before that throws,
  /// and the dropped candidates are often the only ones that would have
  /// connected — the classic "works on wifi, fails on mobile" bug.
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;

  final StreamController<RTCIceCandidate> _localCandidateController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<RTCPeerConnectionState> _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final StreamController<bool> _remoteStreamController =
      StreamController<bool>.broadcast();

  /// Candidates we gathered — send each one over the socket as it arrives.
  Stream<RTCIceCandidate> get localCandidates =>
      _localCandidateController.stream;

  Stream<RTCPeerConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Fires true once remote media is attached to [remoteRenderer].
  Stream<bool> get remoteStreamArrived => _remoteStreamController.stream;

  bool get hasPeer => _peer != null;

  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerOn = true;
  bool _frontCamera = true;

  bool get isMicEnabled => _micEnabled;
  bool get isCameraEnabled => _cameraEnabled;
  bool get isSpeakerOn => _speakerOn;

  // -------------------------------------------------------------------------
  // Setup
  // -------------------------------------------------------------------------

  Future<void> initializeRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  /// Opens the camera/mic and builds the peer connection.
  ///
  /// Call this on **both** ends before any SDP is exchanged: the local
  /// tracks must be attached before `createOffer`, or the generated SDP
  /// advertises no media and the call connects to silence.
  Future<void> start({
    required bool withVideo,
    required IceServersConfig ice,
  }) async {
    await initializeRenderers();

    _localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
      // The mandatory/optional shape, not the flat WebRTC-spec one.
      //
      // flutter_webrtc's Android side parses audio constraints as legacy
      // libwebrtc `MediaConstraints`: a flat `{'echoCancellation': true}`
      // logs "mandatory constraints are not a map" and is DISCARDED —
      // getUserMedia then runs with no processing at all, which on
      // speakerphone means the other person hears themselves echo back.
      // The failure is a debug log, not an error, so it ships silently.
      // The goog-prefixed names are what that parser recognises.
      'audio': <String, dynamic>{
        'mandatory': <String, dynamic>{
          'googEchoCancellation': true,
          'googEchoCancellation2': true,
          'googNoiseSuppression': true,
          'googNoiseSuppression2': true,
          'googAutoGainControl': true,
          'googHighpassFilter': true,
        },
        'optional': <dynamic>[],
      },
      'video': withVideo
          ? <String, dynamic>{
              'facingMode': 'user',
              // A hint, not a demand — the platform picks the nearest
              // supported mode. Asking for more than this wastes uplink
              // on a stream rendered at phone size.
              'width': <String, dynamic>{'ideal': 1280},
              'height': <String, dynamic>{'ideal': 720},
              'frameRate': <String, dynamic>{'ideal': 30},
            }
          : false,
    });

    localRenderer.srcObject = _localStream;
    _cameraEnabled = withVideo;

    final RTCPeerConnection peer =
        await createPeerConnection(ice.toRtcConfiguration());

    // Unified plan: add each track individually rather than the stream.
    for (final MediaStreamTrack track in _localStream!.getTracks()) {
      await peer.addTrack(track, _localStream!);
    }

    peer.onIceCandidate = (RTCIceCandidate candidate) {
      // A null candidate string marks end-of-gathering; nothing to send.
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      if (!_localCandidateController.isClosed) {
        _localCandidateController.add(candidate);
      }
    };

    peer.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      remoteRenderer.srcObject = event.streams.first;
      if (!_remoteStreamController.isClosed) {
        _remoteStreamController.add(true);
      }
    };

    peer.onConnectionState = (RTCPeerConnectionState state) {
      developer.log('connection state: $state', name: 'webrtc');
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(state);
      }
    };

    peer.onIceConnectionState = (RTCIceConnectionState state) {
      developer.log('ice state: $state', name: 'webrtc');
    };

    _peer = peer;

    // Speakerphone on by default for video, earpiece for voice — matching
    // what every other calling app does.
    await setSpeaker(withVideo);
  }

  // -------------------------------------------------------------------------
  // Negotiation
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> createOffer() async {
    final RTCPeerConnection peer = _requirePeer();
    final RTCSessionDescription offer = await peer.createOffer(
      <String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      },
    );
    await peer.setLocalDescription(offer);
    return <String, dynamic>{'type': offer.type, 'sdp': offer.sdp};
  }

  Future<Map<String, dynamic>> createAnswer() async {
    final RTCPeerConnection peer = _requirePeer();
    final RTCSessionDescription answer = await peer.createAnswer();
    await peer.setLocalDescription(answer);
    return <String, dynamic>{'type': answer.type, 'sdp': answer.sdp};
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    final RTCPeerConnection peer = _requirePeer();
    await peer.setRemoteDescription(
      RTCSessionDescription(
        (sdp['sdp'] ?? '') as String,
        (sdp['type'] ?? '') as String,
      ),
    );
    _remoteDescriptionSet = true;

    // Drain into a copy first: hangUp() clears this list, and a hang-up
    // landing while the loop is suspended on an await would otherwise
    // throw ConcurrentModificationError and abandon the rest.
    final List<RTCIceCandidate> pending =
        List<RTCIceCandidate>.of(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();

    for (final RTCIceCandidate candidate in pending) {
      try {
        await peer.addCandidate(candidate);
      } catch (error) {
        developer.log('buffered candidate rejected: $error', name: 'webrtc');
      }
    }
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> json) async {
    final RTCIceCandidate candidate = RTCIceCandidate(
      (json['candidate'] ?? '') as String?,
      json['sdpMid'] as String?,
      (json['sdpMLineIndex'] as num?)?.toInt(),
    );

    final RTCPeerConnection? peer = _peer;
    if (peer == null || !_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }

    try {
      await peer.addCandidate(candidate);
    } catch (error) {
      developer.log('candidate rejected: $error', name: 'webrtc');
    }
  }

  static Map<String, dynamic> candidateToJson(RTCIceCandidate candidate) {
    return <String, dynamic>{
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    };
  }

  // -------------------------------------------------------------------------
  // In-call controls
  // -------------------------------------------------------------------------

  /// Mutes by disabling the track rather than removing it.
  ///
  /// Removing a track forces renegotiation and can drop the connection;
  /// disabling keeps the stream alive and sends silence, which is what
  /// every calling app actually does.
  Future<void> setMicEnabled(bool enabled) async {
    _micEnabled = enabled;
    for (final MediaStreamTrack track in _localStream?.getAudioTracks() ??
        <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    _cameraEnabled = enabled;
    for (final MediaStreamTrack track in _localStream?.getVideoTracks() ??
        <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final List<MediaStreamTrack> videoTracks =
        _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
    _frontCamera = !_frontCamera;
  }

  bool get isFrontCamera => _frontCamera;

  Future<void> setSpeaker(bool on) async {
    _speakerOn = on;
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (error) {
      // Not fatal — some emulators have no audio routing at all.
      developer.log('speaker toggle failed: $error', name: 'webrtc');
    }
  }

  // -------------------------------------------------------------------------
  // Teardown
  // -------------------------------------------------------------------------

  /// Releases the camera, mic and connection.
  ///
  /// Must run on every exit path. A missed teardown leaves the camera LED
  /// on and the mic hot after the call screen has closed — the single most
  /// alarming bug a calling feature can ship with.
  Future<void> hangUp() async {
    try {
      for (final MediaStreamTrack track in _localStream?.getTracks() ??
          <MediaStreamTrack>[]) {
        await track.stop();
      }
      await _localStream?.dispose();
    } catch (error) {
      developer.log('stream teardown: $error', name: 'webrtc');
    }
    _localStream = null;

    try {
      await _peer?.close();
    } catch (error) {
      developer.log('peer close: $error', name: 'webrtc');
    }
    _peer = null;

    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    // Guarded: RTCVideoRenderer.srcObject throws when the renderer has no
    // texture yet, even when assigning null. Declining a call or a failed
    // invite reaches here without ever having called start(), and an
    // exception on this path would strand the call state as "ringing".
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
  }

  Future<void> dispose() async {
    await hangUp();
    if (_renderersReady) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      _renderersReady = false;
    }
    await _localCandidateController.close();
    await _connectionStateController.close();
    await _remoteStreamController.close();
  }

  RTCPeerConnection _requirePeer() {
    final RTCPeerConnection? peer = _peer;
    if (peer == null) {
      throw StateError('No peer connection — call start() first.');
    }
    return peer;
  }
}

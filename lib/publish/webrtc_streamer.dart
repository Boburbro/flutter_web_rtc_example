import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';

class WebRTCStreamLogic {
  late RTCPeerConnection _peerConnection;
  MediaStream? _mediaStream;
  final RTCVideoRenderer renderer;
  IOWebSocketChannel? _channel;
  bool _isMicOn = true;

  WebRTCStreamLogic(this.renderer);

  Future<void> initCamera() async {
    await renderer.initialize();
    await _getMedia();
  }

  Future<void> _getMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': {
        'facingMode': "user",
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30},
      },
    };
    _mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
    renderer.srcObject = _mediaStream;
  }

  Future<void> startStreaming({
    required String wsUrl,
    required Map<String, String> turnCredentials,
    required String appName,
    required String streamName,
  }) async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': [
            'turn:${turnCredentials['host']}:3478?transport=udp',
            'turn:${turnCredentials['host']}:3478?transport=tcp',
            'turns:${turnCredentials['host']}:5349?transport=tcp',
          ],
          'username': turnCredentials['username'],
          'credential': turnCredentials['credential'],
        },
      ],
    });

    // ICE candidate handler
    _peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        final payload = {
          'direction': 'publish',
          'command': 'sendCandidate',
          'streamInfo': {
            'applicationName': appName,
            'streamName': streamName,
            'sessionId': '[empty]',
          },
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        };
        _channel?.sink.add(jsonEncode(payload));
      }
    };

    // add tracks
    _mediaStream?.getTracks().forEach((track) {
      _peerConnection.addTrack(track, _mediaStream!);
    });

    // create offer
    final offer = await _peerConnection.createOffer();
    await _peerConnection.setLocalDescription(offer);

    // open signaling
    _channel = IOWebSocketChannel.connect(wsUrl);
    _channel!.stream.listen(_handleSignal, onError: (e) {}, onDone: () {});

    // send offer
    final offerPayload = {
      'direction': 'publish',
      'command': 'sendOffer',
      'streamInfo': {
        'applicationName': appName,
        'streamName': streamName,
        'sessionId': '[empty]',
      },
      'sdp': {'type': 'offer', 'sdp': offer.sdp},
    };
    _channel!.sink.add(jsonEncode(offerPayload));
  }

  void _handleSignal(dynamic message) async {
    final data = jsonDecode(message);
    if (data['sdp'] != null) {
      final sdp = data['sdp'];
      await _peerConnection.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
    }
    if (data['iceCandidates'] != null) {
      for (var c in data['iceCandidates']) {
        final ice = RTCIceCandidate(
          c['candidate'],
          c['sdpMid'],
          c['sdpMLineIndex'],
        );
        await _peerConnection.addCandidate(ice);
      }
    }
  }

  Future<void> stopStreaming() async {
    await _peerConnection.close();
    await _channel?.sink.close();
  }

  void toggleMic() {
    if (_mediaStream == null) return;
    for (var track in _mediaStream!.getAudioTracks()) {
      track.enabled = !_isMicOn;
    }
    _isMicOn = !_isMicOn;
  }

  Future<void> toggleCamera() async {
    if (_mediaStream == null) return;
    for (var track in _mediaStream!.getTracks()) {
      try {
        await Helper.switchCamera(track);
      } catch (e) {
        print(e);
      }
    }
  }
}

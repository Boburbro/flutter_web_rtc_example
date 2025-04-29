import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebRTCPlayer extends StatefulWidget {
  const WebRTCPlayer({super.key});

  @override
  State<WebRTCPlayer> createState() => _WebRTCPlayerState();
}

class _WebRTCPlayerState extends State<WebRTCPlayer> {
  RTCPeerConnection? _peerConnection;
  final _remoteRenderer = RTCVideoRenderer();
  WebSocketChannel? _socket;
  bool _isConnected = false;
  String _connectionStatus = "Connecting...";

  String? _sessionId;

  final String wsUrl =
      'wss://6806228b75ff3.streamlock.net:8443/webrtc-session.json';
  final String appName = 'live';
  final String streamName =
      'user-998903644135-edf160b9-5b8c-4116-84a8-e81777dbe3bb';

  final Map<String, dynamic> rtcConfig = {
    'iceServers': [
      {
        'urls': 'turn:turn.bozormedia.uz',
        'username': 'webrtc',
        'credential': 'securepassword123',
      },
      {
        'urls': 'stun:stun.l.google.com:19302', // fallback stun server
      },
    ],
    // Force using TCP to avoid UDP blocking issues
    'iceTransportPolicy': 'all',
  };

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _connect();
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _connectionStatus = status;
      });
      print(status);
    }
  }

  Future<void> _connect() async {
    try {
      _updateStatus("Initializing peer connection...");

      // Create peer connection with proper media constraints
      _peerConnection = await createPeerConnection(rtcConfig, {
        'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
        'optional': [],
      });

      // Set up event handlers
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        // Send ICE candidate to server
        if (_socket != null && _sessionId != null) {
          _socket!.sink.add(
            jsonEncode({
              'direction': 'play',
              'command': 'addIceCandidate',
              'streamInfo': {
                'applicationName': appName,
                'streamName': streamName,
                'sessionId': _sessionId,
              },
              'candidate': {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              },
            }),
          );
        }
      };

      _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
        _updateStatus("ICE Connection State: ${state.toString()}");
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          setState(() {
            _isConnected = true;
          });
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          setState(() {
            _isConnected = false;
          });
          // Consider reconnecting here
        }
      };

      _peerConnection?.onTrack = (RTCTrackEvent event) {
        _updateStatus("Received track: ${event.track.kind}");
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
          });
        }
      };

      // Connect to WebSocket
      _updateStatus("Connecting to WebSocket...");
      _connectWebSocket();
    } catch (e) {
      _updateStatus("Connection error: $e");
    }
  }

  void _connectWebSocket() {
    try {
      _socket = WebSocketChannel.connect(Uri.parse(wsUrl));
      _updateStatus("WebSocket connected, sending play request...");

      _socket!.stream.listen(
        (message) async {
          try {
            final data = jsonDecode(message);
            _processSocketMessage(data);
          } catch (e) {
            _updateStatus("Error processing message: $e");
          }
        },
        onError: (error) {
          _updateStatus("WebSocket error: $error");
        },
        onDone: () {
          _updateStatus("WebSocket connection closed");
          // Consider reconnecting here
        },
      );

      // Send initial play request
      _sendPlayRequest();
    } catch (e) {
      _updateStatus("WebSocket connection error: $e");
    }
  }

  void _sendPlayRequest() {
    if (_socket == null) return;

    final playRequest = {
      'direction': 'play',
      'command': 'getOffer',
      'streamInfo': {
        'applicationName': appName,
        'streamName': streamName,
        'sessionId': '[empty]',
      },
      'userData': {"param1": "value1"},
    };

    _socket!.sink.add(jsonEncode(playRequest));
    _updateStatus("Play request sent");
  }

  Future<void> _processSocketMessage(Map<String, dynamic> data) async {
    // Log the data for debugging
    print("Received: ${jsonEncode(data)}");

    // Handle session ID
    if (data['streamInfo'] != null && data['streamInfo']['sessionId'] != null) {
      _sessionId = data['streamInfo']['sessionId'];
      _updateStatus("Session ID received: $_sessionId");
    }

    // Handle SDP
    if (data['sdp'] != null) {
      final sdpMap = data['sdp'];
      final sdpType = sdpMap['type'];
      final sdpString = sdpMap['sdp'];

      _updateStatus("Received SDP: $sdpType");

      try {
        final desc = RTCSessionDescription(sdpString, sdpType);

        if (sdpType == 'offer') {
          await _peerConnection!.setRemoteDescription(desc);
          _updateStatus("Remote description set, creating answer...");

          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          _updateStatus("Local description set, sending answer...");

          _socket!.sink.add(
            jsonEncode({
              'direction': 'play',
              'command': 'sendResponse',
              'streamInfo': {
                'applicationName': appName,
                'streamName': streamName,
                'sessionId': _sessionId,
              },
              'sdp': {'type': answer.type, 'sdp': answer.sdp},
            }),
          );
        } else if (sdpType == 'answer') {
          await _peerConnection!.setRemoteDescription(desc);
          _updateStatus("Remote answer set");
        }
      } catch (e) {
        _updateStatus("SDP handling error: $e");
      }
    }

    // Handle ICE candidates
    if (data['iceCandidates'] != null) {
      final candidates = data['iceCandidates'] as List;
      for (var c in candidates) {
        _updateStatus("Adding remote ICE candidate");
        await _peerConnection!.addCandidate(
          RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
        );
      }
    } else if (data['iceCandidate'] != null) {
      final c = data['iceCandidate'];
      _updateStatus("Adding single remote ICE candidate");
      await _peerConnection!.addCandidate(
        RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
      );
    }
  }

  void _reconnect() {
    _dispose();
    _initRenderer();
    _connect();
  }

  void _dispose() {
    _socket?.sink.close();
    _socket = null;
    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;
    _sessionId = null;
  }

  @override
  void dispose() {
    _dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC Player')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _connectionStatus,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child:
                _isConnected
                    ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      filterQuality: FilterQuality.none,
                    )
                    : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _reconnect,
                            child: const Text('Qayta ulanish'),
                          ),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

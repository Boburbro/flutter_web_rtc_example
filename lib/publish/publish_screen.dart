import 'package:flutter/material.dart';
import 'package:flutter_web_rtc_example/publish/webrtc_streamer.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  late WebRTCStreamLogic _logic;
  bool isStreaming = false;

  @override
  void initState() {
    super.initState();
    _logic = WebRTCStreamLogic(_localRenderer);
    _logic.initCamera().then((_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("📡 Stream boshqaruv")),
      body: Stack(
        children: [
          RTCVideoView(
            _localRenderer,

            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            filterQuality: FilterQuality.none,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: isStreaming ? _stopStream : _startStream,
                  child: Text(isStreaming ? "⛔️ Stop" : "▶️ Start"),
                ),
                // ElevatedButton(
                //   onPressed: () {
                //     setState(() {
                //       _logic.toggleMic();
                //     });
                //   },
                //   child: const Text("🎤 Mic On/Off"),
                // ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _logic.toggleCamera();
                    });
                  },
                  child: const Text("Switch kamera"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startStream() async {
    await _logic.startStreaming(
      wsUrl: 'wss://6806228b75ff3.streamlock.net:8443/webrtc-session.json',
      turnCredentials: {
        'host': 'turn.bozormedia.uz',
        'username': 'webrtc',
        'credential': 'securepassword123',
      },
      appName: 'live',
      streamName: 'user-998903644135-edf160b9-5b8c-4116-84a8-e81777dbe3bb',
    );
    setState(() => isStreaming = true);
  }

  Future<void> _stopStream() async {
    await _logic.stopStreaming();
    setState(() => isStreaming = false);
  }
}

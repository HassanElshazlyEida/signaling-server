import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// Point this at your deployed signaling server's base URL (no path).
const String signalingServerUrl = 'https://karim.imockup.top';

// Must match the `path` the server's Socket.IO instance was configured
// with. Using Socket.IO instead of a raw WebSocket lets the client
// automatically fall back to HTTP long-polling when a reverse proxy (like
// the one in front of this server) blocks the WebSocket Upgrade handshake
// — it still tries a real WebSocket first, and upgrades to it silently if
// the network path ever allows one.
const String signalingSocketPath = '/socket/socket.io/';

void main() {
  runApp(const VoiceCallApp());
}

class VoiceCallApp extends StatelessWidget {
  const VoiceCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Call',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const CallScreen(),
    );
  }
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final String myId;
  final TextEditingController _targetIdController = TextEditingController();

  io.Socket? _socket;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  String _status = 'Not connected';
  String? _remoteId; // id of the user we are currently in a call with
  bool _inCall = false;
  bool _muted = false;

  final _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      // For production, add a TURN server here too, e.g.:
      // {
      //   'urls': 'turn:your.turn.server:3478',
      //   'username': 'user',
      //   'credential': 'pass',
      // },
    ]
  };

  @override
  void initState() {
    super.initState();
    myId = _generateId();
    _connectSignaling();
  }

  String _generateId() {
    final rnd = Random();
    return (100000 + rnd.nextInt(899999)).toString(); // 6-digit id
  }

  void _connectSignaling() {
    setState(() => _status = 'Connecting to server...');

    _socket = io.io(
      signalingServerUrl,
      io.OptionBuilder()
          .setPath(signalingSocketPath)
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      _send({'type': 'register', 'id': myId});
    });

    _socket!.on('signal', (data) {
      _onSignalingMessage(Map<String, dynamic>.from(data as Map));
    });

    _socket!.onDisconnect((_) => setState(() => _status = 'Disconnected from server'));
    _socket!.onConnectError((e) => setState(() => _status = 'Connection error: $e'));
    _socket!.onError((e) => setState(() => _status = 'Connection error: $e'));
  }

  void _send(Map<String, dynamic> data) {
    _socket?.emit('signal', data);
  }

  Future<void> _onSignalingMessage(Map<String, dynamic> msg) async {
    switch (msg['type']) {
      case 'registered':
        setState(() => _status = 'Online. Your ID: $myId');
        break;

      case 'offer':
        _remoteId = msg['from'];
        await _ensurePeerConnection();
        await _pc!.setRemoteDescription(
          RTCSessionDescription(msg['sdp'], 'offer'),
        );
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _send({
          'type': 'answer',
          'target': _remoteId,
          'sdp': answer.sdp,
        });
        setState(() {
          _inCall = true;
          _status = 'In call with $_remoteId';
        });
        break;

      case 'answer':
        await _pc!.setRemoteDescription(
          RTCSessionDescription(msg['sdp'], 'answer'),
        );
        setState(() {
          _inCall = true;
          _status = 'In call with $_remoteId';
        });
        break;

      case 'candidate':
        if (msg['candidate'] != null) {
          await _pc?.addCandidate(RTCIceCandidate(
            msg['candidate']['candidate'],
            msg['candidate']['sdpMid'],
            msg['candidate']['sdpMLineIndex'],
          ));
        }
        break;

      case 'hangup':
        _endCall(notifyRemote: false);
        break;

      case 'error':
        setState(() => _status = 'Error: ${msg['message']}');
        break;
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;

    await Permission.microphone.request();

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    _pc = await createPeerConnection(_iceServers);

    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _pc!.onIceCandidate = (candidate) {
      if (_remoteId == null) return;
      _send({
        'type': 'candidate',
        'target': _remoteId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _endCall(notifyRemote: false);
      }
    };
  }

  Future<void> _callUser() async {
    final target = _targetIdController.text.trim();
    if (target.isEmpty) return;

    _remoteId = target;
    await _ensurePeerConnection();

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    _send({
      'type': 'offer',
      'target': target,
      'sdp': offer.sdp,
    });

    setState(() => _status = 'Calling $target...');
  }

  void _endCall({bool notifyRemote = true}) {
    if (notifyRemote && _remoteId != null) {
      _send({'type': 'hangup', 'target': _remoteId});
    }
    _pc?.close();
    _pc = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    setState(() {
      _inCall = false;
      _remoteId = null;
      _status = 'Online. Your ID: $myId';
    });
  }

  void _toggleMute() {
    if (_localStream == null) return;
    _muted = !_muted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_muted;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _endCall(notifyRemote: true);
    _socket?.disconnect();
    _socket?.dispose();
    _targetIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Call')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Your ID (share this with the other person)'),
                    const SizedBox(height: 8),
                    SelectableText(
                      myId,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (!_inCall) ...[
              TextField(
                controller: _targetIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Enter ID to call',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _callUser,
                icon: const Icon(Icons.call),
                label: const Text('Call'),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 48,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    onPressed: _toggleMute,
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    iconSize: 48,
                    color: Colors.red,
                    icon: const Icon(Icons.call_end),
                    onPressed: () => _endCall(notifyRemote: true),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

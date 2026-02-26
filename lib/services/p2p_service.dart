import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path_provider/path_provider.dart';

/// Message types for the P2P protocol
enum P2PMessageType {
  classroomInfo,
  joinRequest,
  joinAccepted,
  joinRejected,
  newPost,
  syncAllPosts,
  newAssignment,
  syncAssignments,
  turnInSubmission,
  submissionReceived,
  returnSubmission,
  syncReturnedSubmissions,
  fileMetadata, // sent before a file payload to tell the receiver what to expect
  requestFiles, // sent by student to request specific missing file attachments
}

/// A structured message sent over P2P
class P2PMessage {
  final P2PMessageType type;
  final Map<String, dynamic> data;

  P2PMessage({required this.type, required this.data});

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'data': data,
      };

  factory P2PMessage.fromJson(Map<String, dynamic> json) {
    return P2PMessage(
      type: P2PMessageType.values.firstWhere((e) => e.name == json['type']),
      data: Map<String, dynamic>.from(json['data'] as Map),
    );
  }

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory P2PMessage.fromBytes(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return P2PMessage.fromJson(json);
  }
}

/// Callbacks for P2P events
typedef OnEndpointFound = void Function(
    String endpointId, String endpointName, String serviceId);
typedef OnEndpointLost = void Function(String endpointId);
typedef OnConnectionInitiated = void Function(
    String endpointId, ConnectionInfo info);
typedef OnConnectionResult = void Function(String endpointId, Status status);
typedef OnDisconnected = void Function(String endpointId);
typedef OnMessageReceived = void Function(
    String endpointId, P2PMessage message);
typedef OnFileReceived = void Function(
    String endpointId, int payloadId, String tempFilePath);
typedef OnFileTransferUpdate = void Function(
    String endpointId, int payloadId, int bytesTransferred, int totalBytes);

class P2PService {
  static const String serviceId = 'com.p2pclassroom.p2p';
  static const Strategy strategy = Strategy.P2P_STAR;

  final Nearby _nearby = Nearby();

  // Callbacks
  OnEndpointFound? onEndpointFound;
  OnEndpointLost? onEndpointLost;
  OnConnectionInitiated? onConnectionInitiated;
  OnConnectionResult? onConnectionResult;
  OnDisconnected? onDisconnected;
  OnMessageReceived? onMessageReceived;
  OnFileReceived? onFileReceived;
  OnFileTransferUpdate? onFileTransferUpdate;

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  // Track pending file payloads by payloadId
  final Map<int, String> _pendingFilePayloads = {};

  bool get isAdvertising => _isAdvertising;
  bool get isDiscovering => _isDiscovering;

  /// ─── Teacher: Start advertising (making self discoverable) ───
  Future<bool> startAdvertising(String userName) async {
    try {
      final result = await _nearby.startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: (String id, ConnectionInfo info) {
          debugPrint('[P2P] Connection initiated from: ${info.endpointName}');
          onConnectionInitiated?.call(id, info);
        },
        onConnectionResult: (String id, Status status) {
          debugPrint('[P2P] Connection result: $id -> ${status.name}');
          onConnectionResult?.call(id, status);
        },
        onDisconnected: (String id) {
          debugPrint('[P2P] Disconnected: $id');
          onDisconnected?.call(id);
        },
        serviceId: serviceId,
      );
      _isAdvertising = result;
      debugPrint('[P2P] Advertising started: $result');
      return result;
    } catch (e) {
      debugPrint('[P2P] Error starting advertising: $e');
      return false;
    }
  }

  /// ─── Student: Start discovering nearby teachers ───
  Future<bool> startDiscovery(String userName) async {
    try {
      final result = await _nearby.startDiscovery(
        userName,
        strategy,
        onEndpointFound: (String id, String name, String sid) {
          debugPrint('[P2P] Found endpoint: $name ($id)');
          onEndpointFound?.call(id, name, sid);
        },
        onEndpointLost: (String? id) {
          if (id != null) {
            debugPrint('[P2P] Lost endpoint: $id');
            onEndpointLost?.call(id);
          }
        },
        serviceId: serviceId,
      );
      _isDiscovering = result;
      debugPrint('[P2P] Discovery started: $result');
      return result;
    } catch (e) {
      debugPrint('[P2P] Error starting discovery: $e');
      return false;
    }
  }

  /// ─── Student: Request connection to a teacher ───
  Future<bool> requestConnection(
      String userName, String endpointId) async {
    try {
      await _nearby.requestConnection(
        userName,
        endpointId,
        onConnectionInitiated: (String id, ConnectionInfo info) {
          debugPrint('[P2P] Connection initiated to: ${info.endpointName}');
          onConnectionInitiated?.call(id, info);
        },
        onConnectionResult: (String id, Status status) {
          debugPrint('[P2P] Connection result: $id -> ${status.name}');
          onConnectionResult?.call(id, status);
        },
        onDisconnected: (String id) {
          debugPrint('[P2P] Disconnected: $id');
          onDisconnected?.call(id);
        },
      );
      return true;
    } catch (e) {
      debugPrint('[P2P] Error requesting connection: $e');
      return false;
    }
  }

  /// ─── Accept a connection (both teacher and student call this) ───
  Future<void> acceptConnection(String endpointId) async {
    try {
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (String id, Payload payload) {
          if (payload.type == PayloadType.BYTES && payload.bytes != null) {
            try {
              final message = P2PMessage.fromBytes(payload.bytes!);
              debugPrint('[P2P] Message received from $id: ${message.type.name}');
              onMessageReceived?.call(id, message);
            } catch (e) {
              debugPrint('[P2P] Error parsing message: $e');
            }
          } else if (payload.type == PayloadType.FILE) {
            // File payload received — track it
            debugPrint('[P2P] File payload started from $id, payloadId: ${payload.id}');
            if (payload.uri != null) {
              _pendingFilePayloads[payload.id!] = payload.uri!;
            }
          }
        },
        onPayloadTransferUpdate: (String id, PayloadTransferUpdate update) {
          final payloadId = update.id;
          final bytesTransferred = update.bytesTransferred;
          final totalBytes = update.totalBytes;

          // Report progress for file transfers
          if (_pendingFilePayloads.containsKey(payloadId)) {
            onFileTransferUpdate?.call(
                id, payloadId, bytesTransferred, totalBytes);

            if (update.status == PayloadStatus.SUCCESS) {
              debugPrint('[P2P] File transfer complete, payloadId: $payloadId');
              final tempPath = _pendingFilePayloads.remove(payloadId);
              if (tempPath != null) {
                onFileReceived?.call(id, payloadId, tempPath);
              }
            } else if (update.status == PayloadStatus.FAILURE) {
              debugPrint('[P2P] File transfer failed, payloadId: $payloadId');
              _pendingFilePayloads.remove(payloadId);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('[P2P] Error accepting connection: $e');
    }
  }

  /// ─── Reject a connection ───
  Future<void> rejectConnection(String endpointId) async {
    try {
      await _nearby.rejectConnection(endpointId);
    } catch (e) {
      debugPrint('[P2P] Error rejecting connection: $e');
    }
  }

  /// ─── Send a message to a specific endpoint ───
  Future<void> sendMessage(String endpointId, P2PMessage message) async {
    try {
      await _nearby.sendBytesPayload(endpointId, message.toBytes());
      debugPrint('[P2P] Sent ${message.type.name} to $endpointId');
    } catch (e) {
      debugPrint('[P2P] Error sending message to $endpointId: $e');
    }
  }

  /// ─── Send a message to multiple endpoints ───
  Future<void> broadcastMessage(
      List<String> endpointIds, P2PMessage message) async {
    for (final id in endpointIds) {
      await sendMessage(id, message);
    }
  }

  /// ─── Send a file to a specific endpoint ───
  Future<int?> sendFilePayload(String endpointId, String filePath) async {
    try {
      final payloadId = await _nearby.sendFilePayload(endpointId, filePath);
      debugPrint('[P2P] Sent file payload to $endpointId, payloadId: $payloadId');
      return payloadId;
    } catch (e) {
      debugPrint('[P2P] Error sending file to $endpointId: $e');
      return null;
    }
  }

  /// ─── Send a file to multiple endpoints ───
  Future<void> broadcastFile(
      List<String> endpointIds, String filePath) async {
    for (final id in endpointIds) {
      await sendFilePayload(id, filePath);
    }
  }

  /// ─── Get app storage directory for received files ───
  /// Uses external storage so files can be opened by other apps via open_filex
  static Future<String> getReceivedFilesDir() async {
    // Try external storage first (accessible by other apps)
    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      final receivedDir = Directory('${extDir.path}/received_files');
      if (!await receivedDir.exists()) {
        await receivedDir.create(recursive: true);
      }
      return receivedDir.path;
    }
    // Fallback to internal storage
    final appDir = await getApplicationDocumentsDirectory();
    final receivedDir = Directory('${appDir.path}/received_files');
    if (!await receivedDir.exists()) {
      await receivedDir.create(recursive: true);
    }
    return receivedDir.path;
  }

  /// ─── Stop advertising ───
  Future<void> stopAdvertising() async {
    await _nearby.stopAdvertising();
    _isAdvertising = false;
    debugPrint('[P2P] Advertising stopped');
  }

  /// ─── Stop discovery ───
  Future<void> stopDiscovery() async {
    await _nearby.stopDiscovery();
    _isDiscovering = false;
    debugPrint('[P2P] Discovery stopped');
  }

  /// ─── Disconnect from a specific endpoint ───
  Future<void> disconnectFromEndpoint(String endpointId) async {
    await _nearby.disconnectFromEndpoint(endpointId);
  }

  /// ─── Stop all connections and cleanup ───
  Future<void> stopAll() async {
    await _nearby.stopAllEndpoints();
    await stopAdvertising();
    await stopDiscovery();
    _isAdvertising = false;
    _isDiscovering = false;
    _pendingFilePayloads.clear();
    debugPrint('[P2P] All connections stopped');
  }
}

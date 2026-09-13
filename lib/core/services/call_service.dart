// 文件用途：封装 CallState 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：协调呼叫信令、Agora/LiveKit 会话、权限和音视频状态，在重连、降级和结束时同步本地与服务端状态。
import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../i18n/app_localizations.dart';
import '../i18n/server_message_localizer.dart';
import 'api/api_client.dart';
import 'api/auth_service.dart';
import 'api/system_settings_service.dart';
import 'api/websocket_service.dart';
import 'android_callkit_helper.dart';
import 'call_end_tone_service.dart';
import 'call_terminal_outbox.dart';
import 'desktop_notification_service.dart';
import 'device_service.dart';
import 'media_permission_policy.dart';
import 'incoming_call_tone_service.dart';
import 'outgoing_call_tone_service.dart';

String _callServiceText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String _genericCallFailureText() => _callServiceText(
      zhCN: '\u901a\u8bdd\u5931\u8d25\uff0c\u8bf7\u91cd\u8bd5',
      zhTW: '\u901a\u8a71\u5931\u6557\uff0c\u8acb\u91cd\u8a66',
      en: 'Call failed. Please try again.',
    );

String _callServerMessage(String? raw, {required String fallbackEn}) {
  return localizeServerMessage(raw, fallbackEn: fallbackEn);
}

String _blockedCallText() => _callServiceText(
      zhCN:
          '\u5df2\u5c4f\u853d\u8be5\u7528\u6237\uff0c\u65e0\u6cd5\u53d1\u8d77\u901a\u8bdd',
      zhTW:
          '\u5df2\u5c01\u9396\u8a72\u7528\u6236\uff0c\u7121\u6cd5\u767c\u8d77\u901a\u8a71',
      en: 'This user is blocked. Unable to start a call.',
    );

String _mediaServiceUnavailableText() => _callServiceText(
      zhCN: '\u97f3\u89c6\u9891\u670d\u52a1\u672a\u542f\u7528',
      zhTW: '\u97f3\u8a0a\u8207\u8996\u8a0a\u670d\u52d9\u672a\u555f\u7528',
      en: 'Audio and video service is not enabled',
    );

String _callConnectionNotReadyText() => _callServiceText(
      zhCN:
          '\u901a\u8bdd\u8fde\u63a5\u672a\u5c31\u7eea\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5',
      zhTW:
          '\u901a\u8a71\u9023\u7dda\u672a\u5c31\u7dd2\uff0c\u8acb\u7a0d\u5f8c\u91cd\u8a66',
      en: 'Call connection is not ready. Please try again later.',
    );

String _callAlreadyInProgressText() => _callServiceText(
      zhCN: '\u5df2\u5728\u901a\u8bdd\u4e2d',
      zhTW: '\u5df2\u5728\u901a\u8a71\u4e2d',
      en: 'A call is already in progress.',
    );

String _callActionText(String actionKey) {
  switch (actionKey) {
    case 'answer':
      return _callServiceText(
        zhCN: '\u63a5\u542c',
        zhTW: '\u63a5\u807d',
        en: 'Answer',
      );
    case 'decline':
      return _callServiceText(
        zhCN: '\u62d2\u7edd',
        zhTW: '\u62d2\u7d55',
        en: 'Decline',
      );
    case 'call':
    default:
      return _callServiceText(
        zhCN: '\u901a\u8bdd',
        zhTW: '\u901a\u8a71',
        en: 'Call',
      );
  }
}

// 关键声明：call service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
enum CallState {
  idle,
  preparing,
  outgoing,
  incoming,
  connecting,
  connected,
  reconnecting,
  failed,
  ended,
}

enum CallType { voice, video }

enum CallPermissionIssue {
  microphoneDenied,
  microphonePermanentlyDenied,
  cameraDenied,
  cameraPermanentlyDenied,
}

bool callPermissionSupportsVoiceFallback(CallPermissionIssue? issue) {
  return issue == CallPermissionIssue.cameraDenied ||
      issue == CallPermissionIssue.cameraPermanentlyDenied;
}

bool callPermissionCanOpenSettings(CallPermissionIssue? issue) {
  return issue == CallPermissionIssue.microphonePermanentlyDenied ||
      issue == CallPermissionIssue.cameraPermanentlyDenied;
}

int callReconnectSecondsRemaining(DateTime deadline, DateTime now) {
  final milliseconds = deadline.difference(now).inMilliseconds;
  if (milliseconds <= 0) return 0;
  return (milliseconds / Duration.millisecondsPerSecond).ceil();
}

int callElapsedSeconds(DateTime? connectedAt, DateTime now) {
  if (connectedAt == null) return 0;
  final seconds = now.difference(connectedAt).inSeconds;
  return seconds < 0 ? 0 : seconds;
}

Duration estimateServerClockOffset({
  required DateTime serverTime,
  required DateTime localRequestStarted,
  required DateTime localResponseReceived,
}) {
  final roundTrip = localResponseReceived.difference(localRequestStarted);
  final midpoint = localRequestStarted.add(
    Duration(microseconds: roundTrip.inMicroseconds ~/ 2),
  );
  return serverTime.difference(midpoint);
}

int callElapsedSecondsWithClockOffset(
  DateTime? connectedAt,
  DateTime localNow,
  Duration serverClockOffset,
) {
  return callElapsedSeconds(connectedAt, localNow.add(serverClockOffset));
}

bool incomingCallIsExpired(String? rawExpiresAt, DateTime now) {
  return incomingCallExpiryPassed(rawExpiresAt, now);
}

bool serverConfirmsExistingCallBeforeBusy({
  required int? localCallId,
  required int? incomingCallId,
  required bool serverActive,
  required int? serverCallId,
}) {
  return serverActive &&
      localCallId != null &&
      serverCallId == localCallId &&
      serverCallId != incomingCallId;
}

/// Terminal and acceptance events are safe only when they identify the exact
/// server-side call. Treating a missing id as a wildcard lets a delayed event
/// from the previous call terminate a rapid redial attempt.
bool callEventMatchesCurrentCall({
  required int? currentCallId,
  required int? eventCallId,
  String? currentSessionId,
  String? eventSessionId,
  int currentRevision = 0,
  int? eventRevision,
}) {
  final callIdMatches = currentCallId != null &&
      currentCallId > 0 &&
      eventCallId != null &&
      eventCallId > 0 &&
      currentCallId == eventCallId;
  if (!callIdMatches) return false;

  final normalizedCurrentSession = currentSessionId?.trim() ?? '';
  final normalizedEventSession = eventSessionId?.trim() ?? '';
  if (normalizedCurrentSession.isNotEmpty &&
      normalizedCurrentSession != normalizedEventSession) {
    return false;
  }
  if (eventRevision != null && eventRevision < currentRevision) {
    return false;
  }
  return true;
}

/// A restored CallKit answer may be delivered again after the same media
/// session has already started. The native event naturally carries the older
/// revision from the ringing snapshot, so replay detection deliberately keys
/// on the immutable call id and session instead of the mutable revision.
@visibleForTesting
bool callKitAcceptIsActiveReplay({
  required CallState currentState,
  required int? currentCallId,
  required int? eventCallId,
  String? currentSessionId,
  String? eventSessionId,
}) {
  if (currentState != CallState.connecting &&
      currentState != CallState.connected &&
      currentState != CallState.reconnecting) {
    return false;
  }
  if (currentCallId == null ||
      currentCallId <= 0 ||
      eventCallId == null ||
      eventCallId != currentCallId) {
    return false;
  }
  final currentSession = currentSessionId?.trim() ?? '';
  final eventSession = eventSessionId?.trim() ?? '';
  return currentSession.isNotEmpty && currentSession == eventSession;
}

String _normalizeRtcProvider(String? provider) {
  return provider?.trim().toLowerCase() == 'livekit' ? 'livekit' : 'agora';
}

@visibleForTesting
String stableIosCallKitUuid(int callId, {String? sessionId}) {
  final normalizedSession = sessionId?.trim() ?? '';
  final seed = normalizedSession.isEmpty
      ? 'customer-call-$callId'
      : 'customer-call-$callId-$normalizedSession';
  final digest = sha256.convert(utf8.encode(seed)).bytes;
  String byteHex(int index) => digest[index].toRadixString(16).padLeft(2, '0');
  return '${byteHex(0)}${byteHex(1)}${byteHex(2)}${byteHex(3)}-'
      '${byteHex(4)}${byteHex(5)}-'
      '${byteHex(6)}${byteHex(7)}-'
      '${byteHex(8)}${byteHex(9)}-'
      '${byteHex(10)}${byteHex(11)}${byteHex(12)}'
      '${byteHex(13)}${byteHex(14)}${byteHex(15)}';
}

String _firstStringValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

@visibleForTesting
Map<String, dynamic>? incomingCallPayloadFromActiveSnapshot(
  Map<String, dynamic> data, {
  DateTime? now,
}) {
  if (data['active'] != true ||
      data['status']?.toString() != 'calling' ||
      data['role']?.toString() != 'callee') {
    return null;
  }
  final callId = _intValue(data['call_id']);
  final remoteId = data['remote_id']?.toString().trim() ?? '';
  final remoteName = data['remote_name']?.toString() ?? '';
  final channel = _firstStringValue(data, ['channel_name', 'room_name']);
  final expiresAt = data['expires_at']?.toString();
  if (callId == null ||
      callId <= 0 ||
      remoteId.isEmpty ||
      channel.isEmpty ||
      incomingCallIsExpired(expiresAt, now ?? DateTime.now())) {
    return null;
  }
  return <String, dynamic>{
    'call_id': callId,
    'session_id': data['session_id'],
    'revision': data['revision'],
    'call_type': data['call_type'],
    'channel_name': channel,
    'room_name': _firstStringValue(data, ['room_name', 'channel_name']),
    'provider': data['provider'] ?? data['rtc_provider'],
    'rtc_provider': data['rtc_provider'] ?? data['provider'],
    'server_url': data['server_url'],
    'caller_id': remoteId,
    'caller_name': remoteName,
    'caller_avatar': data['remote_avatar'],
    'expires_at': expiresAt,
    'target_device_session_id': data['target_device_session_id'],
    'server_time_ms': data['server_time_ms'],
  };
}

bool _truthyValue(dynamic value) {
  if (value == true) return true;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

class CallInfo {
  final int? callId;
  final String? sessionId;
  final String? clientRequestId;
  final int revision;
  final int generation;
  final String channelName;
  final String roomName;
  final String rtcProvider;
  final String? serverUrl;
  final String? identity;
  final String? remoteIdentity;
  final String remoteUserId;
  final String remoteName;
  final String? remoteAvatar;
  final String? targetDeviceSessionId;
  final CallType type;
  final bool isOutgoing;
  final DateTime startTime;
  DateTime? connectTime;
  int? remoteUid;

  CallInfo({
    this.callId,
    this.sessionId,
    this.clientRequestId,
    this.revision = 0,
    this.generation = 0,
    required this.channelName,
    String? roomName,
    this.rtcProvider = 'agora',
    this.serverUrl,
    this.identity,
    this.remoteIdentity,
    required this.remoteUserId,
    required this.remoteName,
    this.remoteAvatar,
    this.targetDeviceSessionId,
    required this.type,
    required this.isOutgoing,
    DateTime? startTime,
    this.connectTime,
    this.remoteUid,
  })  : roomName = roomName ?? channelName,
        startTime = startTime ?? DateTime.now();

  CallInfo copyWith({
    int? callId,
    String? sessionId,
    String? clientRequestId,
    int? revision,
    int? generation,
    String? channelName,
    String? roomName,
    String? rtcProvider,
    String? serverUrl,
    String? identity,
    String? remoteIdentity,
    String? remoteUserId,
    String? remoteName,
    String? remoteAvatar,
    String? targetDeviceSessionId,
    CallType? type,
    bool? isOutgoing,
    DateTime? startTime,
    DateTime? connectTime,
    int? remoteUid,
  }) {
    return CallInfo(
      callId: callId ?? this.callId,
      sessionId: sessionId ?? this.sessionId,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      revision: revision ?? this.revision,
      generation: generation ?? this.generation,
      channelName: channelName ?? this.channelName,
      roomName: roomName ?? this.roomName,
      rtcProvider: rtcProvider ?? this.rtcProvider,
      serverUrl: serverUrl ?? this.serverUrl,
      identity: identity ?? this.identity,
      remoteIdentity: remoteIdentity ?? this.remoteIdentity,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      remoteName: remoteName ?? this.remoteName,
      remoteAvatar: remoteAvatar ?? this.remoteAvatar,
      targetDeviceSessionId:
          targetDeviceSessionId ?? this.targetDeviceSessionId,
      type: type ?? this.type,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      startTime: startTime ?? this.startTime,
      connectTime: connectTime ?? this.connectTime,
      remoteUid: remoteUid ?? this.remoteUid,
    );
  }
}

/// 通话业务状态的页面投影；服务端信令状态与 RTC 媒体连接由 [CallService] 协调后写入。
class CallServiceState {
  final CallState state;
  final CallInfo? callInfo;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isRemoteVideoEnabled;
  final bool isMinimized;
  final String? errorMessage;
  final int reconnectSecondsRemaining;
  final CallPermissionIssue? permissionIssue;

  const CallServiceState({
    this.state = CallState.idle,
    this.callInfo,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = true,
    this.isRemoteVideoEnabled = true,
    this.isMinimized = false,
    this.errorMessage,
    this.reconnectSecondsRemaining = 0,
    this.permissionIssue,
  });

  CallServiceState copyWith({
    CallState? state,
    CallInfo? callInfo,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    bool? isRemoteVideoEnabled,
    bool? isMinimized,
    String? errorMessage,
    bool clearError = false,
    int? reconnectSecondsRemaining,
    CallPermissionIssue? permissionIssue,
    bool clearPermissionIssue = false,
  }) {
    return CallServiceState(
      state: state ?? this.state,
      callInfo: callInfo ?? this.callInfo,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isRemoteVideoEnabled: isRemoteVideoEnabled ?? this.isRemoteVideoEnabled,
      isMinimized: isMinimized ?? this.isMinimized,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      reconnectSecondsRemaining:
          reconnectSecondsRemaining ?? this.reconnectSecondsRemaining,
      permissionIssue: clearPermissionIssue
          ? null
          : (permissionIssue ?? this.permissionIssue),
    );
  }

  bool get isInCall =>
      state == CallState.preparing ||
      state == CallState.outgoing ||
      state == CallState.incoming ||
      state == CallState.connecting ||
      state == CallState.connected ||
      state == CallState.reconnecting ||
      state == CallState.failed;
}

/// Media objects detached from one immutable call generation.
///
/// A queued cleanup must never look up mutable service fields after another
/// rapid-redial attempt has installed its own engine or room.
class _DetachedCallMedia {
  const _DetachedCallMedia({
    this.engine,
    this.liveKitRoom,
    this.liveKitLocalVideoTrack,
  });

  final RtcEngine? engine;
  final lk.Room? liveKitRoom;
  final lk.LocalVideoTrack? liveKitLocalVideoTrack;
}

class _AcceptAttempt {
  _AcceptAttempt({
    required this.id,
    required this.callId,
    required this.sessionId,
    required this.callKitUuid,
  }) : cancelToken = CancelToken();

  final int id;
  final int callId;
  String? sessionId;
  final String? callKitUuid;
  final CancelToken cancelToken;
  final Completer<bool> resolutionResult = Completer<bool>();
  final Completer<void> rollbackComplete = Completer<void>();
  Timer? timer;
  bool serverAccepted = false;
  bool rollbackStarted = false;
}

/// 单人通话状态机，统一协调 HTTP/WS 信令、Agora/LiveKit 媒体层和系统 CallKit。
///
/// 服务端 callId 是业务会话身份；RTC channel/room 只承载媒体，不能单独证明通话仍有效。
class CallService extends StateNotifier<CallServiceState> {
  final ApiClient _api;
  final WebSocketService _wsService;
  final CallEndToneService _callEndTone;
  final IncomingCallToneService _incomingCallTone;
  final OutgoingCallToneService _outgoingCallTone;
  final CallTerminalOutbox _terminalOutbox = CallTerminalOutbox();
  Future<void>? _terminalOutboxDrainFuture;
  RtcEngine? _engine;
  bool _agoraPreviewStarted = false;
  Timer? _callTimer;
  Timer? _callHeartbeatTimer;
  Timer? _outgoingCallTimer;
  Timer? _reconnectTimer;
  DateTime? _reconnectDeadline;
  Future<void>? _localCleanupFuture;
  Future<void>? _leaveChannelFuture;
  Future<void>? _speakerRouteFuture;
  String? _appId;
  String _rtcProvider = 'agora';
  String? _liveKitServerUrl;
  lk.Room? _liveKitRoom;
  lk.EventsListener<lk.RoomEvent>? _liveKitListener;
  lk.LocalVideoTrack? _liveKitLocalVideoTrack;
  lk.RemoteVideoTrack? _liveKitRemoteVideoTrack;
  String? _liveKitRemoteIdentity;
  lk.Room? _preparedLiveKitRoom;
  Future<void>? _preparedLiveKitFuture;
  String? _preparedLiveKitUrl;
  bool _isEnabled = false;
  bool _isSimulator = false;

  // CallKit identities remain owned by their immutable business call. Delayed
  // callbacks must never resolve through one mutable "current UUID" value.
  final Map<int, String> _callKitUuidByCallId = <int, String>{};
  final Map<String, int> _callIdByCallKitUuid = <String, int>{};
  final Map<String, String> _callKitSessionByUuid = <String, String>{};
  final Set<String> _callKitAcceptsInFlight = <String>{};
  static const MethodChannel _iosNativeCallKitChannel =
      MethodChannel('com.customer/push');

  Duration _serverClockOffset = Duration.zero;
  bool _hasServerClockOffset = false;
  Duration _connectedElapsedBase = Duration.zero;
  Stopwatch? _connectedElapsedStopwatch;
  String? _connectedClockIdentity;

  Function(CallInfo)? onIncomingCall;
  Function()? onCallConnected;
  Function(String reason)? onCallEnded;
  Function(String error)? onCallFailed;

  static GlobalKey<NavigatorState>? navigatorKey;

  Future<void>? _initEngineFuture;
  Completer<void>? _agoraJoinCompleter;
  bool _isAcceptingCall = false;
  bool _isEndingCall = false;
  bool _isRejectingCall = false;
  bool _isCancellingCall = false;
  int _outgoingAttemptGeneration = 0;
  int? _activeOutgoingAttemptId;
  Stopwatch? _outgoingAttemptStopwatch;
  int _acceptAttemptGeneration = 0;
  _AcceptAttempt? _activeAcceptAttempt;
  final Set<int> _heartbeatInactiveConfirmations = <int>{};

  StreamSubscription? _callKitSubscription;

  bool _isRestoringSystemIncomingCall = false;

  final List<String> _wsHandlerIds = [];

  bool _configLoaded = false;
  Future<void>? _configLoadFuture;

  RtcEngineEventHandler? _eventHandler;

  bool _isDisposed = false;
  bool _restoreVideoAfterBackground = false;
  final bool _prefetchConfig;

  CallService(
    this._api,
    this._wsService, {
    bool prefetchConfig = false,
    CallEndToneService? callEndTone,
    IncomingCallToneService? incomingCallTone,
    OutgoingCallToneService? outgoingCallTone,
  })  : _prefetchConfig = prefetchConfig,
        _callEndTone = callEndTone ?? CallEndToneService(),
        _incomingCallTone = incomingCallTone ?? IncomingCallToneService(),
        _outgoingCallTone = outgoingCallTone ?? OutgoingCallToneService(),
        super(const CallServiceState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      await _checkSimulator();

      // 系统来电 UI 仅在移动真机启用；Web/桌面仍共享同一套 WS 信令状态机。
      if (!kIsWeb && !_isSimulator && (Platform.isIOS || Platform.isAndroid)) {
        _setupCallKit();
      }

      _setupWebSocketListeners();
      unawaited(_drainTerminalOutbox());
      // 登录态创建 CallService 后立即预取配置。发起按钮只负责写入本地状态，
      // 不能再把配置请求放在通话页导航之前。
      if (_prefetchConfig) {
        unawaited(ensureConfigLoaded());
      }
    } catch (e) {
      debugPrint('[CallService] Init error: $e');
    }
  }

  Future<void> ensureConfigLoaded() async {
    if (_configLoaded || _isDisposed) return;
    final running = _configLoadFuture;
    if (running != null) return running;

    late final Future<void> current;
    current = () async {
      final loaded = await _loadConfig();
      if (loaded) _configLoaded = true;
    }();
    _configLoadFuture = current;
    try {
      await current;
    } catch (e) {
      debugPrint('[CallService] Load config error: $e');
    } finally {
      if (identical(_configLoadFuture, current)) {
        _configLoadFuture = null;
      }
    }
  }

  Future<void> startIncomingCallTone() async {
    if (_isDisposed || state.state != CallState.incoming) return;
    await _incomingCallTone.start();
  }

  Future<void> stopIncomingCallTone() => _incomingCallTone.stop();

  Future<void> _checkSimulator() async {
    try {
      if (kIsWeb) {
        _isSimulator = false;
        return;
      }
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _isSimulator = !iosInfo.isPhysicalDevice;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _isSimulator = !androidInfo.isPhysicalDevice;
      } else {
        _isSimulator = false;
      }
      if (_isSimulator) {
        debugPrint('[CallService] Running on simulator');
      }
    } catch (e) {
      debugPrint('[CallService] Check simulator error: $e');
    }
  }

  DateTime? _serverTimeFromPayload(Map<String, dynamic> data) {
    final rawMilliseconds = data['server_time_ms'];
    final milliseconds = rawMilliseconds is int
        ? rawMilliseconds
        : int.tryParse(rawMilliseconds?.toString() ?? '');
    if (milliseconds != null && milliseconds > 0) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    return DateTime.tryParse(data['server_time']?.toString() ?? '')?.toUtc();
  }

  void _observeServerClock(
    Map<String, dynamic> data, {
    DateTime? localRequestStarted,
    DateTime? localResponseReceived,
  }) {
    final serverTime = _serverTimeFromPayload(data);
    if (serverTime == null) return;
    final received = localResponseReceived ?? DateTime.now();
    final started = localRequestStarted ?? received;
    if (received.isBefore(started)) return;
    final sample = estimateServerClockOffset(
      serverTime: serverTime,
      localRequestStarted: started,
      localResponseReceived: received,
    );
    if (sample.abs() > const Duration(hours: 24)) return;
    _serverClockOffset = sample;
    _hasServerClockOffset = true;
  }

  String _callClockIdentity(CallInfo info) {
    final session = info.sessionId?.trim() ?? '';
    return '${info.callId ?? 0}:$session';
  }

  void _startConnectedClock(CallInfo info, {bool forceRebase = false}) {
    final identity = _callClockIdentity(info);
    if (!forceRebase &&
        _connectedClockIdentity == identity &&
        _connectedElapsedStopwatch?.isRunning == true) {
      return;
    }
    final localNow = DateTime.now();
    final offset = _hasServerClockOffset ? _serverClockOffset : Duration.zero;
    final elapsed = callElapsedSecondsWithClockOffset(
      info.connectTime,
      localNow,
      offset,
    );
    _connectedClockIdentity = identity;
    _connectedElapsedBase = Duration(seconds: elapsed);
    _connectedElapsedStopwatch = Stopwatch()..start();
  }

  void _resetConnectedClock() {
    _connectedElapsedStopwatch?.stop();
    _connectedElapsedStopwatch = null;
    _connectedElapsedBase = Duration.zero;
    _connectedClockIdentity = null;
  }

  Future<bool> _incomingCallTargetsThisDevice(
    Map<String, dynamic> data,
  ) async {
    final target = _firstStringValue(
      data,
      ['target_device_session_id', 'callee_device_session_id'],
    );
    if (target.isEmpty) return true;
    final current = (await DeviceService.getDeviceId()).trim();
    return current.isNotEmpty && current == target;
  }

  void _setupWebSocketListeners() {
    debugPrint('[CallService] Setting up WebSocket listeners');

    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();

    final incomingId = _wsService.registerHandler(WSMessageType.incomingCall, (
      data,
    ) {
      debugPrint('[CallService] ========== INCOMING CALL ==========');
      debugPrint(
          '[CallService] Incoming call data: ${_sensitiveMapSummary(data)}');
      debugPrint(
        '[CallService] isSimulator: $_isSimulator, isEnabled: $_isEnabled',
      );
      final callData = data['data'] as Map<String, dynamic>?;
      if (callData != null) {
        unawaited(() async {
          if (!await _incomingCallTargetsThisDevice(callData)) {
            debugPrint(
              '[CallService] Incoming call belongs to another device session',
            );
            return;
          }
          await handleIncomingCall(callData);
        }());
      } else {
        debugPrint('[CallService] ERROR: callData is null!');
      }
    });
    _wsHandlerIds.add(incomingId);

    final acceptedId = _wsService.registerHandler(WSMessageType.callAccepted, (
      data,
    ) {
      debugPrint('[CallService] Call accepted');
      final payload = _asStringKeyMap(data['data']);
      handleCallAccepted(payload);
    });
    _wsHandlerIds.add(acceptedId);

    final connectedId = _wsService.registerHandler(
      WSMessageType.callConnected,
      (data) {
        debugPrint('[CallService] Call media connected');
        final payload = _asStringKeyMap(data['data']);
        handleCallConnected(payload);
      },
    );
    _wsHandlerIds.add(connectedId);

    final rejectedId = _wsService.registerHandler(WSMessageType.callRejected, (
      data,
    ) {
      debugPrint('[CallService] Call rejected: ${_sensitiveMapSummary(data)}');
      final payload = _asStringKeyMap(data['data']);
      final reason = payload?['reason']?.toString() ?? 'decline';
      handleCallRejected(reason, payload);
    });
    _wsHandlerIds.add(rejectedId);

    final endedId = _wsService.registerHandler(WSMessageType.callEnded, (data) {
      debugPrint('[CallService] Call ended: ${_sensitiveMapSummary(data)}');
      final payload = _asStringKeyMap(data['data']);
      unawaited(_handleRemoteCallEnded(payload));
    });
    _wsHandlerIds.add(endedId);

    final releasedId = _wsService.registerHandler(
      WSMessageType.callReleased,
      (data) {
        debugPrint(
            '[CallService] Call released: ${_sensitiveMapSummary(data)}');
        final payload = _asStringKeyMap(data['data']);
        unawaited(_handleRemoteCallEnded(payload));
      },
    );
    _wsHandlerIds.add(releasedId);

    final cancelledId = _wsService.registerHandler(
      WSMessageType.callCancelled,
      (data) {
        debugPrint('[CallService] Call cancelled');
        final payload = _asStringKeyMap(data['data']);
        unawaited(handleCallCancelled(payload));
      },
    );
    _wsHandlerIds.add(cancelledId);

    final mediaChangedId = _wsService.registerHandler(
      WSMessageType.callMediaChanged,
      (data) {
        final payload = _asStringKeyMap(data['data']);
        if (payload != null) {
          unawaited(_handleRemoteMediaChanged(payload));
        }
      },
    );
    _wsHandlerIds.add(mediaChangedId);

    final reconnectedId = _wsService.registerHandler(
      WSMessageType.reconnected,
      (_) {
        // A terminal event can be lost while the socket is reconnecting. The
        // server remains authoritative, so reconcile local ringing/call state.
        unawaited(_drainTerminalOutbox());
        unawaited(syncActiveCallStateWithServer());
      },
    );
    _wsHandlerIds.add(reconnectedId);
  }

  Future<bool> _loadConfig() async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/call/config');
      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        _isEnabled = data['enabled'] == true;
        _appId = data['app_id']?.toString();
        _rtcProvider = _normalizeRtcProvider(
          _firstStringValue(data, ['rtc_provider', 'provider']),
        );
        _liveKitServerUrl = _firstStringValue(
          data,
          ['livekit_server_url', 'server_url'],
        );
        if (_liveKitServerUrl?.isEmpty == true) {
          _liveKitServerUrl = null;
        }
        if (_rtcProvider == 'livekit' && _liveKitServerUrl != null) {
          unawaited(_prepareLiveKitConnection(_liveKitServerUrl!));
        }
        final appIdPreview = (_appId == null || _appId!.isEmpty)
            ? '-'
            : (_appId!.length > 8 ? '${_appId!.substring(0, 8)}...' : _appId!);
        debugPrint(
          '[CallService] Enabled: $_isEnabled, provider=$_rtcProvider, AppId: $appIdPreview, LiveKit=${_liveKitServerUrl?.isNotEmpty == true}',
        );
        return true;
      }
    } catch (e) {
      debugPrint('[CallService] Load config error: $e');
    }
    return false;
  }

  bool _hasRtcConfig(String provider) {
    if (provider == 'livekit') {
      return _liveKitServerUrl != null && _liveKitServerUrl!.isNotEmpty;
    }
    return _appId != null && _appId!.isNotEmpty;
  }

  String _providerFromData(
    Map<String, dynamic> data, {
    String? fallback,
  }) {
    final provider = _firstStringValue(data, ['rtc_provider', 'provider']);
    if (provider.isNotEmpty) {
      return _normalizeRtcProvider(provider);
    }
    return _normalizeRtcProvider(fallback ?? _rtcProvider);
  }

  String? _serverUrlFromData(Map<String, dynamic> data) {
    final value = _firstStringValue(
      data,
      ['server_url', 'livekit_server_url'],
    );
    if (value.isNotEmpty) return value;
    return _liveKitServerUrl;
  }

  bool get isEnabled {
    if (!_isEnabled || !_hasRtcConfig(_rtcProvider)) {
      return false;
    }
    return true;
  }

  String? _callUnavailableReason() {
    if (!_isEnabled || !_hasRtcConfig(_rtcProvider)) {
      return _mediaServiceUnavailableText();
    }
    return null;
  }

  Future<void> syncActiveCallStateWithServer({
    bool releaseServerWhenLocalIdle = false,
  }) async {
    if (_isDisposed) return;
    // Lifecycle resume can run before AuthService has restored the persisted
    // session. Avoid an unauthenticated /call/active request in that window;
    // authentication listeners and the next resume will reconcile once the
    // API client has a usable token.
    if (_api.currentToken?.isNotEmpty != true) return;
    try {
      final response = await _api.get<Map<String, dynamic>>('/call/active');
      if (!response.isSuccess || response.data == null) return;
      final data = response.data!;
      _observeServerClock(data);
      final active = data['active'] == true;
      if (!active && state.isInCall && (state.callInfo?.callId ?? 0) > 0) {
        final currentCallId = state.callInfo!.callId!;
        debugPrint(
          '[CallService] Active-call sync returned inactive; confirming '
          'call_id=$currentCallId',
        );
        await _confirmInactiveHeartbeat(currentCallId);
        return;
      }
      if (active &&
          state.state == CallState.connecting &&
          _intValue(data['call_id']) == state.callInfo?.callId &&
          data['status']?.toString() == 'connected') {
        handleCallConnected(<String, dynamic>{
          ...data,
          'connected_at': data['connected_at'] ?? data['connect_time'],
        });
        return;
      }
      if (active && (!state.isInCall || state.state == CallState.preparing)) {
        final status = data['status']?.toString();
        final role = data['role']?.toString();
        final callId = _intValue(data['call_id']) ?? 0;
        final sessionId = _sessionIdFromPayload(data);
        final startTime =
            DateTime.tryParse(data['start_time']?.toString() ?? '');
        final authoritativeNow = DateTime.now().add(
          _hasServerClockOffset ? _serverClockOffset : Duration.zero,
        );
        final age = startTime == null
            ? Duration.zero
            : authoritativeNow.difference(startTime);
        if (releaseServerWhenLocalIdle && callId > 0) {
          if (status == 'calling' && role == 'caller') {
            debugPrint('[CallService] Cancelling stale outgoing call: $callId');
            await _cancelCallById(callId, sessionId: sessionId);
          } else {
            debugPrint('[CallService] Ending stale active call: $callId');
            await _endCallById(
              callId,
              'client_reset',
              sessionId: sessionId,
            );
          }
          return;
        }
        if (state.state == CallState.idle &&
            status == 'calling' &&
            role == 'callee') {
          final incoming = incomingCallPayloadFromActiveSnapshot(data);
          if (incoming != null) {
            debugPrint(
              '[CallService] Restoring missed incoming call from active snapshot: $callId',
            );
            await handleIncomingCall(incoming);
          }
          return;
        }
        if (state.state == CallState.idle &&
            status == 'connecting' &&
            callId > 0) {
          debugPrint(
            '[CallService] Ending orphan connecting call after restart: $callId',
          );
          await _endCallById(
            callId,
            'client_restart_during_connect',
            sessionId: sessionId,
          );
          return;
        }
        if (status == 'calling' &&
            role == 'caller' &&
            callId > 0 &&
            age > const Duration(seconds: 15)) {
          debugPrint('[CallService] Cancelling orphan outgoing call: $callId');
          await _cancelCallById(callId, sessionId: sessionId);
        }
      }
    } catch (e) {
      debugPrint('[CallService] Sync active call state error: $e');
    }
  }

  Future<CallType?> _requestPermissions(
    CallType type, {
    bool allowVideoDowngrade = false,
    required bool userInitiated,
  }) async {
    try {
      if (kIsWeb) {
        debugPrint(
          '[CallService] Web platform, browser will handle media permissions',
        );
        return type;
      }
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        debugPrint(
          '[CallService] Desktop platform, system will handle permissions',
        );
        return type;
      }

      // The overnight real-device QA build must never open the microphone.
      // Voice calls need no runtime media permission in this mode; video calls
      // request only camera access so camera signalling/rendering remains
      // testable without touching RECORD_AUDIO.
      if (kSilentCallQaMode) {
        if (type != CallType.video) return type;
        final cameraResult = await resolveMediaPermission(
          readStatus: () => Permission.camera.status,
          requestPermission: () => Permission.camera.request(),
          userInitiated: userInitiated,
          allowVoiceFallback: allowVideoDowngrade,
        );
        if (cameraResult.isGranted) return type;
        if (cameraResult.action == MediaPermissionAction.fallbackToVoice) {
          state = state.copyWith(
            isVideoEnabled: false,
            clearPermissionIssue: true,
            clearError: true,
          );
          return CallType.voice;
        }
        state = state.copyWith(
          errorMessage: _callServiceText(
            zhCN:
                '\u9700\u8981\u76f8\u673a\u6743\u9650\u624d\u80fd\u8fdb\u884c\u89c6\u9891\u901a\u8bdd',
            zhTW:
                '\u9700\u8981\u76f8\u6a5f\u6b0a\u9650\u624d\u80fd\u9032\u884c\u8996\u8a0a\u901a\u8a71',
            en: 'Camera permission is required for video calls',
          ),
          permissionIssue: cameraResult.status.isPermanentlyDenied
              ? CallPermissionIssue.cameraPermanentlyDenied
              : CallPermissionIssue.cameraDenied,
        );
        return null;
      }

      final micResult = await resolveMediaPermission(
        readStatus: () => Permission.microphone.status,
        requestPermission: () => Permission.microphone.request(),
        userInitiated: userInitiated,
      );
      if (!micResult.isGranted) {
        debugPrint('[CallService] Microphone permission denied');
        state = state.copyWith(
          errorMessage: _callServiceText(
            zhCN: '麦克风未开启，暂时无法录音或通话。',
            zhTW: '麥克風未開啟，暫時無法錄音或通話。',
            en: 'Microphone access is off. Recording and calls are unavailable.',
          ),
          permissionIssue: micResult.status.isPermanentlyDenied
              ? CallPermissionIssue.microphonePermanentlyDenied
              : CallPermissionIssue.microphoneDenied,
        );
        return null;
      }

      if (type == CallType.video) {
        final cameraResult = await resolveMediaPermission(
          readStatus: () => Permission.camera.status,
          requestPermission: () => Permission.camera.request(),
          userInitiated: userInitiated,
          allowVoiceFallback: allowVideoDowngrade,
        );
        if (!cameraResult.isGranted) {
          debugPrint('[CallService] Camera permission denied');
          if (cameraResult.action == MediaPermissionAction.fallbackToVoice) {
            state = state.copyWith(
              isVideoEnabled: false,
              clearPermissionIssue: true,
              clearError: true,
            );
            return CallType.voice;
          }
          state = state.copyWith(
            errorMessage: _callServiceText(
              zhCN: cameraResult.status.isPermanentlyDenied
                  ? '相机权限已被永久拒绝，可改用语音或前往系统设置开启'
                  : '相机权限未开启，可改用语音通话',
              zhTW: cameraResult.status.isPermanentlyDenied
                  ? '相機權限已被永久拒絕，可改用語音或前往系統設定開啟'
                  : '相機權限未開啟，可改用語音通話',
              en: cameraResult.status.isPermanentlyDenied
                  ? 'Camera access is permanently denied. Use voice or enable it in system settings.'
                  : 'Camera access is unavailable. You can continue with a voice call.',
            ),
            permissionIssue: cameraResult.status.isPermanentlyDenied
                ? CallPermissionIssue.cameraPermanentlyDenied
                : CallPermissionIssue.cameraDenied,
            isVideoEnabled: false,
          );
          return null;
        }
      }

      if (Platform.isAndroid) {
        await Permission.bluetoothConnect.request();
      }
    } catch (e) {
      debugPrint('[CallService] Permission request error: $e');
      state = state.copyWith(
        errorMessage: _callServiceText(
          zhCN: '无法确认通话权限，请重试或前往系统设置检查',
          zhTW: '無法確認通話權限，請重試或前往系統設定檢查',
          en: 'Unable to verify call permissions. Retry or check system settings.',
        ),
        permissionIssue: CallPermissionIssue.microphoneDenied,
      );
      return null;
    }

    state = state.copyWith(clearPermissionIssue: true, clearError: true);
    return type;
  }

  Future<bool> openCallPermissionSettings() => openAppSettings();

  Future<void> _initEngine() async {
    if (_engine != null) return;

    if (_initEngineFuture != null) {
      return _initEngineFuture;
    }

    _initEngineFuture = _doInitEngine();
    try {
      await _initEngineFuture;
    } finally {
      _initEngineFuture = null;
    }
  }

  Future<void> _initEngineWithWebRetry() async {
    const maxAttempts = kIsWeb ? 12 : 2;
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        await _initEngine();
        return;
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        _eventHandler = null;
        _engine = null;
        if (attempt == maxAttempts) {
          Error.throwWithStackTrace(error, stack);
        }
        debugPrint(
          '[CallService] Agora web engine init attempt $attempt failed: $error',
        );
        final delayMs =
            kIsWeb ? (250 * attempt > 1000 ? 1000 : 250 * attempt) : 50;
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    if (lastError != null && lastStack != null) {
      Error.throwWithStackTrace(lastError, lastStack);
    }
  }

  Future<void> _doInitEngine() async {
    if (_engine != null) return;
    if (_appId == null || _appId!.isEmpty) {
      throw Exception('App ID not configured');
    }

    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(
      RtcEngineContext(
        appId: _appId!,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    if (!identical(_engine, engine)) {
      try {
        await engine.release();
      } catch (_) {}
      throw StateError('Agora initialization superseded by another call');
    }

    final eventHandler = RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('[Agora] Join channel success: ${connection.channelId}');
        final joinCompleter = _agoraJoinCompleter;
        if (joinCompleter != null && !joinCompleter.isCompleted) {
          joinCompleter.complete();
        }
        final attemptId = _activeOutgoingAttemptId;
        if (attemptId != null) {
          _traceOutgoingAttempt(attemptId, 'local_rtc_joined');
        }
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        debugPrint('[Agora] User joined: $remoteUid');
        if (_isDisposed || state.callInfo == null) return;
        if (state.state == CallState.connected ||
            state.state == CallState.reconnecting) {
          _markCallConnected(
            remoteUid: remoteUid,
            source: 'agora_user_joined',
          );
        } else {
          state = state.copyWith(
            callInfo: state.callInfo!.copyWith(remoteUid: remoteUid),
          );
        }
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('[Agora] User offline: $remoteUid, reason: $reason');
        if (_isDisposed) return;
        _beginReconnect('agora_remote_offline');
      },
      onRemoteVideoStateChanged:
          (connection, remoteUid, videoState, reason, elapsed) {
        debugPrint(
          '[Agora] Remote video state: $videoState, reason: $reason',
        );
        if (_isDisposed) return;
        if (state.state == CallState.connected ||
            state.state == CallState.connecting) {
          final isEnabled =
              videoState == RemoteVideoState.remoteVideoStateDecoding ||
                  videoState == RemoteVideoState.remoteVideoStateStarting;
          state = state.copyWith(isRemoteVideoEnabled: isEnabled);
        }
      },
      onError: (err, msg) {
        debugPrint('[Agora] Error: $err - $msg');
        final joinCompleter = _agoraJoinCompleter;
        if (joinCompleter != null && !joinCompleter.isCompleted) {
          joinCompleter.completeError(
            StateError('Agora join failed: $err $msg'),
          );
        }
        if (_isDisposed) return;
        if (state.state != CallState.idle) {
          state = state.copyWith(errorMessage: msg);
        }
      },
      onConnectionStateChanged: (connection, stateType, reason) {
        debugPrint('[Agora] Connection state: $stateType, reason: $reason');
        if (_isDisposed) return;
        if (stateType == ConnectionStateType.connectionStateConnected) {
          _recoverReconnect('agora_connection_restored');
        } else if (stateType ==
                ConnectionStateType.connectionStateDisconnected ||
            stateType == ConnectionStateType.connectionStateFailed) {
          if (state.state == CallState.connected ||
              state.state == CallState.reconnecting) {
            _beginReconnect('agora_connection_lost');
          }
        }
      },
    );
    if (!identical(_engine, engine)) {
      try {
        await engine.release();
      } catch (_) {}
      throw StateError('Agora initialization superseded by another call');
    }
    _eventHandler = eventHandler;
    engine.registerEventHandler(eventHandler);

    if (kSilentCallQaMode) {
      // Do not initialize Agora's audio module at all in overnight QA. Join
      // presence/video signalling still works, while neither capture nor
      // playback can touch an audio device even transiently.
      await engine.disableAudio();
    } else {
      await engine.enableAudio();
    }

    if (Platform.isIOS || Platform.isAndroid) {
      final useSpeaker = state.callInfo?.type == CallType.video;
      try {
        await _setDefaultSpeakerphoneRoute(useSpeaker);
      } catch (e) {
        // iOS can reject route changes until CallKit/Agora activates the audio
        // session. The joined-channel route application below retries it.
        debugPrint('[CallService] Default audio route deferred: $e');
      }
    }
  }

  Future<void> _joinAgoraChannelAndWait({
    required String token,
    required String channelName,
    required int uid,
    required bool isVideo,
  }) async {
    final engine = _engine;
    if (engine == null) throw StateError('Agora engine is unavailable');
    final completer = Completer<void>();
    _agoraJoinCompleter = completer;
    try {
      await engine.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid > 0 ? uid : 0,
        options: ChannelMediaOptions(
          autoSubscribeAudio: !kSilentCallQaMode,
          autoSubscribeVideo: isVideo ? true : null,
          publishMicrophoneTrack: !kSilentCallQaMode,
          publishCameraTrack: isVideo ? true : null,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      await completer.future.timeout(const Duration(seconds: 12));
    } finally {
      if (identical(_agoraJoinCompleter, completer)) {
        _agoraJoinCompleter = null;
      }
    }
  }

  /// Starts an outgoing attempt without waiting for network, permissions or RTC.
  ///
  /// This method is deliberately synchronous: the tap handler must be able to
  /// navigate to [CallState.preparing] in the same event loop. All expensive
  /// work continues in [_startCallInternal] and is guarded by an attempt id.
  bool startCall({
    required String targetUserId,
    required String targetName,
    String? targetAvatar,
    required CallType type,
  }) {
    if (_isDisposed || state.isInCall) return false;

    final attemptId = ++_outgoingAttemptGeneration;
    final clientRequestId = const Uuid().v4();
    _activeOutgoingAttemptId = attemptId;
    _outgoingAttemptStopwatch = Stopwatch()..start();
    state = CallServiceState(
      state: CallState.preparing,
      callInfo: CallInfo(
        clientRequestId: clientRequestId,
        generation: attemptId,
        channelName: '',
        rtcProvider: _rtcProvider,
        remoteUserId: targetUserId,
        remoteName: targetName,
        remoteAvatar: targetAvatar,
        type: type,
        isOutgoing: true,
      ),
      isVideoEnabled: type == CallType.video,
      isSpeakerOn: type == CallType.video,
      isRemoteVideoEnabled: false,
      isMuted: kSilentCallQaMode,
    );
    _traceOutgoingAttempt(attemptId, 'tap_preparing');

    // Browsers need the original user gesture for audio playback. Native ring
    // back starts only after RTC has joined so Huawei audio routing stays valid.
    unawaited(_callEndTone.stop());
    if (kIsWeb && !kSilentCallQaMode) {
      unawaited(_outgoingCallTone.start());
    }

    unawaited(_startCallInternal(
      attemptId: attemptId,
      targetUserId: targetUserId,
      targetName: targetName,
      targetAvatar: targetAvatar,
      type: type,
    ));
    return true;
  }

  bool retryOutgoingCall() {
    final info = state.callInfo;
    if (_isDisposed || state.state != CallState.failed || info == null) {
      return false;
    }
    _activeOutgoingAttemptId = null;
    state = const CallServiceState();
    return startCall(
      targetUserId: info.remoteUserId,
      targetName: info.remoteName,
      targetAvatar: info.remoteAvatar,
      type: info.type,
    );
  }

  bool retryOutgoingCallAsVoice() {
    final info = state.callInfo;
    if (_isDisposed ||
        state.state != CallState.failed ||
        info == null ||
        info.type != CallType.video ||
        !callPermissionSupportsVoiceFallback(state.permissionIssue)) {
      return false;
    }
    _activeOutgoingAttemptId = null;
    state = const CallServiceState();
    return startCall(
      targetUserId: info.remoteUserId,
      targetName: info.remoteName,
      targetAvatar: info.remoteAvatar,
      type: CallType.voice,
    );
  }

  void markCallPageFirstFrame() {
    final attemptId = _activeOutgoingAttemptId;
    if (attemptId != null) {
      _traceOutgoingAttempt(attemptId, 'call_page_first_frame');
    }
  }

  bool _isOutgoingAttemptActive(int attemptId) {
    return !_isDisposed &&
        _activeOutgoingAttemptId == attemptId &&
        state.callInfo != null &&
        state.state != CallState.idle &&
        state.state != CallState.ended;
  }

  void _traceOutgoingAttempt(int attemptId, String stage) {
    final elapsed = _outgoingAttemptStopwatch?.elapsedMilliseconds ?? 0;
    if (kDebugMode || const bool.fromEnvironment('ENABLE_PERF_TRACE')) {
      // Keep this on stdout instead of debugPrint: production bootstrap can
      // silence debugPrint, while opt-in performance builds still need a
      // stable logcat signal for device acceptance.
      // ignore: avoid_print
      print(
          '[CallLatency] attempt=$attemptId stage=$stage elapsed_ms=$elapsed');
    }
  }

  void _failOutgoingAttempt(int attemptId, String message) {
    if (!_isOutgoingAttemptActive(attemptId)) return;
    _traceOutgoingAttempt(attemptId, 'failed');
    state = state.copyWith(
      state: CallState.failed,
      errorMessage: message,
    );
    unawaited(_outgoingCallTone.stop());
  }

  Future<bool> _startCallInternal({
    required int attemptId,
    required String targetUserId,
    required String targetName,
    String? targetAvatar,
    required CallType type,
  }) async {
    if (!_isOutgoingAttemptActive(attemptId)) return false;

    // Cleanup no longer blocks config, validation or /call/create. Only the
    // media handoff waits for it, so rapid redial gets immediate UI and server
    // arbitration while still avoiding microphone/camera engine contention.
    final cleanupFuture = _waitForLocalCleanup();
    final clientRequestId =
        state.callInfo?.clientRequestId ?? const Uuid().v4();

    debugPrint(
      '[CallService] startCall: isWeb=$kIsWeb, isSimulator=$_isSimulator, isEnabled=$_isEnabled, provider=$_rtcProvider',
    );

    await ensureConfigLoaded();
    if (!_isOutgoingAttemptActive(attemptId)) return false;
    if (!_isEnabled || !_hasRtcConfig(_rtcProvider)) {
      // A cold-start request can race Android network restoration. Failed
      // loads are not cached; give the in-page preparation flow one quick
      // retry instead of incorrectly reporting that calls are disabled.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await ensureConfigLoaded();
      if (!_isOutgoingAttemptActive(attemptId)) return false;
    }
    _traceOutgoingAttempt(attemptId, 'config_ready');
    debugPrint(
      '[CallService] After loadConfig: isEnabled=$_isEnabled, provider=$_rtcProvider',
    );

    final unavailableReason = _callUnavailableReason();
    if (unavailableReason != null) {
      _failOutgoingAttempt(attemptId, unavailableReason);
      return false;
    }

    final isBlocked = await _isBlockedByCurrentUser(targetUserId);
    if (!_isOutgoingAttemptActive(attemptId)) return false;
    _traceOutgoingAttempt(attemptId, 'preflight_done');
    if (isBlocked) {
      _failOutgoingAttempt(attemptId, _blockedCallText());
      return false;
    }

    // 呼叫创建前要求实时通道可用，否则服务端虽创建成功，客户端也可能收不到接听/拒绝事件。
    final realtimeReady = await _wsService.ensureConnectedForRealtime(
      timeout: const Duration(seconds: 2),
    );
    if (!_isOutgoingAttemptActive(attemptId)) return false;
    if (!realtimeReady) {
      _failOutgoingAttempt(attemptId, _callConnectionNotReadyText());
      return false;
    }
    _traceOutgoingAttempt(attemptId, 'websocket_ready');

    var createdCallId = 0;
    String? createdSessionId;
    var rtcJoined = false;
    try {
      final permittedType = await _requestPermissions(
        type,
        userInitiated: true,
      );
      if (!_isOutgoingAttemptActive(attemptId)) return false;
      if (permittedType == null) {
        _failOutgoingAttempt(
          attemptId,
          state.errorMessage ?? _genericCallFailureText(),
        );
        return false;
      }
      _traceOutgoingAttempt(attemptId, 'permissions_ready');

      final createRequestStarted = DateTime.now();
      final createFuture = _api.post<Map<String, dynamic>>(
        '/call/create',
        data: {
          'target_user_id': targetUserId,
          'call_type': type == CallType.voice ? 'voice' : 'video',
          'client_request_id': clientRequestId,
          'attempt_generation': attemptId,
        },
      );
      if (type == CallType.video) {
        try {
          await cleanupFuture;
          if (!_isOutgoingAttemptActive(attemptId)) return false;
          _traceOutgoingAttempt(attemptId, 'cleanup_done');
          await _ensureOutgoingLocalPreview(attemptId, _rtcProvider);
        } catch (_) {
          // The create request is already in flight. Resolve it and cancel a
          // late server-side call so preview failures never leave a ghost ring.
          final lateResponse = await createFuture;
          final lateCallId = _intValue(lateResponse.data?['call_id']) ?? 0;
          if (lateCallId > 0) {
            await _cancelCallById(
              lateCallId,
              sessionId: _sessionIdFromPayload(
                lateResponse.data ?? const <String, dynamic>{},
              ),
            );
          }
          rethrow;
        }
        if (!_isOutgoingAttemptActive(attemptId)) {
          final lateResponse = await createFuture;
          final lateCallId = _intValue(lateResponse.data?['call_id']) ?? 0;
          if (lateCallId > 0) {
            await _cancelCallById(
              lateCallId,
              sessionId: _sessionIdFromPayload(
                lateResponse.data ?? const <String, dynamic>{},
              ),
            );
          }
          return false;
        }
      }

      final response = await createFuture;
      final createResponseReceived = DateTime.now();
      if (!_isOutgoingAttemptActive(attemptId)) {
        final lateCallId = _intValue(response.data?['call_id']) ?? 0;
        if (lateCallId > 0) {
          await _cancelCallById(
            lateCallId,
            sessionId: _sessionIdFromPayload(
              response.data ?? const <String, dynamic>{},
            ),
          );
        }
        return false;
      }
      _traceOutgoingAttempt(attemptId, 'create_done');

      if (!response.isSuccess || response.data == null) {
        _failOutgoingAttempt(
          attemptId,
          _callServerMessage(
            response.message,
            fallbackEn: 'Call failed. Please try again.',
          ),
        );
        return false;
      }

      final data = response.data!;
      _observeServerClock(
        data,
        localRequestStarted: createRequestStarted,
        localResponseReceived: createResponseReceived,
      );
      createdSessionId = _sessionIdFromPayload(data);
      if (type != CallType.video) {
        await cleanupFuture;
        if (!_isOutgoingAttemptActive(attemptId)) {
          final lateCallId = _intValue(data['call_id']) ?? 0;
          if (lateCallId > 0) {
            await _cancelCallById(lateCallId, sessionId: createdSessionId);
          }
          return false;
        }
        _traceOutgoingAttempt(attemptId, 'cleanup_done');
      }
      final arbitrated = _truthyValue(data['arbitrated']);
      final rtcProvider = _providerFromData(data);
      final channelName =
          _firstStringValue(data, ['channel_name', 'room_name']);
      final roomName = _firstStringValue(data, ['room_name', 'channel_name']);
      final token = data['token']?.toString() ?? '';
      final callId = data['call_id'] is int
          ? data['call_id'] as int
          : int.tryParse(data['call_id']?.toString() ?? '') ?? 0;
      createdCallId = callId;
      if (!_isOutgoingAttemptActive(attemptId)) {
        await _cancelCallById(createdCallId, sessionId: createdSessionId);
        return false;
      }
      final agoraUid = data['agora_uid'] is int
          ? data['agora_uid'] as int
          : int.tryParse(data['agora_uid']?.toString() ?? '') ?? 0;
      final serverUrl = _serverUrlFromData(data);
      if (channelName.isEmpty || token.isEmpty) {
        debugPrint(
          '[CallService] Invalid call data: channelName or token is empty',
        );
        await _cancelCallById(createdCallId, sessionId: createdSessionId);
        _failOutgoingAttempt(attemptId, _mediaServiceUnavailableText());
        return false;
      }
      if (rtcProvider == 'livekit' &&
          (serverUrl == null || serverUrl.isEmpty)) {
        debugPrint('[CallService] LiveKit server URL is empty');
        await _cancelCallById(createdCallId, sessionId: createdSessionId);
        _failOutgoingAttempt(attemptId, _mediaServiceUnavailableText());
        return false;
      }
      if (rtcProvider == 'agora' && (_appId == null || _appId!.isEmpty)) {
        debugPrint('[CallService] Agora App ID is empty');
        await _cancelCallById(createdCallId, sessionId: createdSessionId);
        _failOutgoingAttempt(attemptId, _mediaServiceUnavailableText());
        return false;
      }

      final provisionalInfo = state.callInfo!;
      state = state.copyWith(
        state: arbitrated ? CallState.connecting : CallState.outgoing,
        callInfo: provisionalInfo.copyWith(
          callId: callId,
          sessionId: _sessionIdFromPayload(data),
          revision: _revisionFromPayload(data) ?? 0,
          clientRequestId: clientRequestId,
          channelName: channelName,
          roomName: roomName.isNotEmpty ? roomName : channelName,
          rtcProvider: rtcProvider,
          serverUrl: serverUrl,
          identity: _firstStringValue(data, ['identity', 'livekit_identity']),
          isOutgoing: !arbitrated,
        ),
        isVideoEnabled: type == CallType.video,
        isSpeakerOn: type == CallType.video,
        isRemoteVideoEnabled: type != CallType.video,
        clearError: true,
        clearPermissionIssue: true,
      );

      if (type == CallType.video && rtcProvider != _rtcProvider) {
        await _ensureOutgoingLocalPreview(attemptId, rtcProvider);
        if (!_isOutgoingAttemptActive(attemptId)) {
          await _cancelCallById(createdCallId, sessionId: createdSessionId);
          return false;
        }
      }

      _traceOutgoingAttempt(attemptId, 'rtc_join_start');
      if (rtcProvider == 'livekit') {
        await _joinLiveKitRoom(
          serverUrl: serverUrl!,
          token: token,
          callType: type,
          isStillActive: () => _isOutgoingAttemptActive(attemptId),
        );
      } else {
        await _initEngineWithWebRetry();
        _traceOutgoingAttempt(attemptId, 'rtc_engine_ready');

        if (type == CallType.video) {
          await _engine!.enableVideo();
          if (!_agoraPreviewStarted) {
            try {
              await _engine!.startPreview();
              _agoraPreviewStarted = true;
            } catch (previewError) {
              debugPrint('[CallService] startPreview error: $previewError');
              if (previewError is AgoraRtcException &&
                  previewError.code == -2) {
                if (Platform.isMacOS) {
                  state =
                      state.copyWith(errorMessage: _genericCallFailureText());
                } else {
                  state =
                      state.copyWith(errorMessage: _genericCallFailureText());
                }
              }
            }
          }
        }

        final isVideo = type == CallType.video;
        await _joinAgoraChannelAndWait(
          token: token,
          channelName: channelName,
          uid: agoraUid > 0 ? agoraUid : 0,
          isVideo: isVideo,
        );
        _traceOutgoingAttempt(attemptId, 'rtc_join_requested');
        await _applySpeakerphoneEnabled(isVideo);
        debugPrint(
          '[CallService] Caller joined Agora channel callId=$callId '
          'channel=$channelName uid=$agoraUid',
        );
      }

      if (!_isOutgoingAttemptActive(attemptId)) {
        await _leaveChannel();
        await _cancelCallById(createdCallId, sessionId: createdSessionId);
        return false;
      }

      rtcJoined = true;
      _traceOutgoingAttempt(attemptId, 'rtc_setup_complete');
      final readyData = await _reportCallMediaReady(
        callId: callId,
        sessionId: createdSessionId,
      );
      if (!_isOutgoingAttemptActive(attemptId)) {
        await _leaveChannel();
        await _endCallById(
          createdCallId,
          'connection_cancelled',
          sessionId: createdSessionId,
        );
        return false;
      }
      final readyRevision = _revisionFromPayload(readyData);
      if (readyRevision != null && state.callInfo != null) {
        state = state.copyWith(
          callInfo: state.callInfo!.copyWith(revision: readyRevision),
        );
      }
      WakelockPlus.enable();
      if (readyData['status']?.toString() == 'connected') {
        handleCallConnected(readyData);
      }
      if (state.state == CallState.outgoing &&
          state.callInfo?.callId == callId) {
        if (!kIsWeb && !kSilentCallQaMode) {
          await _outgoingCallTone.start();
        }
        _startOutgoingCallTimeout(callId);
      }

      return true;
    } catch (e, stack) {
      debugPrint('[CallService] Start call error: $e\n$stack');

      await _outgoingCallTone.stop();
      await _leaveChannel();
      if (rtcJoined) {
        await _endCallById(
          createdCallId,
          'rtc_error',
          sessionId: createdSessionId,
        );
      } else {
        await _cancelCallById(createdCallId, sessionId: createdSessionId);
      }

      if (!_isOutgoingAttemptActive(attemptId)) return false;

      final errorMessage = _classifyError(e, 'call');
      _failOutgoingAttempt(attemptId, errorMessage);
      return false;
    }
  }

  Future<void> _ensureOutgoingLocalPreview(
    int attemptId,
    String provider,
  ) async {
    if (!_isOutgoingAttemptActive(attemptId) ||
        state.callInfo?.type != CallType.video) {
      return;
    }
    if (provider == 'livekit') {
      _liveKitLocalVideoTrack ??= await lk.LocalVideoTrack.createCameraTrack();
      if (!_isOutgoingAttemptActive(attemptId)) {
        await _liveKitLocalVideoTrack?.stop();
        _liveKitLocalVideoTrack = null;
        return;
      }
      state = state.copyWith(isVideoEnabled: true);
    } else {
      await _initEngineWithWebRetry();
      if (!_isOutgoingAttemptActive(attemptId)) return;
      await _engine!.enableVideo();
      await _engine!.startPreview();
      _agoraPreviewStarted = true;
    }
    _traceOutgoingAttempt(attemptId, 'local_preview_started');
  }

  int? _callIdFromPayload(Map<String, dynamic> data) {
    return _intValue(data['call_id'] ?? data['callId']);
  }

  String? _sessionIdFromPayload(Map<String, dynamic> data) {
    final value = _firstStringValue(data, ['session_id', 'sessionId']);
    return value.isEmpty ? null : value;
  }

  int? _revisionFromPayload(Map<String, dynamic> data) {
    return _intValue(data['revision']);
  }

  bool _matchesCurrentCall(
    int? eventCallId, {
    String? eventSessionId,
    int? eventRevision,
    bool requireSession = false,
  }) {
    final current = state.callInfo;
    return callEventMatchesCurrentCall(
      currentCallId: current?.callId,
      eventCallId: eventCallId,
      currentSessionId: requireSession ? current?.sessionId : null,
      eventSessionId: eventSessionId,
      currentRevision: current?.revision ?? 0,
      eventRevision: eventRevision,
    );
  }

  Future<void> _handleRemoteCallEnded(Map<String, dynamic>? payload) async {
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(
      eventCallId,
      eventSessionId: payload == null ? null : _sessionIdFromPayload(payload),
      eventRevision: payload == null ? null : _revisionFromPayload(payload),
      requireSession: true,
    )) {
      debugPrint(
        '[CallService] Ignoring call_ended for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      if (eventCallId == null && state.isInCall) {
        unawaited(syncActiveCallStateWithServer());
      }
      return;
    }

    final reason = payload?['reason']?.toString();
    await _finishCallLocally(
      reason == null || reason.isEmpty ? 'remote_hangup' : reason,
    );
  }

  CallInfo? _incomingCallInfoFromPayload(Map<String, dynamic> data) {
    final callId = _callIdFromPayload(data);
    final channelName = _firstStringValue(data, ['channel_name', 'room_name']);
    final roomName = _firstStringValue(data, ['room_name', 'channel_name']);
    final rtcProvider = _providerFromData(data);
    final serverUrl = _serverUrlFromData(data);
    final callerId = data['caller_id']?.toString();
    final callerName = data['caller_name']?.toString();

    if (channelName.isEmpty ||
        callerId == null ||
        callerId.isEmpty ||
        callerName == null) {
      return null;
    }

    final callerAvatarRaw = data['caller_avatar']?.toString();
    final callerAvatar = (callerAvatarRaw != null && callerAvatarRaw.isNotEmpty)
        ? ApiConfig.getMediaUrl(callerAvatarRaw)
        : null;
    final callType =
        data['call_type'] == 'video' ? CallType.video : CallType.voice;

    return CallInfo(
      callId: callId,
      sessionId: _sessionIdFromPayload(data),
      revision: _revisionFromPayload(data) ?? 0,
      channelName: channelName,
      roomName: roomName.isNotEmpty ? roomName : channelName,
      rtcProvider: rtcProvider,
      serverUrl: serverUrl,
      identity: _firstStringValue(data, ['identity', 'livekit_identity']),
      remoteUserId: callerId,
      remoteName: callerName,
      remoteAvatar: callerAvatar,
      targetDeviceSessionId: _firstStringValue(
        data,
        ['target_device_session_id', 'callee_device_session_id'],
      ),
      type: callType,
      isOutgoing: false,
    );
  }

  Future<Map<String, dynamic>> _hydrateIncomingCallPayload(
    Map<String, dynamic> payload,
  ) async {
    final callId = _callIdFromPayload(payload);
    if (callId == null || callId <= 0) return payload;
    try {
      final response = await _api.get<Map<String, dynamic>>('/call/active');
      final active = response.data;
      if (!response.isSuccess ||
          active == null ||
          active['active'] != true ||
          _intValue(active['call_id']) != callId) {
        return payload;
      }
      _observeServerClock(active);
      final hydrated = <String, dynamic>{...payload};
      void fill(String key, dynamic value) {
        final current = hydrated[key]?.toString().trim() ?? '';
        if (current.isEmpty && value != null) hydrated[key] = value;
      }

      fill('channel_name', active['channel_name'] ?? active['room_name']);
      fill('room_name', active['room_name'] ?? active['channel_name']);
      fill('session_id', active['session_id']);
      fill('revision', active['revision']);
      fill('provider', active['provider'] ?? active['rtc_provider']);
      fill('rtc_provider', active['rtc_provider'] ?? active['provider']);
      fill('server_url', active['server_url']);
      fill('caller_id', active['remote_id']);
      fill('caller_name', active['remote_name']);
      fill('caller_avatar', active['remote_avatar']);
      fill('call_type', active['call_type']);
      fill(
        'target_device_session_id',
        active['target_device_session_id'],
      );
      fill('server_time_ms', active['server_time_ms']);
      hydrated['_business_data_incomplete'] = false;
      debugPrint('[CallService] Hydrated incoming call payload: $callId');
      return hydrated;
    } catch (e) {
      debugPrint('[CallService] Hydrate incoming call payload failed: $e');
      return payload;
    }
  }

  void _setIncomingCallState(CallInfo callInfo) {
    final generation = ++_outgoingAttemptGeneration;
    state = state.copyWith(
      state: CallState.incoming,
      callInfo: callInfo.copyWith(generation: generation),
      isVideoEnabled: callInfo.type == CallType.video,
      // 语音来电默认使用听筒；视频通话仍由视频模式使用扬声器。
      isSpeakerOn: callInfo.type == CallType.video,
      isRemoteVideoEnabled: callInfo.type != CallType.video,
      isMuted: kSilentCallQaMode,
    );

    _startIncomingCallTimeout(callInfo.callId);
    unawaited(_preloadForIncoming());
  }

  Future<void> handleIncomingCall(Map<String, dynamic> data) async {
    final callId = _callIdFromPayload(data);

    if (!await _incomingCallTargetsThisDevice(data)) {
      debugPrint(
        '[CallService] Ignoring incoming call for another device: $callId',
      );
      return;
    }
    _observeServerClock(data);

    if (incomingCallIsExpired(
      data['expires_at']?.toString(),
      DateTime.now(),
    )) {
      debugPrint('[CallService] Ignoring expired incoming call: $callId');
      if (callId != null) {
        await _rejectCallById(callId, 'timeout');
      }
      return;
    }

    // A different incoming call is itself evidence that the server may have
    // released the old instance. Never emit busy from local memory alone.
    if (state.isInCall) {
      final currentCallId = state.callInfo?.callId;
      if (callId != null && currentCallId == callId) {
        debugPrint('[CallService] Duplicate incoming call ignored: $callId');
        return;
      }

      var serverConfirmsOldCall = false;
      try {
        final activeResponse =
            await _api.get<Map<String, dynamic>>('/call/active');
        if (activeResponse.isSuccess && activeResponse.data != null) {
          final active = activeResponse.data!['active'] == true;
          final activeCallId = _intValue(activeResponse.data!['call_id']);
          serverConfirmsOldCall = serverConfirmsExistingCallBeforeBusy(
            localCallId: currentCallId,
            incomingCallId: callId,
            serverActive: active,
            serverCallId: activeCallId,
          );
        }
      } catch (error) {
        debugPrint(
          '[CallService] Active-call check before incoming failed: $error',
        );
      }
      if (serverConfirmsOldCall) {
        if (callId != null) {
          await _rejectCallById(
            callId,
            'busy',
            sessionId: _sessionIdFromPayload(data),
          );
        }
        return;
      }
      debugPrint(
        '[CallService] Clearing stale local call before incoming call_id=$callId',
      );
      await _finishCallLocally('stale_local_state');
    }

    var normalizedData = data;
    var callInfo = _incomingCallInfoFromPayload(normalizedData);
    if (callInfo == null ||
        _truthyValue(normalizedData['_business_data_incomplete'])) {
      normalizedData = await _hydrateIncomingCallPayload(normalizedData);
      callInfo = _incomingCallInfoFromPayload(normalizedData);
    }
    if (callInfo == null) {
      debugPrint(
        '[CallService] handleIncomingCall: invalid payload ${_sensitiveMapSummary(normalizedData)}',
      );
      return;
    }

    final isBlocked = await _isBlockedByCurrentUser(callInfo.remoteUserId);
    if (isBlocked) {
      debugPrint(
        '[CallService] Incoming call auto rejected due to block: ${callInfo.remoteUserId}',
      );
      if (callInfo.callId != null) {
        await _rejectCallById(callInfo.callId!, 'blocked');
      }
      return;
    }

    _setIncomingCallState(callInfo);

    if (kIsWeb) {
      debugPrint('[CallService] Web: showing in-app IncomingCallPage');
      onIncomingCall?.call(callInfo);
      return;
    }

    if (Platform.isIOS) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isForeground = lifecycleState == AppLifecycleState.resumed ||
          lifecycleState == AppLifecycleState.inactive;

      debugPrint(
        '[CallService] iOS lifecycleState: $lifecycleState, isForeground: $isForeground, isSimulator: $_isSimulator',
      );

      if (isForeground && onIncomingCall != null && !_isSimulator) {
        debugPrint(
          '[CallService] iOS foreground: showing in-app IncomingCallPage',
        );
        onIncomingCall?.call(callInfo);
      } else {
        debugPrint('[CallService] iOS background/locked: showing CallKit UI');
        try {
          await _showCallKit(callInfo);
          if (_isSimulator && onIncomingCall != null) {
            debugPrint(
              '[CallService] iOS simulator: also showing in-app IncomingCallPage',
            );
            onIncomingCall?.call(callInfo);
          }
        } catch (e) {
          debugPrint(
            '[CallService] iOS CallKit failed: $e, falling back to in-app UI',
          );
          onIncomingCall?.call(callInfo);
        }
      }
      return;
    }

    if (Platform.isAndroid) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isForeground = lifecycleState == AppLifecycleState.resumed ||
          lifecycleState == AppLifecycleState.inactive;

      debugPrint(
        '[CallService] Android lifecycleState: $lifecycleState, isForeground: $isForeground',
      );

      if (isForeground && onIncomingCall != null) {
        debugPrint(
          '[CallService] Android foreground: showing in-app IncomingCallPage',
        );
        onIncomingCall?.call(callInfo);
      } else {
        debugPrint(
          '[CallService] Android background/locked: showing system full-screen incoming',
        );
        try {
          await _showCallKit(callInfo);
        } catch (e) {
          debugPrint(
            '[CallService] Android CallKit failed: $e, trying in-app UI',
          );
          onIncomingCall?.call(callInfo);
        }
      }
      return;
    }

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      debugPrint('[CallService] Desktop: showing in-app IncomingCallPage');
      onIncomingCall?.call(callInfo);
    }
  }

  Map<String, dynamic> _incomingPayloadFromCallInfo(CallInfo callInfo) {
    return <String, dynamic>{
      'type': 'incoming_call',
      'call_id': callInfo.callId,
      'callId': callInfo.callId,
      'session_id': callInfo.sessionId ?? '',
      'sessionId': callInfo.sessionId ?? '',
      'revision': callInfo.revision,
      'channel_name': callInfo.channelName,
      'room_name': callInfo.roomName,
      'provider': callInfo.rtcProvider,
      'rtc_provider': callInfo.rtcProvider,
      'server_url': callInfo.serverUrl ?? '',
      'identity': callInfo.identity ?? '',
      'caller_id': callInfo.remoteUserId,
      'caller_name': callInfo.remoteName,
      'caller_avatar': callInfo.remoteAvatar ?? '',
      'target_device_session_id': callInfo.targetDeviceSessionId ?? '',
      'call_type': callInfo.type == CallType.video ? 'video' : 'voice',
      'is_video': callInfo.type == CallType.video,
    };
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return _asStringKeyMap(decoded);
      } catch (_) {
        return null;
      }
    }
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String _sensitiveMapSummary(dynamic value) {
    final map = _asStringKeyMap(value);
    if (map == null || map.isEmpty) {
      return 'keys=-';
    }
    final nested = _asStringKeyMap(map['data']) ?? const <String, dynamic>{};
    final keys = {...map.keys, ...nested.keys}
        .map((key) => key.toString())
        .toList()
      ..sort();
    final type = map['type']?.toString() ?? nested['type']?.toString() ?? '-';
    return 'type=$type keys=${keys.join(',')}';
  }

  Map<String, dynamic>? _incomingPayloadFromCallKitData(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return null;

    final extra = _asStringKeyMap(data['extra']) ?? <String, dynamic>{};
    final payload = <String, dynamic>{...extra};

    payload['type'] = payload['type'] ?? 'incoming_call';
    payload['call_id'] = payload['call_id'] ??
        payload['callId'] ??
        data['call_id'] ??
        data['callId'];
    payload['channel_name'] = payload['channel_name'] ??
        data['channel_name'] ??
        payload['room_name'] ??
        data['room_name'];
    payload['room_name'] =
        payload['room_name'] ?? data['room_name'] ?? payload['channel_name'];
    payload['provider'] = payload['provider'] ?? data['provider'];
    payload['rtc_provider'] = payload['rtc_provider'] ?? data['rtc_provider'];
    payload['server_url'] = payload['server_url'] ?? data['server_url'];
    payload['identity'] = payload['identity'] ?? data['identity'];
    payload['caller_id'] = payload['caller_id'] ?? data['caller_id'];
    payload['caller_name'] =
        payload['caller_name'] ?? data['nameCaller'] ?? data['caller_name'];
    payload['caller_avatar'] =
        payload['caller_avatar'] ?? data['avatar'] ?? data['caller_avatar'];

    final type = payload['call_type'] ?? data['call_type'];
    final isVideo =
        _truthyValue(payload['is_video']) || _intValue(data['type']) == 1;
    payload['call_type'] =
        type?.toString() == 'video' || isVideo ? 'video' : 'voice';
    payload['is_video'] = payload['call_type'] == 'video';

    final hasRequiredFields = payload['call_id'] != null &&
        payload['channel_name']?.toString().isNotEmpty == true &&
        payload['caller_id']?.toString().isNotEmpty == true &&
        payload['caller_name']?.toString().isNotEmpty == true;
    final canAttemptHydration = payload['call_id'] != null &&
        _truthyValue(payload['_business_data_incomplete']);
    return hasRequiredFields || canAttemptHydration ? payload : null;
  }

  void _rememberCallKitUuidFromData(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return;
    final uuid = _firstStringValue(data, ['id', 'uuid']);
    final callId = _callKitEventCallId(data);
    if (uuid.isEmpty || callId == null || callId <= 0) return;
    _callKitUuidByCallId[callId] = uuid;
    _callIdByCallKitUuid[uuid] = callId;
    final sessionId = _callKitEventSessionId(data)?.trim() ?? '';
    if (sessionId.isNotEmpty) {
      _callKitSessionByUuid[uuid] = sessionId;
    }
  }

  String? _callKitUuidForCall(int? callId, {dynamic eventBody}) {
    final eventUuid = _callKitEventUuid(eventBody);
    if (eventUuid != null) return eventUuid;
    if (callId == null || callId <= 0) return null;
    return _callKitUuidByCallId[callId];
  }

  int? _callKitEventCallId(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return null;
    final extra = _asStringKeyMap(data['extra']) ?? <String, dynamic>{};
    final embeddedCallId = _intValue(
      extra['call_id'] ?? extra['callId'] ?? data['call_id'] ?? data['callId'],
    );
    if (embeddedCallId != null) return embeddedCallId;
    final uuid = _firstStringValue(data, ['id', 'uuid']);
    return uuid.isEmpty ? null : _callIdByCallKitUuid[uuid];
  }

  String? _callKitEventUuid(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return null;
    final uuid = _firstStringValue(data, ['id', 'uuid']);
    return uuid.isEmpty ? null : uuid;
  }

  bool _callKitEventIsAccepted(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return false;
    return _truthyValue(data['accepted']) || _truthyValue(data['isAccepted']);
  }

  Future<bool> _restoreIncomingCallFromCallKitEvent(dynamic rawData) async {
    final eventCallId = _callKitEventCallId(rawData);
    final eventUuid = _callKitEventUuid(rawData);
    final eventSessionId = _callKitEventSessionId(rawData);
    final eventRevision = _callKitEventRevision(rawData);

    if (state.state == CallState.incoming && state.callInfo != null) {
      if (_matchesCurrentCall(
        eventCallId,
        eventSessionId: eventSessionId,
        eventRevision: eventRevision,
        requireSession: true,
      )) {
        _rememberCallKitUuidFromData(rawData);
        return true;
      }
      if (eventCallId != null) {
        await _rejectCallById(eventCallId, 'busy');
      }
      if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
        await _endSystemCall(eventUuid);
      }
      return false;
    }
    if (state.state == CallState.connecting ||
        state.state == CallState.connected ||
        state.state == CallState.reconnecting) {
      if (!_matchesCurrentCall(
        eventCallId,
        eventSessionId: eventSessionId,
        eventRevision: eventRevision,
        requireSession: true,
      )) {
        if (eventCallId != null) {
          await _rejectCallById(eventCallId, 'busy');
        }
        if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
          await _endSystemCall(eventUuid);
        }
        return false;
      }
      _rememberCallKitUuidFromData(rawData);
      return true;
    }

    var payload = _incomingPayloadFromCallKitData(rawData);
    if (payload == null) {
      debugPrint(
        '[CallService] Cannot restore incoming call event ${_sensitiveMapSummary(rawData)}',
      );
      if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
        await _endSystemCall(eventUuid);
      }
      return false;
    }

    if (!await _incomingCallTargetsThisDevice(payload)) {
      debugPrint('[CallService] CallKit event belongs to another device');
      if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
        await _endSystemCall(eventUuid);
      }
      return false;
    }

    var callInfo = _incomingCallInfoFromPayload(payload);
    if (callInfo == null ||
        _truthyValue(payload['_business_data_incomplete'])) {
      payload = await _hydrateIncomingCallPayload(payload);
      callInfo = _incomingCallInfoFromPayload(payload);
    }
    if (callInfo == null) {
      debugPrint(
        '[CallService] Invalid CallKit incoming payload ${_sensitiveMapSummary(payload)}',
      );
      if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
        await _endSystemCall(eventUuid);
      }
      return false;
    }

    if (state.isInCall) {
      if (state.callInfo?.callId == callInfo.callId &&
          callInfo.callId != null) {
        _rememberCallKitUuidFromData(rawData);
        return true;
      }
      if (callInfo.callId != null) {
        await _rejectCallById(callInfo.callId!, 'busy');
      }
      if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
        await _endSystemCall(eventUuid);
      }
      return false;
    }

    final isBlocked = await _isBlockedByCurrentUser(callInfo.remoteUserId);
    if (isBlocked) {
      if (callInfo.callId != null) {
        await _rejectCallById(callInfo.callId!, 'blocked');
      }
      return false;
    }

    _rememberCallKitUuidFromData(rawData);
    _setIncomingCallState(callInfo);
    return true;
  }

  Future<void> handleNativeCallKitEvent(
    String event,
    Map<String, dynamic> body,
  ) async {
    debugPrint(
      '[CallService] Native CallKit event=$event ${_sensitiveMapSummary(body)}',
    );
    switch (event) {
      case 'incoming':
        await _restoreIncomingCallFromCallKitEvent(body);
        break;
      case 'accept':
        await _handleCallKitAccept(body);
        break;
      case 'decline':
        await _handleCallKitReject(body, 'decline');
        break;
      case 'timeout':
        await _handleCallKitReject(body, 'timeout');
        break;
      case 'ended':
        await _handleCallKitEnd(body);
        break;
      case 'audioActivated':
        if (_matchesCurrentCall(
          _callKitEventCallId(body),
          eventSessionId: _callKitEventSessionId(body),
          eventRevision: _callKitEventRevision(body),
          requireSession: true,
        )) {
          await _applySpeakerphoneEnabled(
            state.callInfo?.type == CallType.video || state.isSpeakerOn,
          );
        }
        break;
      default:
        debugPrint('[CallService] Unknown native CallKit event: $event');
    }
  }

  Future<bool> restoreIncomingCallFromSystem() async {
    // 进程可能在系统来电界面展示期间被回收，恢复时以 CallKit 活跃列表重建 Dart 状态。
    if (_isDisposed || _isRestoringSystemIncomingCall) return false;
    if (kIsWeb || _isSimulator || !(Platform.isIOS || Platform.isAndroid)) {
      return false;
    }

    if (state.state == CallState.incoming && state.callInfo != null) {
      return true;
    }
    if (state.state == CallState.connecting ||
        state.state == CallState.connected ||
        state.state == CallState.reconnecting) {
      return true;
    }

    _isRestoringSystemIncomingCall = true;
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      final calls = activeCalls is List ? activeCalls : const [];
      debugPrint('[CallService] Active system calls: count=${calls.length}');

      for (final rawCall in calls) {
        final call = _asStringKeyMap(rawCall);
        if (call == null) continue;

        final isAccepted = _callKitEventIsAccepted(call);

        final payload = _incomingPayloadFromCallKitData(call);
        if (payload == null) {
          debugPrint(
            '[CallService] Cannot restore CallKit payload ${_sensitiveMapSummary(call)}',
          );
          continue;
        }

        _rememberCallKitUuidFromData(call);
        debugPrint('[CallService] Restoring incoming call from system UI');
        if (isAccepted) {
          final restored = await _restoreIncomingCallFromCallKitEvent(call);
          if (!restored) continue;
          debugPrint('[CallService] Restored accepted system call, joining');
          await _handleCallKitAccept(call);
          return state.state == CallState.connecting ||
              state.state == CallState.connected ||
              state.state == CallState.reconnecting;
        }
        await handleIncomingCall(payload);
        return state.state == CallState.incoming && state.callInfo != null;
      }
    } catch (e) {
      debugPrint('[CallService] restoreIncomingCallFromSystem error: $e');
    } finally {
      _isRestoringSystemIncomingCall = false;
    }

    return false;
  }

  Timer? _incomingCallTimer;

  void _startIncomingCallTimeout(int? callId) {
    _incomingCallTimer?.cancel();
    _incomingCallTimer = Timer(const Duration(seconds: 30), () {
      if (_isDisposed) return;
      if (state.state == CallState.incoming &&
          state.callInfo?.callId == callId) {
        debugPrint('[CallService] Incoming call timeout, auto rejecting');
        rejectCall(reason: 'timeout');
      }
    });
  }

  void _cancelIncomingCallTimeout() {
    _incomingCallTimer?.cancel();
    _incomingCallTimer = null;
  }

  Timer? _connectionTimer;

  void _startOutgoingCallTimeout(int? callId) {
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = Timer(const Duration(seconds: 30), () {
      if (_isDisposed) return;
      if (state.state != CallState.outgoing ||
          state.callInfo?.callId != callId) {
        return;
      }

      debugPrint('[CallService] Outgoing call timeout, cancelling call');
      state = state.copyWith(errorMessage: _genericCallFailureText());
      unawaited(cancelCall());
    });
  }

  void _cancelOutgoingCallTimeout() {
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = null;
  }

  void _startConnectionTimeout() {
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(seconds: 20), () {
      if (_isDisposed) return;
      if (state.state == CallState.connecting ||
          state.state == CallState.outgoing) {
        debugPrint('[CallService] Connection timeout, ending call');
        state = state.copyWith(errorMessage: _genericCallFailureText());
        endCall(reason: 'connection_timeout');
      }
    });
  }

  void _cancelConnectionTimeout() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
  }

  void _beginReconnect(String source) {
    if (_isDisposed || state.callInfo == null) return;
    if (state.state != CallState.connected &&
        state.state != CallState.reconnecting) {
      return;
    }
    _reconnectDeadline ??= DateTime.now().add(const Duration(seconds: 20));
    final remaining = callReconnectSecondsRemaining(
      _reconnectDeadline!,
      DateTime.now(),
    );
    if (remaining <= 0) {
      unawaited(endCall(reason: 'reconnect_timeout'));
      return;
    }
    state = state.copyWith(
      state: CallState.reconnecting,
      reconnectSecondsRemaining: remaining,
    );
    debugPrint(
      '[CallService] Reconnecting source=$source remaining=$remaining '
      'callId=${state.callInfo?.callId}',
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed || state.state != CallState.reconnecting) {
        _cancelReconnectTimer();
        return;
      }
      final seconds = callReconnectSecondsRemaining(
        _reconnectDeadline!,
        DateTime.now(),
      );
      if (seconds <= 0) {
        _cancelReconnectTimer();
        unawaited(endCall(reason: 'reconnect_timeout'));
        return;
      }
      state = state.copyWith(reconnectSecondsRemaining: seconds);
    });
  }

  void _recoverReconnect(String source) {
    if (_isDisposed || state.state != CallState.reconnecting) return;
    debugPrint('[CallService] Reconnected source=$source');
    _markCallConnected(source: source);
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectDeadline = null;
  }

  Future<Map<String, dynamic>> _reportCallMediaReady({
    required int callId,
    String? sessionId,
    CancelToken? cancelToken,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/call/connected',
      data: <String, dynamic>{
        'call_id': callId,
        if (sessionId?.trim().isNotEmpty == true)
          'session_id': sessionId!.trim(),
      },
      cancelToken: cancelToken,
      retryNetworkErrors: false,
    );
    if (!response.isSuccess || response.data == null) {
      throw StateError(response.message ?? 'media ready was rejected');
    }
    _observeServerClock(response.data!);
    return response.data!;
  }

  void _markCallConnected({
    int? remoteUid,
    DateTime? connectedAt,
    String source = 'unknown',
  }) {
    if (_isDisposed || state.callInfo == null) return;

    final currentState = state.state;
    if (currentState != CallState.outgoing &&
        currentState != CallState.connecting &&
        currentState != CallState.connected &&
        currentState != CallState.reconnecting) {
      return;
    }

    final callInfo = state.callInfo!;
    final wasConnected = currentState == CallState.connected ||
        currentState == CallState.reconnecting;
    _cancelReconnectTimer();
    _cancelOutgoingCallTimeout();
    _cancelConnectionTimeout();

    final nextInfo = callInfo.copyWith(
      remoteUid: remoteUid ?? callInfo.remoteUid,
      connectTime: callInfo.connectTime ?? connectedAt ?? DateTime.now(),
    );

    state = state.copyWith(
      state: CallState.connected,
      reconnectSecondsRemaining: 0,
      isRemoteVideoEnabled:
          callInfo.type == CallType.video ? state.isRemoteVideoEnabled : true,
      callInfo: nextInfo,
    );
    final callKitUuid = _callKitUuidForCall(callInfo.callId);
    if (callKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      // Android CallKit uses its own looping Ringtone. Explicitly marking the
      // system call connected stops that ringtone on ROMs that do not stop it
      // reliably after the accept callback alone.
      unawaited(_markSystemCallConnected(callKitUuid));
    }
    _startConnectedClock(nextInfo);

    unawaited(_stopRingbackAndRestoreConnectedRoute(nextInfo));

    debugPrint(
      '[CallService] Mark call connected source=$source '
      'callId=${nextInfo.callId} remoteUid=${remoteUid ?? nextInfo.remoteUid}',
    );

    if (!wasConnected) {
      final callKitUuid = _callKitUuidForCall(nextInfo.callId);
      if (callKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
        unawaited(
          FlutterCallkitIncoming.setCallConnected(callKitUuid).catchError(
            (Object error) {
              debugPrint('[CallService] setCallConnected error: $error');
            },
          ),
        );
      }
      onCallConnected?.call();
      _startCallTimer();
      _startCallHeartbeatTimer(nextInfo.callId);
    }
  }

  Future<void> _stopRingbackAndRestoreConnectedRoute(CallInfo callInfo) async {
    await _outgoingCallTone.stop();
    if (_isDisposed ||
        kIsWeb ||
        state.state != CallState.connected ||
        state.callInfo?.callId != callInfo.callId) {
      return;
    }

    // Ringback is intentionally sent to the loudspeaker. Restore the route the
    // active call expects as soon as the remote party connects.
    await _applySpeakerphoneEnabled(
      callInfo.type == CallType.video || state.isSpeakerOn,
    );
  }

  Future<bool> acceptCall() async {
    debugPrint(
      '[CallService] acceptCall called, state=${state.state}, callInfo=${state.callInfo != null}',
    );

    if (_isAcceptingCall) {
      debugPrint('[CallService] acceptCall already in progress');
      return false;
    }

    if (state.state != CallState.incoming || state.callInfo == null) {
      debugPrint(
        '[CallService] acceptCall failed: invalid state or no callInfo',
      );
      state = state.copyWith(errorMessage: _genericCallFailureText());
      return false;
    }

    // 必须在切换 RTC 音频会话前完成铃声停止。由 CallService 持有播放器，
    // 即使来电页面已被系统 CallKit 或导航切换销毁，也能可靠停止。
    await _incomingCallTone.stop();

    final currentInfo = state.callInfo!;
    final attempt = _AcceptAttempt(
      id: ++_acceptAttemptGeneration,
      callId: currentInfo.callId ?? 0,
      sessionId: currentInfo.sessionId,
      callKitUuid: _callKitUuidForCall(currentInfo.callId),
    );
    _activeAcceptAttempt = attempt;
    _isAcceptingCall = true;
    _cancelIncomingCallTimeout();
    state = state.copyWith(state: CallState.connecting);
    debugPrint('[CallService] State changed to connecting immediately');

    attempt.timer = Timer(const Duration(seconds: 15), () {
      if (!_isAcceptAttemptActive(attempt) ||
          attempt.resolutionResult.isCompleted) {
        return;
      }
      debugPrint('[CallService] Accept attempt ${attempt.id} timed out');
      attempt.cancelToken.cancel('answer_timeout');
      unawaited(
        _rollbackAcceptAttempt(
          attempt,
          reason: 'answer_timeout',
          errorMessage: _callServiceText(
            zhCN: '接听超时，请重试',
            zhTW: '接聽逾時，請重試',
            en: 'Answer timed out. Please try again.',
          ),
        ).whenComplete(() {
          if (!attempt.resolutionResult.isCompleted) {
            attempt.resolutionResult.complete(false);
          }
        }),
      );
    });

    final operation = _runAcceptCall(attempt);
    final result = await Future.any<bool>([
      operation,
      attempt.resolutionResult.future,
    ]);
    attempt.timer?.cancel();
    // A call_connected WebSocket event can complete resolutionResult before
    // the in-flight /call/connected request returns. Keep successful attempts
    // owned by _runAcceptCall until that request finishes; otherwise its next
    // active-attempt check would misclassify the same connected call as stale.
    // Failed attempts have already rolled back (or must be released here).
    if (!result && identical(_activeAcceptAttempt, attempt)) {
      _activeAcceptAttempt = null;
      _isAcceptingCall = false;
    }
    return result;
  }

  bool _isAcceptAttemptActive(_AcceptAttempt attempt) {
    // call_connected can arrive over WebSocket before /call/connected returns.
    // That is a successful completion of this same accept attempt, not a
    // cancellation. Keep the attempt valid until its media-ready request has
    // returned so IncomingCallPage can leave the "answering" state.
    final callStateStillOwnedByAttempt = state.state == CallState.connecting ||
        state.state == CallState.connected;
    return !_isDisposed &&
        identical(_activeAcceptAttempt, attempt) &&
        !attempt.cancelToken.isCancelled &&
        state.callInfo?.callId == attempt.callId &&
        callStateStillOwnedByAttempt;
  }

  Future<bool> _acceptAttemptNoLongerActive(_AcceptAttempt attempt) async {
    if (_isAcceptAttemptActive(attempt)) return false;
    if (attempt.rollbackStarted && !attempt.rollbackComplete.isCompleted) {
      await attempt.rollbackComplete.future;
    }
    return true;
  }

  Future<bool> _runAcceptCall(_AcceptAttempt attempt) async {
    await _waitForLocalCleanup();
    if (await _acceptAttemptNoLongerActive(attempt)) return false;

    final originalCallId = attempt.callId;
    var callType = state.callInfo!.type;
    var currentInfo = state.callInfo!;
    final acceptedCallId = attempt.callId;
    var acceptedSessionId = attempt.sessionId;
    var acceptedSuccessfully = false;

    try {
      final permittedType = await _requestPermissions(
        callType,
        allowVideoDowngrade: true,
        userInitiated: true,
      );
      if (await _acceptAttemptNoLongerActive(attempt)) return false;
      if (permittedType == null) {
        debugPrint('[CallService] Permission denied');
        await _rollbackAcceptAttempt(
          attempt,
          reason: 'permission_denied',
          errorMessage: state.errorMessage ?? _genericCallFailureText(),
        );
        return false;
      }
      if (permittedType != callType) {
        callType = permittedType;
        currentInfo = currentInfo.copyWith(type: permittedType);
        state = state.copyWith(
          callInfo: currentInfo,
          isVideoEnabled: false,
        );
      }
      await _loadConfigIfNeeded(currentInfo.rtcProvider);
      if (await _acceptAttemptNoLongerActive(attempt)) return false;
      debugPrint('[CallService] Permissions & config ready');

      if (!_isEnabled) {
        await _rollbackAcceptAttempt(
          attempt,
          reason: 'media_disabled',
          errorMessage: _mediaServiceUnavailableText(),
        );
        return false;
      }

      debugPrint('[CallService] Starting accept API...');

      final acceptRequestStarted = DateTime.now();
      final response = await _api.post<Map<String, dynamic>>(
        '/call/accept',
        data: {
          'call_id': originalCallId,
          if (acceptedSessionId?.trim().isNotEmpty == true)
            'session_id': acceptedSessionId!.trim(),
        },
        cancelToken: attempt.cancelToken,
        receiveTimeout: const Duration(seconds: 15),
        retryNetworkErrors: false,
      );
      if (await _acceptAttemptNoLongerActive(attempt)) return false;

      if (!response.isSuccess || response.data == null) {
        debugPrint('[CallService] Accept API failed: ${response.message}');
        final terminalReason = response.data?['reason']?.toString() ?? '';
        if (response.code == 409 &&
            (terminalReason == 'call_replaced' ||
                terminalReason == 'device_not_selected')) {
          await _finishCallLocally(terminalReason);
          return false;
        }
        await _rollbackAcceptAttempt(
          attempt,
          reason: 'answer_failed',
          errorMessage: _genericCallFailureText(),
        );
        return false;
      }
      final acceptResponseReceived = DateTime.now();
      debugPrint('[CallService] Accept API success');
      attempt.serverAccepted = true;

      final data = response.data!;
      _observeServerClock(
        data,
        localRequestStarted: acceptRequestStarted,
        localResponseReceived: acceptResponseReceived,
      );
      acceptedSessionId = _sessionIdFromPayload(data) ?? acceptedSessionId;
      attempt.sessionId = acceptedSessionId;
      final rtcProvider = _providerFromData(
        data,
        fallback: currentInfo.rtcProvider,
      );
      final responseChannel =
          _firstStringValue(data, ['channel_name', 'room_name']);
      final responseRoom =
          _firstStringValue(data, ['room_name', 'channel_name']);
      final channelName = responseChannel.isNotEmpty
          ? responseChannel
          : currentInfo.channelName;
      final roomName =
          responseRoom.isNotEmpty ? responseRoom : currentInfo.roomName;
      final token = data['token']?.toString() ?? '';
      final serverUrl = _serverUrlFromData(data) ?? currentInfo.serverUrl;
      final agoraUid = data['agora_uid'] is int
          ? data['agora_uid'] as int
          : int.tryParse(data['agora_uid']?.toString() ?? '') ?? 0;

      if (channelName.isEmpty || token.isEmpty) {
        debugPrint('[CallService] Accept call: channelName or token is empty');
        await _rollbackAcceptAttempt(
          attempt,
          reason: 'rtc_error',
          errorMessage: _genericCallFailureText(),
        );
        return false;
      }
      if (rtcProvider == 'livekit' &&
          (serverUrl == null || serverUrl.isEmpty)) {
        debugPrint('[CallService] Accept call: LiveKit server URL is empty');
        await _rollbackAcceptAttempt(
          attempt,
          reason: 'rtc_error',
          errorMessage: _genericCallFailureText(),
        );
        return false;
      }
      if (rtcProvider == 'agora' && (_appId == null || _appId!.isEmpty)) {
        debugPrint('[CallService] Accept call: Agora App ID is empty');
        await _rollbackAcceptAttempt(
          attempt,
          reason: 'rtc_error',
          errorMessage: _genericCallFailureText(),
        );
        return false;
      }

      state = state.copyWith(
        callInfo: currentInfo.copyWith(
          sessionId: acceptedSessionId,
          revision: _revisionFromPayload(data) ?? currentInfo.revision,
          channelName: channelName,
          roomName: roomName,
          rtcProvider: rtcProvider,
          serverUrl: serverUrl,
          identity: _firstStringValue(data, ['identity', 'livekit_identity']),
        ),
      );
      if (await _acceptAttemptNoLongerActive(attempt)) return false;

      _startConnectionTimeout();

      if (rtcProvider == 'livekit') {
        await _joinLiveKitRoom(
          serverUrl: serverUrl!,
          token: token,
          callType: callType,
          isStillActive: () => _isAcceptAttemptActive(attempt),
        );
        if (await _acceptAttemptNoLongerActive(attempt)) return false;
      } else {
        await _initEngineWithWebRetry();
        if (await _acceptAttemptNoLongerActive(attempt)) return false;
        debugPrint('[CallService] Engine initialized');

        if (callType == CallType.video) {
          debugPrint('[CallService] Enabling video...');
          await _engine!.enableVideo();
          if (await _acceptAttemptNoLongerActive(attempt)) return false;
          _engine!.startPreview().catchError((e) {
            debugPrint('[CallService] startPreview error: $e');
          });
        }

        debugPrint('[CallService] Joining RTC channel');
        final isVideoCall = callType == CallType.video;
        await _joinAgoraChannelAndWait(
          token: token,
          channelName: channelName,
          uid: agoraUid > 0 ? agoraUid : 0,
          isVideo: isVideoCall,
        );
        if (await _acceptAttemptNoLongerActive(attempt)) return false;
        debugPrint('[CallService] Joined channel successfully');
      }

      // Agora 和 LiveKit 都统一应用接听时记录的输出路由。来电语音默认
      // 为扬声器，避免部分机型在 RTC 初始化后自动回落到听筒。
      final isVideoCall = callType == CallType.video;
      await _applySpeakerphoneEnabled(isVideoCall || state.isSpeakerOn);
      if (await _acceptAttemptNoLongerActive(attempt)) return false;

      final readyData = await _reportCallMediaReady(
        callId: acceptedCallId,
        sessionId: acceptedSessionId,
        cancelToken: attempt.cancelToken,
      );
      if (await _acceptAttemptNoLongerActive(attempt)) return false;
      final readyRevision = _revisionFromPayload(readyData);
      if (readyRevision != null && state.callInfo != null) {
        state = state.copyWith(
          callInfo: state.callInfo!.copyWith(revision: readyRevision),
        );
      }
      if (readyData['status']?.toString() == 'connected') {
        handleCallConnected(readyData);
      }
      WakelockPlus.enable();

      acceptedSuccessfully = true;
      return true;
    } catch (e, stack) {
      debugPrint('[CallService] Accept call error: $e');
      debugPrint('[CallService] Stack: $stack');
      if (await _acceptAttemptNoLongerActive(attempt)) return false;
      final errorMessage = _classifyError(e, 'answer');
      await _rollbackAcceptAttempt(
        attempt,
        reason: attempt.serverAccepted ? 'rtc_error' : 'answer_failed',
        errorMessage: errorMessage,
      );
      return false;
    } finally {
      attempt.timer?.cancel();
      if (identical(_activeAcceptAttempt, attempt) && acceptedSuccessfully) {
        _activeAcceptAttempt = null;
        _isAcceptingCall = false;
      }
    }
  }

  Future<void> _rollbackAcceptAttempt(
    _AcceptAttempt attempt, {
    required String reason,
    required String errorMessage,
  }) async {
    if (attempt.rollbackStarted) return;
    attempt.rollbackStarted = true;
    attempt.timer?.cancel();
    if (!attempt.cancelToken.isCancelled) {
      attempt.cancelToken.cancel(reason);
    }
    if (identical(_activeAcceptAttempt, attempt)) {
      _activeAcceptAttempt = null;
    }
    _isAcceptingCall = false;
    _cancelIncomingCallTimeout();
    _cancelConnectionTimeout();
    _cancelReconnectTimer();
    _stopCallHeartbeatTimer();

    // The accept response can be lost after the server has already entered
    // connecting, so use /call/end for every rollback. It is idempotent and
    // guarantees pre-connected calls are persisted with duration zero.
    final serverCleanup = _endCallById(
      attempt.callId,
      reason,
      sessionId: attempt.sessionId,
    );
    try {
      await _finishCallLocally(
        reason,
        awaitSystemCall: true,
      );
      if (!_isDisposed) {
        state = CallServiceState(errorMessage: errorMessage);
      }
      await serverCleanup;
    } finally {
      if (!attempt.rollbackComplete.isCompleted) {
        attempt.rollbackComplete.complete();
      }
    }
  }

  Future<void> _loadConfigIfNeeded([String? provider]) async {
    final targetProvider = _normalizeRtcProvider(provider ?? _rtcProvider);
    if (_isEnabled && _hasRtcConfig(targetProvider)) {
      return;
    }
    if (await _loadConfig()) {
      _configLoaded = true;
    }
  }

  bool _isPreloading = false;
  Future<void> _preloadForIncoming() async {
    if (_isPreloading) return;
    _isPreloading = true;

    try {
      debugPrint('[CallService] Preloading for incoming call...');

      final provider = state.callInfo?.rtcProvider ?? _rtcProvider;
      await _loadConfigIfNeeded(provider);

      if (_isEnabled &&
          provider == 'agora' &&
          _appId != null &&
          _appId!.isNotEmpty &&
          _engine == null) {
        debugPrint('[CallService] Pre-initializing engine...');
        await _initEngineWithWebRetry();
        debugPrint('[CallService] Engine pre-initialized');
      }
    } catch (e) {
      debugPrint('[CallService] Preload error (non-fatal): $e');
    } finally {
      _isPreloading = false;
    }
  }

  Future<void> _joinLiveKitRoom({
    required String serverUrl,
    required String token,
    required CallType callType,
    bool Function()? isStillActive,
  }) async {
    // A caller may already be showing an unpublished camera preview while the
    // signalling request is running. Preserve that track and publish it after
    // connecting so the renderer does not black-flash or restart the camera.
    final prejoinPreviewTrack =
        _liveKitRoom == null ? _liveKitLocalVideoTrack : null;
    await _disconnectLiveKitRoom(preserveLocalPreview: true);

    final preparedForUrl = _preparedLiveKitUrl == serverUrl;
    final room = preparedForUrl && _preparedLiveKitRoom != null
        ? _preparedLiveKitRoom!
        : lk.Room();
    final prepareFuture = preparedForUrl ? _preparedLiveKitFuture : null;
    if (preparedForUrl) {
      _preparedLiveKitRoom = null;
      _preparedLiveKitFuture = null;
      _preparedLiveKitUrl = null;
    }
    if (prepareFuture != null) {
      await prepareFuture;
    }
    final listener = room.createListener();
    _liveKitRoom = room;
    _liveKitListener = listener;
    _liveKitLocalVideoTrack = prejoinPreviewTrack;
    _liveKitRemoteVideoTrack = null;
    _liveKitRemoteIdentity = null;

    listener
      ..on<lk.TrackSubscribedEvent>((event) {
        _handleLiveKitTrackSubscribed(event);
      })
      ..on<lk.TrackPublishedEvent>((event) {
        if (kSilentCallQaMode && event.publication.kind == lk.TrackType.VIDEO) {
          unawaited(event.publication.subscribe());
        }
      })
      ..on<lk.ParticipantConnectedEvent>((event) {
        if (kSilentCallQaMode) {
          _markLiveKitRemoteActive(identity: event.participant.identity);
        }
      })
      ..on<lk.TrackUnsubscribedEvent>((event) {
        _handleLiveKitTrackUnsubscribed(event);
      })
      ..on<lk.ParticipantDisconnectedEvent>((event) {
        debugPrint(
          '[LiveKit] Participant disconnected: ${event.participant.identity}',
        );
        if (_isDisposed || _isEndingCall || _isCancellingCall) return;
        _beginReconnect('livekit_participant_disconnected');
      })
      ..on<lk.RoomReconnectingEvent>((event) {
        debugPrint('[LiveKit] Room reconnecting');
        _beginReconnect('livekit_room_reconnecting');
      })
      ..on<lk.RoomReconnectedEvent>((event) {
        debugPrint('[LiveKit] Room reconnected');
        _recoverReconnect('livekit_room_reconnected');
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        debugPrint('[LiveKit] Room disconnected: ${event.reason}');
        if (_isDisposed || _isEndingCall || _isCancellingCall) return;
        _beginReconnect('livekit_room_disconnected');
      });

    try {
      await room.connect(
        serverUrl,
        token,
        connectOptions: lk.ConnectOptions(autoSubscribe: !kSilentCallQaMode),
      );
      if (isStillActive?.call() == false) {
        await room.disconnect();
        await room.dispose();
        throw StateError('LiveKit join superseded by another call');
      }
      if (kSilentCallQaMode) {
        for (final participant in room.remoteParticipants.values) {
          _markLiveKitRemoteActive(identity: participant.identity);
          for (final publication in participant.videoTrackPublications) {
            await publication.subscribe();
          }
        }
      }
      final attemptId = _activeOutgoingAttemptId;
      if (attemptId != null) {
        _traceOutgoingAttempt(attemptId, 'local_rtc_joined');
      }
      final localParticipant = room.localParticipant;
      await localParticipant?.setMicrophoneEnabled(!state.isMuted);
      if (isStillActive?.call() == false) {
        await room.disconnect();
        await room.dispose();
        throw StateError('LiveKit setup superseded by another call');
      }

      if (callType == CallType.video && state.isVideoEnabled) {
        final publication = prejoinPreviewTrack != null
            ? await localParticipant?.publishVideoTrack(prejoinPreviewTrack)
            : await localParticipant?.setCameraEnabled(true);
        final track = publication?.track;
        _liveKitLocalVideoTrack =
            track is lk.LocalVideoTrack ? track : _findLiveKitLocalVideoTrack();
      } else {
        await localParticipant?.setCameraEnabled(false);
        _liveKitLocalVideoTrack = null;
      }

      if (isStillActive?.call() == false) {
        await room.disconnect();
        await room.dispose();
        throw StateError('LiveKit setup superseded by another call');
      }
      _syncLiveKitRemoteTracks(room);
      if (isStillActive?.call() == false) {
        await room.disconnect();
        await room.dispose();
        throw StateError('LiveKit setup superseded by another call');
      }
      state = state.copyWith(isVideoEnabled: callType == CallType.video);
    } catch (e) {
      await _disconnectLiveKitRoom();
      rethrow;
    }
  }

  Future<void> _prepareLiveKitConnection(String serverUrl) async {
    if (_isDisposed || serverUrl.isEmpty) return;
    if (_preparedLiveKitUrl == serverUrl && _preparedLiveKitFuture != null) {
      return _preparedLiveKitFuture;
    }

    final previousRoom = _preparedLiveKitRoom;
    _preparedLiveKitRoom = null;
    _preparedLiveKitFuture = null;
    _preparedLiveKitUrl = null;
    if (previousRoom != null) {
      await previousRoom.dispose();
    }

    final room = lk.Room();
    final future = room.prepareConnection(serverUrl, null);
    _preparedLiveKitRoom = room;
    _preparedLiveKitFuture = future;
    _preparedLiveKitUrl = serverUrl;
    try {
      await future;
    } catch (_) {
      // Connection preparation only warms DNS/TLS. The actual connect call
      // remains authoritative and reports any actionable network error.
    }
  }

  void _handleLiveKitTrackSubscribed(lk.TrackSubscribedEvent event) {
    final identity = event.participant.identity;
    final track = event.track;
    if (kSilentCallQaMode && track.kind == lk.TrackType.AUDIO) {
      unawaited(event.publication.unsubscribe());
      return;
    }
    if (track.kind == lk.TrackType.VIDEO && track is lk.RemoteVideoTrack) {
      _liveKitRemoteVideoTrack = track;
      _markLiveKitRemoteActive(identity: identity, videoEnabled: true);
      return;
    }
    if (track.kind == lk.TrackType.AUDIO) {
      _markLiveKitRemoteActive(identity: identity);
    }
  }

  void _handleLiveKitTrackUnsubscribed(lk.TrackUnsubscribedEvent event) {
    if (event.track.kind != lk.TrackType.VIDEO) return;
    if (_liveKitRemoteIdentity != null &&
        event.participant.identity != _liveKitRemoteIdentity) {
      return;
    }
    _liveKitRemoteVideoTrack = null;
    if (_isDisposed || state.callInfo?.type != CallType.video) return;
    state = state.copyWith(isRemoteVideoEnabled: false);
  }

  void _syncLiveKitRemoteTracks(lk.Room room) {
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track != null) {
          _liveKitRemoteVideoTrack = track;
          _markLiveKitRemoteActive(
            identity: participant.identity,
            videoEnabled: true,
          );
          return;
        }
      }
      for (final publication in participant.audioTrackPublications) {
        if (publication.track != null || publication.subscribed) {
          _markLiveKitRemoteActive(identity: participant.identity);
          return;
        }
      }
      _markLiveKitRemoteActive(identity: participant.identity);
      return;
    }
  }

  void _markLiveKitRemoteActive({
    required String identity,
    bool videoEnabled = false,
  }) {
    if (_isDisposed || state.callInfo == null) return;
    final callInfo = state.callInfo!;
    unawaited(_outgoingCallTone.stop());
    _liveKitRemoteIdentity = identity;

    state = state.copyWith(
      isRemoteVideoEnabled:
          callInfo.type == CallType.video ? videoEnabled : true,
      callInfo: callInfo.copyWith(
        remoteIdentity: identity,
        remoteUid: callInfo.remoteUid ?? identity.hashCode,
      ),
    );
    if (state.state == CallState.connected ||
        state.state == CallState.reconnecting) {
      _cancelConnectionTimeout();
      _markCallConnected(source: 'livekit_remote_active');
    }
  }

  lk.LocalVideoTrack? _findLiveKitLocalVideoTrack() {
    final publications = _liveKitRoom?.localParticipant?.videoTrackPublications;
    if (publications == null) return null;
    for (final publication in publications) {
      final track = publication.track;
      if (track != null && !publication.muted) {
        return track;
      }
    }
    return null;
  }

  Future<void> _disconnectLiveKitRoom({
    bool preserveLocalPreview = false,
  }) async {
    final listener = _liveKitListener;
    _liveKitListener = null;
    try {
      await listener?.dispose();
    } catch (e) {
      debugPrint('[LiveKit] listener dispose error: $e');
    }

    final room = _liveKitRoom;
    _liveKitRoom = null;
    final localTrack = _liveKitLocalVideoTrack;
    _liveKitLocalVideoTrack = null;
    _liveKitRemoteVideoTrack = null;
    _liveKitRemoteIdentity = null;
    if (room == null) {
      if (!preserveLocalPreview) {
        try {
          await localTrack?.stop();
        } catch (e) {
          debugPrint('[LiveKit] preview stop error: $e');
        }
      }
      return;
    }

    try {
      await room.disconnect();
      await room.dispose();
    } catch (e) {
      debugPrint('[LiveKit] disconnect error: $e');
    }
  }

  Future<void> _setLiveKitCameraEnabled(bool enabled) async {
    final participant = _liveKitRoom?.localParticipant;
    if (participant == null) return;
    final publication = await participant.setCameraEnabled(enabled);
    if (!enabled) {
      _liveKitLocalVideoTrack = null;
      return;
    }
    final track = publication?.track;
    _liveKitLocalVideoTrack =
        track is lk.LocalVideoTrack ? track : _findLiveKitLocalVideoTrack();
    if (!_isDisposed) {
      state = state.copyWith(isVideoEnabled: true);
    }
  }

  Future<void> _switchLiveKitCamera() async {
    final room = _liveKitRoom;
    if (room == null || state.callInfo?.type != CallType.video) return;
    final devices = await lk.Hardware.instance.videoInputs();
    if (devices.length < 2) return;
    final selectedId = room.selectedVideoInputDeviceId;
    lk.MediaDevice? nextDevice;
    for (final device in devices) {
      if (device.deviceId != selectedId) {
        nextDevice = device;
        break;
      }
    }
    if (nextDevice == null) return;
    await room.setVideoInputDevice(nextDevice);
    _liveKitLocalVideoTrack = _findLiveKitLocalVideoTrack();
  }

  Future<void> _setDefaultSpeakerphoneRoute(bool enabled) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }

    if (state.callInfo?.rtcProvider == 'livekit') {
      return;
    }

    final engine = _engine;
    if (engine == null) return;
    await engine.setDefaultAudioRouteToSpeakerphone(enabled);
  }

  Future<void> _setSpeakerphoneEnabled(bool enabled) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }

    if (state.callInfo?.rtcProvider == 'livekit') {
      await _liveKitRoom?.setSpeakerOn(enabled);
      return;
    }

    final engine = _engine;
    if (engine == null) return;
    await engine.setEnableSpeakerphone(enabled);
  }

  Future<void> _applySpeakerphoneEnabled(bool enabled) async {
    final previous = _speakerRouteFuture;
    late final Future<void> current;
    current = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      const retryDelays = <Duration>[
        Duration.zero,
        Duration(milliseconds: 120),
        Duration(milliseconds: 350),
      ];
      for (var index = 0; index < retryDelays.length; index++) {
        final delay = retryDelays[index];
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (_isDisposed || !state.isInCall) return;
        try {
          await _setSpeakerphoneEnabled(enabled);
          return;
        } catch (e) {
          final transient = e.toString().contains('-3');
          if (!transient || index == retryDelays.length - 1) {
            debugPrint('[CallService] Apply speakerphone route error: $e');
            return;
          }
          debugPrint('[CallService] Audio route not ready; retrying: $e');
        }
      }
    }();
    _speakerRouteFuture = current;
    await current.whenComplete(() {
      if (identical(_speakerRouteFuture, current)) {
        _speakerRouteFuture = null;
      }
    });
  }

  bool _isCallCancelled(int? originalCallId) {
    if (state.state != CallState.incoming &&
        state.state != CallState.connecting) {
      return true;
    }
    if (state.callInfo?.callId != originalCallId) {
      return true;
    }
    return false;
  }

  String _classifyError(dynamic e, String actionKey) {
    final action = _callActionText(actionKey);
    if (e is TimeoutException) {
      return _callServiceText(
        zhCN: '$action超时，请重试',
        zhTW: '$action逾時，請重試',
        en: '$action timed out. Please try again.',
      );
    }

    if (e is AgoraRtcException) {
      switch (e.code) {
        case -2: // ERR_INVALID_ARGUMENT
          return _genericCallFailureText();
        case -7: // ERR_NOT_INITIALIZED
          return _genericCallFailureText();
        case -17: // ERR_JOIN_CHANNEL_REJECTED
          return _genericCallFailureText();
        case 110: // ERR_TOKEN_EXPIRED
          return _genericCallFailureText();
        default:
          return _callServiceText(
            zhCN: '$action失败（错误码: ${e.code}）',
            zhTW: '$action失敗（錯誤碼: ${e.code}）',
            en: '$action failed (error code: ${e.code})',
          );
      }
    }

    final errorStr = e.toString().toLowerCase();
    if (errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return _genericCallFailureText();
    }

    return _callServiceText(
      zhCN: '$action失败，请重试',
      zhTW: '$action失敗，請重試',
      en: '$action failed. Please try again.',
    );
  }

  Future<bool> _isBlockedByCurrentUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return false;
    }

    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/user/blocked/check?user_id=$normalized',
      );
      if (!response.isSuccess || response.data == null) {
        return false;
      }
      return response.data!['is_blocked'] == true;
    } catch (e) {
      debugPrint('[CallService] Block status check failed for $normalized: $e');
      return false;
    }
  }

  Future<void> rejectCall({String reason = 'decline'}) async {
    if (_isDisposed) return;
    if (_isRejectingCall) return;
    if (state.state != CallState.incoming || state.callInfo == null) {
      return;
    }
    _isRejectingCall = true;
    final callId = state.callInfo!.callId ?? 0;
    final sessionId = state.callInfo!.sessionId;

    _cancelIncomingCallTimeout();

    _callTimer?.cancel();
    _callTimer = null;

    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().cancelCallNotification();
    }

    if (callId > 0) {
      unawaited(_rejectCallById(callId, reason, sessionId: sessionId));
    }
    await _finishCallLocally(reason);
  }

  Future<void> endCall({
    String reason = 'hangup',
    bool notifyServer = true,
  }) async {
    if (_isDisposed) return;
    if (_isEndingCall) return;
    if (!state.isInCall) return;
    _isEndingCall = true;
    final callId = state.callInfo?.callId ?? 0;
    final sessionId = state.callInfo?.sessionId;
    _callTimer?.cancel();
    _callTimer = null;

    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().cancelCallNotification();
    }

    if (notifyServer && callId > 0) {
      unawaited(_endCallById(callId, reason, sessionId: sessionId));
    }

    await _finishCallLocally(reason);
  }

  Future<void> _finishCallLocally(
    String reason, {
    bool awaitSystemCall = false,
  }) async {
    if (_isDisposed) return;
    await _incomingCallTone.stop();
    final acceptAttempt = _activeAcceptAttempt;
    if (acceptAttempt != null) {
      acceptAttempt.timer?.cancel();
      if (!acceptAttempt.cancelToken.isCancelled) {
        acceptAttempt.cancelToken.cancel(reason);
      }
      _activeAcceptAttempt = null;
      _acceptAttemptGeneration += 1;
    }
    _activeOutgoingAttemptId = null;
    _outgoingAttemptGeneration += 1;
    _outgoingAttemptStopwatch?.stop();
    _outgoingAttemptStopwatch = null;
    final finishingCallId = state.callInfo?.callId;
    final callKitUuid = _callKitUuidForCall(finishingCallId);
    final shouldPlayEndTone = !kSilentCallQaMode &&
        (state.state == CallState.connected ||
            state.state == CallState.reconnecting);

    // Detach old media before exposing idle state. All slow SDK, CallKit and
    // network work continues in the background, while a rapid redial can only
    // see fresh mutable fields.
    final cleanup = _leaveChannel();
    _localCleanupFuture = cleanup;
    unawaited(_outgoingCallTone.stop());
    onCallEnded?.call(reason);
    _resetState(immediate: true);

    if (callKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      final systemCleanup = _endSystemCall(callKitUuid);
      if (awaitSystemCall) {
        await systemCleanup;
      } else {
        unawaited(systemCleanup);
      }
    }

    if (shouldPlayEndTone) {
      unawaited(_callEndTone.playAfter(cleanup));
    }
    unawaited(cleanup.whenComplete(() {
      if (identical(_localCleanupFuture, cleanup)) {
        _localCleanupFuture = null;
      }
    }));
  }

  Future<void> _endSystemCall(String uuid) async {
    final targetCallId = _callIdByCallKitUuid[uuid];
    try {
      await FlutterCallkitIncoming.endCall(uuid);
    } catch (e) {
      debugPrint('[CallService] plugin endCall error: $e');
    }
    // Some Android ROMs deliver the end broadcast with a stale UUID. Resolve
    // the same business call by its active UUID as a fallback, without
    // touching a newer rapid-redial system call.
    if (Platform.isAndroid) {
      try {
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls is List) {
          for (final rawCall in activeCalls) {
            final active = _asStringKeyMap(rawCall);
            final activeId = active?['id']?.toString().trim() ?? '';
            final activeCallId =
                active == null ? null : _callIdFromPayload(active);
            if (activeId.isNotEmpty &&
                activeId != uuid &&
                targetCallId != null &&
                activeCallId == targetCallId) {
              await FlutterCallkitIncoming.endCall(activeId);
            }
          }
        }
      } catch (e) {
        debugPrint('[CallService] Android active call cleanup error: $e');
      }
    }
    if (Platform.isIOS) {
      try {
        await _iosNativeCallKitChannel.invokeMethod<void>(
          'endNativeCall',
          <String, dynamic>{'uuid': uuid},
        );
      } catch (e) {
        debugPrint('[CallService] native endCall error: $e');
      }
    }
    final callId = _callIdByCallKitUuid.remove(uuid);
    _callKitSessionByUuid.remove(uuid);
    _callKitAcceptsInFlight.remove(uuid);
    if (callId != null && _callKitUuidByCallId[callId] == uuid) {
      _callKitUuidByCallId.remove(callId);
    }
  }

  Future<void> _markSystemCallConnected(String uuid) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(uuid);
    } catch (e) {
      debugPrint('[CallService] plugin callConnected error: $e');
    }
  }

  Future<void> _waitForLocalCleanup() async {
    final cleanup = _localCleanupFuture;
    if (cleanup == null) return;
    try {
      await cleanup.timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[CallService] Local cleanup wait skipped: $e');
    }
  }

  Future<void> cancelCall() async {
    if (_isDisposed) return;
    if (_isCancellingCall) return;
    if ((state.state != CallState.preparing &&
            state.state != CallState.outgoing &&
            state.state != CallState.failed) ||
        state.callInfo == null) {
      return;
    }
    _isCancellingCall = true;
    _activeOutgoingAttemptId = null;
    _outgoingAttemptGeneration += 1;
    final callId = state.callInfo!.callId ?? 0;
    final sessionId = state.callInfo!.sessionId;

    if (callId > 0) {
      unawaited(_cancelCallById(callId, sessionId: sessionId));
    }

    if (_isDisposed) return;

    await _finishCallLocally('cancelled');
  }

  Future<void> _cancelCallById(
    int callId, {
    String? sessionId,
  }) async {
    await _queueAndDeliverTerminalAction(
      callId: callId,
      sessionId: sessionId,
      action: 'cancel',
      reason: 'cancelled',
    );
  }

  Future<void> _endCallById(
    int callId,
    String reason, {
    String? sessionId,
  }) async {
    await _queueAndDeliverTerminalAction(
      callId: callId,
      sessionId: sessionId,
      action: 'end',
      reason: reason,
    );
  }

  Future<void> _rejectCallById(
    int callId,
    String reason, {
    String? sessionId,
  }) async {
    await _queueAndDeliverTerminalAction(
      callId: callId,
      sessionId: sessionId,
      action: 'reject',
      reason: reason,
    );
  }

  Future<void> _queueAndDeliverTerminalAction({
    required int callId,
    required String action,
    required String reason,
    String? sessionId,
  }) async {
    if (callId <= 0) return;
    final owner = (await TokenStorage.getUserId())?.trim() ?? '';
    if (owner.isEmpty) {
      debugPrint(
        '[CallService] Terminal action has no authenticated owner; '
        'sending without persistence call_id=$callId',
      );
      await _deliverTerminalAction(
        CallTerminalAction(
          ownerUserId: 'unavailable',
          callId: callId,
          sessionId: sessionId?.trim() ?? '',
          action: action,
          reason: reason,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      return;
    }
    final terminalAction = CallTerminalAction(
      ownerUserId: owner,
      callId: callId,
      sessionId: sessionId?.trim() ?? '',
      action: action,
      reason: reason,
      createdAt: DateTime.now().toUtc(),
    );
    try {
      await _terminalOutbox.enqueue(terminalAction);
    } catch (e) {
      debugPrint('[CallService] Persist terminal action failed: $e');
    }
    if (await _deliverTerminalAction(terminalAction)) {
      await _terminalOutbox.remove(terminalAction);
    }
  }

  Future<void> _drainTerminalOutbox() {
    final running = _terminalOutboxDrainFuture;
    if (running != null) return running;
    late final Future<void> current;
    current = () async {
      final owner = (await TokenStorage.getUserId())?.trim() ?? '';
      if (owner.isEmpty) return;
      final pending = await _terminalOutbox.loadForOwner(owner);
      for (final action in pending) {
        if (_isDisposed) return;
        if (await _deliverTerminalAction(action)) {
          await _terminalOutbox.remove(action);
        }
      }
    }();
    _terminalOutboxDrainFuture = current;
    return current.whenComplete(() {
      if (identical(_terminalOutboxDrainFuture, current)) {
        _terminalOutboxDrainFuture = null;
      }
    });
  }

  Future<bool> _deliverTerminalAction(CallTerminalAction action) async {
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        late final ApiResponse<dynamic> response;
        if (action.action == 'cancel') {
          final path = action.sessionId.isEmpty
              ? '/call/${action.callId}'
              : '/call/${action.callId}?session_id=${Uri.encodeQueryComponent(action.sessionId)}';
          response = await _api
              .delete<dynamic>(path)
              .timeout(const Duration(seconds: 4));
        } else {
          response = await _api.post<dynamic>(
            action.action == 'reject' ? '/call/reject' : '/call/end',
            data: <String, dynamic>{
              'call_id': action.callId,
              if (action.sessionId.isNotEmpty) 'session_id': action.sessionId,
              'reason': action.reason,
            },
          ).timeout(const Duration(seconds: 4));
        }
        if (response.isSuccess ||
            response.code == 400 ||
            response.code == 403 ||
            response.code == 404) {
          return true;
        }
        debugPrint(
          '[CallService] Terminal action failed attempt=$attempt '
          'action=${action.action} call_id=${action.callId} '
          'code=${response.code}',
        );
      } catch (e) {
        debugPrint(
          '[CallService] Terminal action error attempt=$attempt '
          'action=${action.action} call_id=${action.callId}: $e',
        );
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    return false;
  }

  void toggleMute() {
    if (_isDisposed) return;
    if (kSilentCallQaMode) {
      state = state.copyWith(isMuted: true);
      return;
    }
    final newMuted = !state.isMuted;
    if (state.callInfo?.rtcProvider == 'livekit') {
      unawaited(
        _liveKitRoom?.localParticipant?.setMicrophoneEnabled(!newMuted) ??
            Future.value(),
      );
    } else {
      _engine?.muteLocalAudioStream(newMuted);
    }
    state = state.copyWith(isMuted: newMuted);
  }

  void toggleSpeaker() {
    unawaited(_toggleSpeaker());
  }

  Future<void> _toggleSpeaker() async {
    if (_isDisposed) return;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }
    final newSpeaker = !state.isSpeakerOn;
    try {
      await _setSpeakerphoneEnabled(newSpeaker);
      if (_isDisposed) return;
      state = state.copyWith(isSpeakerOn: newSpeaker);
    } catch (e) {
      debugPrint('[CallService] Toggle speaker error: $e');
    }
  }

  void toggleVideo() {
    if (_isDisposed) return;
    if (state.callInfo?.type != CallType.video) return;

    unawaited(_setVideoEnabled(!state.isVideoEnabled));
  }

  Future<void> _setVideoEnabled(
    bool newEnabled, {
    bool notifyPeer = true,
  }) async {
    if (_isDisposed || state.callInfo?.type != CallType.video) return;
    if (state.isVideoEnabled == newEnabled) return;
    if (state.callInfo?.rtcProvider == 'livekit') {
      await _setLiveKitCameraEnabled(newEnabled);
    } else {
      if (newEnabled) {
        await _engine?.enableVideo();
        await _engine?.startPreview();
      } else {
        await _engine?.stopPreview();
        await _engine?.disableVideo();
      }
      await _engine?.muteLocalVideoStream(!newEnabled);
    }
    if (_isDisposed) return;
    state = state.copyWith(isVideoEnabled: newEnabled);
    if (notifyPeer) {
      await _sendMediaState(videoEnabled: newEnabled);
    }
  }

  Future<void> downgradeToVoice() async {
    final info = state.callInfo;
    if (_isDisposed || info == null || info.type != CallType.video) return;
    if (state.isVideoEnabled) {
      await _setVideoEnabled(false, notifyPeer: false);
    }
    if (_isDisposed || state.callInfo?.callId != info.callId) return;
    state = state.copyWith(
      callInfo: info.copyWith(type: CallType.voice),
      isVideoEnabled: false,
      isRemoteVideoEnabled: true,
    );
    await _applySpeakerphoneEnabled(state.isSpeakerOn);
    await _sendMediaState(callType: CallType.voice, videoEnabled: false);
  }

  Future<void> handleAppLifecycleState(AppLifecycleState lifecycleState) async {
    if (_isDisposed || state.callInfo?.type != CallType.video) return;
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      if (state.isVideoEnabled) {
        _restoreVideoAfterBackground = true;
        await _setVideoEnabled(false);
      }
    } else if (lifecycleState == AppLifecycleState.resumed &&
        _restoreVideoAfterBackground) {
      _restoreVideoAfterBackground = false;
      await _setVideoEnabled(true);
    }
  }

  Future<void> _sendMediaState({
    CallType? callType,
    required bool videoEnabled,
  }) async {
    final callId = state.callInfo?.callId;
    if (callId == null || callId <= 0 || state.state != CallState.connected) {
      return;
    }
    try {
      await _api.post<Map<String, dynamic>>(
        '/call/media-state',
        data: {
          'call_id': callId,
          if (state.callInfo?.sessionId != null)
            'session_id': state.callInfo!.sessionId,
          if (callType != null)
            'call_type': callType == CallType.video ? 'video' : 'voice',
          'video_enabled': videoEnabled,
        },
      );
    } catch (e) {
      debugPrint('[CallService] Sync media state error: $e');
    }
  }

  Future<void> _handleRemoteMediaChanged(
    Map<String, dynamic> payload,
  ) async {
    final eventCallId = _callIdFromPayload(payload);
    if (!_matchesCurrentCall(
          eventCallId,
          eventSessionId: _sessionIdFromPayload(payload),
          eventRevision: _revisionFromPayload(payload),
          requireSession: true,
        ) ||
        state.callInfo == null) {
      return;
    }
    final downgraded = payload['call_type']?.toString() == 'voice';
    final videoEnabled = _truthyValue(payload['video_enabled']);
    final info = state.callInfo!;
    if (downgraded && info.type == CallType.video && state.isVideoEnabled) {
      await _setVideoEnabled(false, notifyPeer: false);
      if (_isDisposed || state.callInfo?.callId != info.callId) return;
    }
    state = state.copyWith(
      callInfo: info.copyWith(
        type: downgraded ? CallType.voice : info.type,
        revision: _revisionFromPayload(payload) ?? info.revision,
      ),
      isRemoteVideoEnabled: downgraded ? true : videoEnabled,
      isVideoEnabled: downgraded ? false : state.isVideoEnabled,
    );
  }

  Future<void> switchCamera() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }
    if (state.callInfo?.rtcProvider == 'livekit') {
      await _switchLiveKitCamera();
      return;
    }
    await _engine?.switchCamera();
  }

  void toggleMinimize() {
    state = state.copyWith(isMinimized: !state.isMinimized);
  }

  Duration get callDuration {
    final info = state.callInfo;
    final stopwatch = _connectedElapsedStopwatch;
    if (info != null &&
        stopwatch != null &&
        _connectedClockIdentity == _callClockIdentity(info)) {
      return _connectedElapsedBase + stopwatch.elapsed;
    }
    final offset = _hasServerClockOffset ? _serverClockOffset : Duration.zero;
    return Duration(
      seconds: callElapsedSecondsWithClockOffset(
        info?.connectTime,
        DateTime.now(),
        offset,
      ),
    );
  }

  bool get hasLocalVideoView {
    if (state.callInfo?.rtcProvider == 'livekit') {
      return _liveKitLocalVideoTrack != null ||
          _findLiveKitLocalVideoTrack() != null;
    }
    return _engine != null;
  }

  Widget getLocalView() {
    if (state.callInfo?.rtcProvider == 'livekit') {
      final track = _liveKitLocalVideoTrack ?? _findLiveKitLocalVideoTrack();
      if (track == null) return const SizedBox();
      return lk.VideoTrackRenderer(
        track,
        fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    if (_engine == null) return const SizedBox();
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeHidden,
        ),
      ),
    );
  }

  Widget getRemoteView() {
    if (state.callInfo?.rtcProvider == 'livekit') {
      final track = _liveKitRemoteVideoTrack;
      if (track == null) return const SizedBox();
      return lk.VideoTrackRenderer(
        track,
        fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    if (_engine == null || state.callInfo?.remoteUid == null) {
      return const SizedBox();
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(
          uid: state.callInfo!.remoteUid!,
          renderMode: RenderModeType.renderModeHidden,
        ),
        connection: RtcConnection(channelId: state.callInfo!.channelName),
      ),
    );
  }

  Future<void> _leaveChannel() {
    // Detach synchronously. A later queued cleanup must only own this old
    // snapshot and can never release resources installed by a rapid redial.
    final detached = _detachCallMedia();
    final previous = _leaveChannelFuture;
    final current = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (e) {
          debugPrint('[CallService] Previous channel cleanup failed: $e');
        }
      }
      await _disposeDetachedCallMedia(detached);
    }();
    _leaveChannelFuture = current;
    return current.whenComplete(() {
      if (identical(_leaveChannelFuture, current)) {
        _leaveChannelFuture = null;
      }
    });
  }

  String? _callKitEventSessionId(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return null;
    final extra = _asStringKeyMap(data['extra']) ?? <String, dynamic>{};
    final value = _firstStringValue(
      <String, dynamic>{...data, ...extra},
      ['session_id', 'sessionId'],
    );
    if (value.isNotEmpty) return value;
    final uuid = _firstStringValue(data, ['id', 'uuid']);
    return uuid.isEmpty ? null : _callKitSessionByUuid[uuid];
  }

  int? _callKitEventRevision(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return null;
    final extra = _asStringKeyMap(data['extra']) ?? <String, dynamic>{};
    return _intValue(extra['revision'] ?? data['revision']);
  }

  _DetachedCallMedia _detachCallMedia() {
    _callTimer?.cancel();
    _callTimer = null;
    _stopCallHeartbeatTimer();
    _cancelOutgoingCallTimeout();
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _cancelReconnectTimer();

    final engine = _engine;
    final eventHandler = _eventHandler;
    if (eventHandler != null && engine != null) {
      try {
        engine.unregisterEventHandler(eventHandler);
      } catch (e) {
        debugPrint('[CallService] Detach Agora handler error: $e');
      }
    }
    _engine = null;
    _eventHandler = null;
    _agoraJoinCompleter = null;
    _agoraPreviewStarted = false;

    final liveKitRoom = _liveKitRoom;
    final liveKitListener = _liveKitListener;
    final liveKitLocalVideoTrack = _liveKitLocalVideoTrack;
    try {
      liveKitListener?.dispose();
    } catch (e) {
      debugPrint('[LiveKit] Detach listener error: $e');
    }
    _liveKitRoom = null;
    _liveKitListener = null;
    _liveKitLocalVideoTrack = null;
    _liveKitRemoteVideoTrack = null;
    _liveKitRemoteIdentity = null;

    WakelockPlus.disable();
    return _DetachedCallMedia(
      engine: engine,
      liveKitRoom: liveKitRoom,
      liveKitLocalVideoTrack: liveKitLocalVideoTrack,
    );
  }

  Future<void> _disposeDetachedCallMedia(_DetachedCallMedia media) async {
    final room = media.liveKitRoom;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (e) {
        debugPrint('[LiveKit] Detached disconnect error: $e');
      }
      try {
        await room.dispose();
      } catch (e) {
        debugPrint('[LiveKit] Detached dispose error: $e');
      }
    } else {
      try {
        await media.liveKitLocalVideoTrack?.stop();
      } catch (e) {
        debugPrint('[LiveKit] Detached preview stop error: $e');
      }
    }

    try {
      await media.engine?.leaveChannel();
      await media.engine?.stopPreview();
      await media.engine?.release();
    } catch (e) {
      debugPrint('[CallService] Leave channel error: $e');
    }
  }

  void _resetState({bool immediate = false}) {
    final acceptAttempt = _activeAcceptAttempt;
    acceptAttempt?.timer?.cancel();
    if (acceptAttempt != null && !acceptAttempt.cancelToken.isCancelled) {
      acceptAttempt.cancelToken.cancel('call_state_reset');
    }
    _activeAcceptAttempt = null;
    _activeOutgoingAttemptId = null;
    _outgoingAttemptStopwatch?.stop();
    _outgoingAttemptStopwatch = null;
    unawaited(_outgoingCallTone.stop());
    unawaited(_incomingCallTone.stop());
    _callTimer?.cancel();
    _callTimer = null;
    _stopCallHeartbeatTimer();
    _cancelOutgoingCallTimeout();
    _cancelReconnectTimer();
    _resetConnectedClock();
    _isAcceptingCall = false;
    _isEndingCall = false;
    _isRejectingCall = false;
    _isCancellingCall = false;
    _isPreloading = false;
    WakelockPlus.disable();

    if (_isDisposed) return;

    if (immediate) {
      state = const CallServiceState();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        state = const CallServiceState();
      }
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isDisposed) {
        _callTimer?.cancel();
        _callTimer = null;
        return;
      }
      if (state.state != CallState.connected &&
          state.state != CallState.reconnecting) {
        _callTimer?.cancel();
        _callTimer = null;
      }
    });
  }

  void _startCallHeartbeatTimer(int? callId) {
    _stopCallHeartbeatTimer();
    if (callId == null || callId <= 0) return;
    _sendCallHeartbeat(callId);
    _callHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isDisposed) {
        _stopCallHeartbeatTimer();
        return;
      }
      if ((state.state != CallState.connected &&
              state.state != CallState.reconnecting) ||
          state.callInfo?.callId != callId) {
        _stopCallHeartbeatTimer();
        return;
      }
      _sendCallHeartbeat(callId);
    });
  }

  void _stopCallHeartbeatTimer() {
    _callHeartbeatTimer?.cancel();
    _callHeartbeatTimer = null;
  }

  void _sendCallHeartbeat(int callId) {
    unawaited(
      _api.post<Map<String, dynamic>>('/call/heartbeat', data: {
        'call_id': callId,
        if (state.callInfo?.sessionId?.trim().isNotEmpty == true)
          'session_id': state.callInfo!.sessionId!.trim(),
      }).then((response) {
        if (!response.isSuccess || response.data == null) return;
        if (response.data!['active'] == false &&
            state.callInfo?.callId == callId) {
          debugPrint(
            '[CallService] Heartbeat marked call inactive; confirming '
            'call_id=$callId before local teardown',
          );
          unawaited(_confirmInactiveHeartbeat(callId));
        }
      }).catchError((e) {
        debugPrint('[CallService] Call heartbeat error: $e');
      }),
    );
  }

  Future<void> _confirmInactiveHeartbeat(int callId) async {
    if (!_heartbeatInactiveConfirmations.add(callId)) return;
    try {
      // A terminal update and the heartbeat response can cross in flight.
      // Give the authoritative active-call read a small consistency window;
      // this costs one request but avoids a visible false hangup.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (_isDisposed || state.callInfo?.callId != callId) return;

      final response = await _api.get<Map<String, dynamic>>('/call/active');
      if (!response.isSuccess || response.data == null) return;
      if (_isDisposed || state.callInfo?.callId != callId) return;

      final data = response.data!;
      final active = data['active'] == true;
      final activeCallId = _intValue(data['call_id']);
      final activeSessionId = _sessionIdFromPayload(data);
      final currentSessionId = state.callInfo?.sessionId?.trim() ?? '';
      final sessionMatches = currentSessionId.isEmpty ||
          (activeSessionId != null && activeSessionId == currentSessionId);
      if (active && activeCallId == callId && sessionMatches) {
        final revision = _revisionFromPayload(data);
        if (revision != null && state.callInfo != null) {
          state = state.copyWith(
            callInfo: state.callInfo!.copyWith(revision: revision),
          );
        }
        debugPrint(
          '[CallService] Heartbeat inactive result was transient; '
          'keeping call_id=$callId',
        );
        return;
      }

      debugPrint(
        '[CallService] Server inactivity confirmed for call_id=$callId '
        'active=$active active_call_id=$activeCallId',
      );
      await _finishCallLocally('server_inactive_confirmed');
    } catch (e) {
      // Confirmation failures preserve the live call. A later heartbeat or WS
      // terminal event will retry reconciliation without user-visible churn.
      debugPrint(
        '[CallService] Inactive heartbeat confirmation failed '
        'call_id=$callId: $e',
      );
    } finally {
      _heartbeatInactiveConfirmations.remove(callId);
    }
  }

  void _setupCallKit() {
    _callKitSubscription?.cancel();
    _callKitSubscription = FlutterCallkitIncoming.onEvent.listen((event) async {
      debugPrint(
        '[CallService] CallKit event: ${event?.event}, body=${_sensitiveMapSummary(event?.body)}',
      );
      switch (event?.event) {
        case Event.actionCallAccept:
          debugPrint('[CallService] CallKit: actionCallAccept');
          await _handleCallKitAccept(event?.body);
          break;
        case Event.actionCallDecline:
          debugPrint('[CallService] CallKit: actionCallDecline');
          await _handleCallKitReject(event?.body, 'decline');
          break;
        case Event.actionCallEnded:
          debugPrint(
            '[CallService] CallKit: actionCallEnded, currentState=${state.state}',
          );
          await _handleCallKitEnd(event?.body);
          break;
        case Event.actionCallStart:
          debugPrint('[CallService] CallKit: actionCallStart (outgoing)');
          break;
        case Event.actionCallIncoming:
          debugPrint('[CallService] CallKit: actionCallIncoming');
          await _restoreIncomingCallFromCallKitEvent(event?.body);
          break;
        case Event.actionCallTimeout:
          debugPrint('[CallService] CallKit: actionCallTimeout');
          await _handleCallKitReject(event?.body, 'timeout');
          break;
        case Event.actionCallToggleHold:
          debugPrint('[CallService] CallKit: actionCallToggleHold');
          break;
        case Event.actionCallToggleMute:
          debugPrint('[CallService] CallKit: actionCallToggleMute');
          toggleMute();
          break;
        case Event.actionCallToggleDmtf:
          debugPrint('[CallService] CallKit: actionCallToggleDmtf');
          break;
        case Event.actionCallToggleGroup:
          debugPrint('[CallService] CallKit: actionCallToggleGroup');
          break;
        case Event.actionCallToggleAudioSession:
          debugPrint('[CallService] CallKit: actionCallToggleAudioSession');
          unawaited(_applySpeakerphoneEnabled(
            state.callInfo?.type == CallType.video || state.isSpeakerOn,
          ));
          break;
        case Event.actionDidUpdateDevicePushTokenVoip:
          debugPrint(
            '[CallService] CallKit: actionDidUpdateDevicePushTokenVoip',
          );
          break;
        default:
          debugPrint('[CallService] CallKit: unknown event ${event?.event}');
          break;
      }
    });
  }

  Future<void> _handleCallKitReject(dynamic eventBody, String reason) async {
    final callId = _callKitEventCallId(eventBody);
    final eventUuid = _callKitEventUuid(eventBody);
    final eventSessionId = _callKitEventSessionId(eventBody);
    final eventRevision = _callKitEventRevision(eventBody);
    if (state.state == CallState.incoming &&
        state.callInfo != null &&
        _matchesCurrentCall(
          callId,
          eventSessionId: eventSessionId,
          eventRevision: eventRevision,
          requireSession: true,
        )) {
      await rejectCall(reason: reason);
      return;
    }

    if (callId != null) {
      await _rejectCallById(callId, reason, sessionId: eventSessionId);
    }
    if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      await _endSystemCall(eventUuid);
    }
    if (!state.isInCall) {
      _resetState();
    }
  }

  Future<void> _handleCallKitEnd(dynamic eventBody) async {
    final callId = _callKitEventCallId(eventBody);
    final eventUuid = _callKitEventUuid(eventBody);
    final eventSessionId = _callKitEventSessionId(eventBody);
    final eventRevision = _callKitEventRevision(eventBody);
    final matchesCurrent = _matchesCurrentCall(
      callId,
      eventSessionId: eventSessionId,
      eventRevision: eventRevision,
      requireSession: true,
    );
    if (state.state == CallState.incoming && matchesCurrent) {
      await rejectCall(reason: 'dismissed');
      return;
    }
    if (state.isInCall && matchesCurrent) {
      await endCall();
      return;
    }

    if (callId != null) {
      if (_callKitEventIsAccepted(eventBody)) {
        await _endCallById(
          callId,
          'hangup',
          sessionId: eventSessionId,
        );
      } else {
        await _rejectCallById(
          callId,
          'dismissed',
          sessionId: eventSessionId,
        );
      }
    }
    if (eventUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      await _endSystemCall(eventUuid);
    }
    if (!state.isInCall) {
      _resetState();
    }
  }

  Future<void> _handleCallKitAccept([dynamic eventBody]) async {
    final eventCallId = _callKitEventCallId(eventBody);
    final eventSessionId = _callKitEventSessionId(eventBody)?.trim() ?? '';
    final eventUuid = _callKitEventUuid(eventBody);
    final currentCall = state.callInfo;
    if (callKitAcceptIsActiveReplay(
      currentState: state.state,
      currentCallId: currentCall?.callId,
      eventCallId: eventCallId,
      currentSessionId: currentCall?.sessionId,
      eventSessionId: eventSessionId,
    )) {
      _rememberCallKitUuidFromData(eventBody);
      debugPrint(
        '[CallService] Ignoring restored CallKit accept for active '
        'call_id=$eventCallId state=${state.state}',
      );
      return;
    }
    final acceptIdentity =
        eventUuid ?? 'call:${eventCallId ?? 0}:$eventSessionId';
    if (!_callKitAcceptsInFlight.add(acceptIdentity)) {
      debugPrint(
        '[CallService] CallKit accept already handled for $acceptIdentity',
      );
      return;
    }

    try {
      final restored = await _restoreIncomingCallFromCallKitEvent(eventBody);
      final callId = state.callInfo?.callId ?? eventCallId;
      final callKitUuid = _callKitUuidForCall(callId, eventBody: eventBody);
      if (!restored) {
        if (callKitUuid != null) await _endSystemCall(callKitUuid);
        return;
      }

      await Future.delayed(const Duration(milliseconds: 200));

      if (state.state != CallState.incoming || state.callInfo == null) {
        debugPrint('[CallService] CallKit accept: call no longer incoming');
        if (callKitUuid != null && state.state == CallState.idle) {
          await _endSystemCall(callKitUuid);
        }
        return;
      }

      final success = await acceptCall();

      debugPrint('[CallService] CallKit acceptCall result: $success');

      if (success) {
        debugPrint(
          '[CallService] CallKit accept success, triggering onCallAccepted',
        );
        await Future.delayed(const Duration(milliseconds: 100));
        onCallAccepted?.call();
      } else {
        debugPrint('[CallService] CallKit accept failed');
        if (callKitUuid != null) {
          await _endSystemCall(callKitUuid);
        }
        if (state.errorMessage != null) {
          onCallFailed?.call(state.errorMessage!);
        }
      }
    } catch (e) {
      debugPrint('[CallService] CallKit accept error: $e');
      final callKitUuid = _callKitUuidForCall(
        state.callInfo?.callId ?? eventCallId,
        eventBody: eventBody,
      );
      if (callKitUuid != null) {
        await _endSystemCall(callKitUuid);
      }
      state = state.copyWith(errorMessage: _genericCallFailureText());
      onCallFailed?.call(
        '${_callServiceText(
          zhCN: '接听通话失败',
          zhTW: '接聽通話失敗',
          en: 'Answer call failed',
        )}: $e',
      );
    } finally {
      _callKitAcceptsInFlight.remove(acceptIdentity);
    }
  }

  VoidCallback? onCallAccepted;

  Future<void> _showCallKit(CallInfo callInfo) async {
    late final String callKitUuid;
    if (Platform.isAndroid && callInfo.callId != null) {
      final sessionSuffix = callInfo.sessionId?.trim() ?? '';
      callKitUuid = sessionSuffix.isEmpty
          ? 'call-${callInfo.callId}'
          : 'call-${callInfo.callId}-$sessionSuffix';
    } else if (Platform.isIOS && callInfo.callId != null) {
      callKitUuid = stableIosCallKitUuid(
        callInfo.callId!,
        sessionId: callInfo.sessionId,
      );
    } else {
      callKitUuid = const Uuid().v4();
    }
    if (callInfo.callId != null) {
      _callKitUuidByCallId[callInfo.callId!] = callKitUuid;
      _callIdByCallKitUuid[callKitUuid] = callInfo.callId!;
      final sessionId = callInfo.sessionId?.trim() ?? '';
      if (sessionId.isNotEmpty) {
        _callKitSessionByUuid[callKitUuid] = sessionId;
      }
    }

    final restored = await _useExistingSystemCallIfPresent(callInfo);
    if (restored) {
      return;
    }

    if (Platform.isAndroid) {
      await FlutterCallkitIncoming.showCallkitIncoming(
        buildAndroidIncomingCallParams(
          _incomingPayloadFromCallInfo(callInfo),
          uuid: callKitUuid,
        ),
      );
      return;
    }

    final params = CallKitParams(
      id: callKitUuid,
      nameCaller: callInfo.remoteName,
      appName: defaultAppDisplayName(),
      avatar: callInfo.remoteAvatar,
      handle: callInfo.remoteName,
      type: callInfo.type == CallType.video ? 1 : 0,
      duration: 30000,
      textAccept: _callActionText('answer'),
      textDecline: _callActionText('decline'),
      extra: _incomingPayloadFromCallInfo(callInfo),
      headers: <String, dynamic>{},
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#5865F2',
        backgroundUrl: '',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        isShowFullLockedScreen: true,
        isShowCallID: false,
        incomingCallNotificationChannelName: _callServiceText(
          zhCN: '\u6765\u7535\u901a\u77e5',
          zhTW: '\u4f86\u96fb\u901a\u77e5',
          en: 'Incoming call',
        ),
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: false,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        configureAudioSession: false,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: '',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<bool> _useExistingSystemCallIfPresent(CallInfo callInfo) async {
    if (!(Platform.isIOS || Platform.isAndroid)) {
      return false;
    }
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      final calls = activeCalls is List ? activeCalls : const [];
      for (final rawCall in calls) {
        final call = _asStringKeyMap(rawCall);
        if (call == null) continue;
        final payload = _incomingPayloadFromCallKitData(call);
        if (payload == null) continue;
        final payloadCallId =
            int.tryParse(payload['call_id']?.toString() ?? '');
        if (payloadCallId == null || payloadCallId != callInfo.callId) {
          continue;
        }
        final existingUuid =
            call['id']?.toString() ?? call['uuid']?.toString() ?? '';
        if (existingUuid.isNotEmpty && callInfo.callId != null) {
          _callKitUuidByCallId[callInfo.callId!] = existingUuid;
          _callIdByCallKitUuid[existingUuid] = callInfo.callId!;
          final sessionId = callInfo.sessionId?.trim() ?? '';
          if (sessionId.isNotEmpty) {
            _callKitSessionByUuid[existingUuid] = sessionId;
          }
        }
        return true;
      }
    } catch (e) {
      debugPrint('[CallService] Check existing system call error: $e');
    }
    return false;
  }

  void handleCallAccepted([Map<String, dynamic>? payload]) {
    if (payload != null) {
      _observeServerClock(payload);
    }
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(
      eventCallId,
      eventSessionId: payload == null ? null : _sessionIdFromPayload(payload),
      eventRevision: payload == null ? null : _revisionFromPayload(payload),
      requireSession: true,
    )) {
      debugPrint(
        '[CallService] Ignoring call_accepted for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }
    final eventRevision =
        payload == null ? null : _revisionFromPayload(payload);
    if (state.callInfo != null && eventRevision != null) {
      state = state.copyWith(
        callInfo: state.callInfo!.copyWith(
          revision: eventRevision,
        ),
      );
    }
    if (state.state == CallState.outgoing) {
      _cancelOutgoingCallTimeout();
      unawaited(_outgoingCallTone.stop());
      state = state.copyWith(state: CallState.connecting);
      _startConnectionTimeout();
      final info = state.callInfo;
      if (info?.callId != null) {
        unawaited(_refreshConnectedStateAfterAccept(info!));
      }
    }
  }

  Future<void> _refreshConnectedStateAfterAccept(CallInfo info) async {
    try {
      final data = await _reportCallMediaReady(
        callId: info.callId!,
        sessionId: info.sessionId,
      );
      if (_isDisposed || state.callInfo?.callId != info.callId) return;
      if (data['status']?.toString() == 'connected') {
        handleCallConnected(data);
      }
    } catch (error) {
      debugPrint('[CallService] Refresh after accept failed: $error');
      unawaited(syncActiveCallStateWithServer());
    }
  }

  void handleCallConnected([Map<String, dynamic>? payload]) {
    if (payload == null) return;
    _observeServerClock(payload);
    final eventCallId = _callIdFromPayload(payload);
    if (!_matchesCurrentCall(
      eventCallId,
      eventSessionId: _sessionIdFromPayload(payload),
      eventRevision: _revisionFromPayload(payload),
      requireSession: true,
    )) {
      debugPrint(
        '[CallService] Ignoring call_connected for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }
    final connectedAt = DateTime.tryParse(
      payload['connected_at']?.toString() ?? '',
    );
    if (connectedAt == null || state.callInfo == null) {
      debugPrint('[CallService] call_connected missing connected_at');
      return;
    }
    final eventRevision = _revisionFromPayload(payload);
    state = state.copyWith(
      callInfo: state.callInfo!.copyWith(
        revision: eventRevision,
        connectTime: connectedAt,
      ),
    );
    _markCallConnected(
      connectedAt: connectedAt,
      source: 'call_connected',
    );
    final acceptAttempt = _activeAcceptAttempt;
    if (acceptAttempt != null &&
        acceptAttempt.callId == eventCallId &&
        !acceptAttempt.resolutionResult.isCompleted) {
      // WebSocket delivery can win the race against the media-ready HTTP
      // response. Once this immutable call is connected, answer UI may advance
      // immediately and the timeout must no longer be able to roll it back.
      acceptAttempt.resolutionResult.complete(true);
    }
    if (state.callInfo != null) {
      _startConnectedClock(state.callInfo!, forceRebase: true);
    }
  }

  Future<void> handleCallRejected(
    String reason, [
    Map<String, dynamic>? payload,
  ]) async {
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(
      eventCallId,
      eventSessionId: payload == null ? null : _sessionIdFromPayload(payload),
      eventRevision: payload == null ? null : _revisionFromPayload(payload),
      requireSession: true,
    )) {
      debugPrint(
        '[CallService] Ignoring call_rejected for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }
    await _finishCallLocally(reason);
  }

  Future<void> handleCallCancelled([Map<String, dynamic>? payload]) async {
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(
      eventCallId,
      eventSessionId: payload == null ? null : _sessionIdFromPayload(payload),
      eventRevision: payload == null ? null : _revisionFromPayload(payload),
      requireSession: true,
    )) {
      debugPrint(
        '[CallService] Ignoring call_cancelled for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }
    _cancelIncomingCallTimeout();
    await _finishCallLocally('cancelled');
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    unawaited(_callEndTone.dispose());
    unawaited(_incomingCallTone.dispose());
    unawaited(_outgoingCallTone.dispose());
    _isDisposed = true;
    final acceptAttempt = _activeAcceptAttempt;
    acceptAttempt?.timer?.cancel();
    if (acceptAttempt != null && !acceptAttempt.cancelToken.isCancelled) {
      acceptAttempt.cancelToken.cancel('service_disposed');
    }
    _activeAcceptAttempt = null;

    if (state.isInCall) {
      endCall(reason: 'service_disposed');
    }

    _callKitSubscription?.cancel();
    _callKitSubscription = null;

    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();

    _callTimer?.cancel();
    _callTimer = null;
    _cancelOutgoingCallTimeout();
    _incomingCallTimer?.cancel();
    _incomingCallTimer = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _cancelReconnectTimer();
    _stopCallHeartbeatTimer();

    if (_eventHandler != null && _engine != null) {
      _engine!.unregisterEventHandler(_eventHandler!);
      _eventHandler = null;
    }
    _engine?.release();
    _engine = null;
    unawaited(_disconnectLiveKitRoom());
    final preparedLiveKitRoom = _preparedLiveKitRoom;
    _preparedLiveKitRoom = null;
    _preparedLiveKitFuture = null;
    _preparedLiveKitUrl = null;
    if (preparedLiveKitRoom != null) {
      unawaited(preparedLiveKitRoom.dispose());
    }

    onIncomingCall = null;
    onCallConnected = null;
    onCallEnded = null;
    onCallFailed = null;
    onCallAccepted = null;

    WakelockPlus.disable();
    super.dispose();
  }
}

/// Provider
final callServiceProvider =
    StateNotifierProvider<CallService, CallServiceState>((ref) {
  final api = ref.watch(apiClientProvider);
  final wsService = ref.watch(webSocketServiceProvider.notifier);
  final isAuthenticated = ref.watch(
    authServiceProvider.select(
      (state) => state.status == AuthStatus.authenticated,
    ),
  );
  return CallService(api, wsService, prefetchConfig: isAuthenticated);
});

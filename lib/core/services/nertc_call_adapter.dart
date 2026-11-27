import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nertc_core/nertc_core.dart';

/// Small media-only adapter so NERTC lifecycle does not leak into call
/// signaling, CallKit, or the existing page state machine.
///
/// Yunxin Flutter official flow (nertc_core):
/// create(appKey) → enable media → joinChannel(token, channelName, uid)
/// onUserVideoStart → subscribeRemoteVideoStream + NERtcVideoView(uid)
///
/// This project uses **basic Token** (暖鄰对接文档). Basic Token is passed to
/// [joinChannel]; [NERtcEngine.updatePermissionKey] is for advanced Token only
/// and must not be used for /rtc/nertc/renew.
class NertcCallAdapter with NERtcChannelEventCallback {
  NertcCallAdapter({
    required this.onRemoteJoined,
    required this.onRemoteLeft,
    required this.onRemoteVideoChanged,
    required this.onConnectionLost,
    this.onJoinSuccess,
  });

  final void Function(int uid) onRemoteJoined;
  final void Function(int uid) onRemoteLeft;
  final void Function(int uid, bool enabled) onRemoteVideoChanged;
  final VoidCallback onConnectionLost;
  final VoidCallback? onJoinSuccess;

  final NERtcEngine engine = NERtcEngine.instance;
  bool _created = false;
  bool _joined = false;
  bool _videoEnabled = false;
  String? _appKey;

  /// Call page rebuilds every second (duration timer). Returning a *new*
  /// [NERtcVideoView] each time re-runs setupRemoteVideoCanvas and blacks out
  /// remote video. Cache the same widget instances for the call lifetime.
  Widget? _localViewWidget;
  Widget? _remoteViewWidget;
  int? _remoteViewUid;
  final ValueNotifier<bool> _localMirror = ValueNotifier<bool>(true);

  Future<void> initialize(String appKey) async {
    if (_created && _appKey == appKey) return;
    if (_created && _appKey != appKey) {
      await leave();
    }
    // 云信默认 videoAutoSubscribe=false；1v1 打开自动订阅，事件里再显式订一次。
    final result = await engine.create(
      appKey: appKey,
      channelEventCallback: this,
      options: const NERtcOptions(
        audioAutoSubscribe: true,
        videoAutoSubscribe: true,
      ),
    );
    if (result != 0) throw StateError('NERTC initialization failed: $result');
    _created = true;
    _appKey = appKey;
    await engine.enableLocalAudio(true);
  }

  Future<void> join({
    required String token,
    required String channelName,
    required int uid,
    required bool video,
  }) async {
    if (!_created) throw StateError('NERTC is not initialized');
    _videoEnabled = video;
    if (video) {
      await engine.enableLocalVideo(true);
      await engine.muteLocalVideoStream(false);
    } else {
      await engine.enableLocalVideo(false);
      await engine.muteLocalVideoStream(true);
    }
    final result = await engine.joinChannel(token, channelName, uid);
    if (result != 0) throw StateError('NERTC join failed: $result');
    _joined = true;
    // Re-assert publish after join — some SDK builds drop the pre-join mute
    // state when the channel session starts.
    if (video) {
      await engine.enableLocalVideo(true);
      await engine.muteLocalVideoStream(false);
    }
  }

  Future<void> subscribeRemoteVideo(int uid) async {
    if (!_created) return;
    final result = await engine.subscribeRemoteVideoStream(
      uid,
      NERtcRemoteVideoStreamType.high,
      true,
    );
    debugPrint(
      '[NertcAdapter] subscribeRemoteVideo uid=$uid result=$result',
    );
  }

  /// Basic-token renew: leave then rejoin with the new server token.
  Future<void> rejoinWithToken({
    required String token,
    required String channelName,
    required int uid,
    required bool video,
  }) async {
    if (!_created) throw StateError('NERTC is not initialized');
    if (_joined) {
      try {
        await engine.leaveChannel();
      } finally {
        _joined = false;
      }
    }
    // Keep existing video view widgets; only media session is refreshed.
    await join(
      token: token,
      channelName: channelName,
      uid: uid,
      video: video,
    );
    final remoteUid = _remoteViewUid;
    if (remoteUid != null && video) {
      unawaited(subscribeRemoteVideo(remoteUid));
    }
  }

  Future<void> setMuted(bool muted) async {
    if (_created) await engine.muteLocalAudioStream(muted);
  }

  Future<void> setVideoEnabled(bool enabled) async {
    if (!_created) return;
    _videoEnabled = enabled;
    await engine.enableLocalVideo(enabled);
    await engine.muteLocalVideoStream(!enabled);
  }

  Future<void> switchCamera() async {
    if (_created) await engine.deviceManager.switchCamera();
  }

  Future<void> setSpeakerphoneOn(bool enabled) async {
    if (_created) await engine.deviceManager.setSpeakerphoneOn(enabled);
  }

  Future<void> leave() async {
    if (_joined) {
      try {
        await engine.leaveChannel();
      } finally {
        _joined = false;
      }
    }
    _clearCachedViews();
    if (_created) {
      await engine.release();
      _created = false;
      _appKey = null;
    }
    _videoEnabled = false;
  }

  void _clearCachedViews() {
    _localViewWidget = null;
    _remoteViewWidget = null;
    _remoteViewUid = null;
  }

  Widget localView() {
    return _localViewWidget ??= NERtcVideoView.withInternalRenderer(
      key: const ValueKey('nertc_local_view'),
      mirrorListenable: _localMirror,
      fitType: NERtcVideoViewFitType.cover,
    );
  }

  Widget remoteView(int uid) {
    if (_remoteViewWidget != null && _remoteViewUid == uid) {
      return _remoteViewWidget!;
    }
    _remoteViewUid = uid;
    _remoteViewWidget = NERtcVideoView.withInternalRenderer(
      key: ValueKey('nertc_remote_view_$uid'),
      uid: uid,
      fitType: NERtcVideoViewFitType.cover,
    );
    // Ensure subscribe even if the UI mounts the canvas slightly late.
    unawaited(subscribeRemoteVideo(uid));
    return _remoteViewWidget!;
  }

  @override
  void onJoinChannel(int result, int channelId, int elapsed, int uid) {
    debugPrint(
      '[NertcAdapter] onJoinChannel result=$result channelId=$channelId uid=$uid',
    );
    if (result == 0) {
      onJoinSuccess?.call();
    }
  }

  @override
  void onUserJoined(int uid, NERtcUserJoinExtraInfo? joinExtraInfo) {
    debugPrint('[NertcAdapter] onUserJoined uid=$uid');
    onRemoteJoined(uid);
    // Peer may already be publishing video before videoStart arrives.
    if (_videoEnabled) {
      unawaited(subscribeRemoteVideo(uid));
    }
  }

  @override
  void onUserLeave(
    int uid,
    int reason,
    NERtcUserLeaveExtraInfo? leaveExtraInfo,
  ) {
    debugPrint('[NertcAdapter] onUserLeave uid=$uid reason=$reason');
    if (_remoteViewUid == uid) {
      _remoteViewWidget = null;
      _remoteViewUid = null;
    }
    onRemoteLeft(uid);
  }

  @override
  void onUserVideoStart(int uid, int maxProfile) {
    debugPrint(
      '[NertcAdapter] onUserVideoStart uid=$uid maxProfile=$maxProfile',
    );
    // 官方: canvas(NERtcVideoView) + subscribeRemoteVideoStream，缺一则黑屏。
    unawaited(subscribeRemoteVideo(uid));
    onRemoteVideoChanged(uid, true);
  }

  @override
  void onUserVideoStop(int uid) {
    debugPrint('[NertcAdapter] onUserVideoStop uid=$uid');
    if (_created) {
      unawaited(
        engine.subscribeRemoteVideoStream(
          uid,
          NERtcRemoteVideoStreamType.high,
          false,
        ),
      );
    }
    onRemoteVideoChanged(uid, false);
  }

  @override
  void onDisconnect(int reason) {
    debugPrint('[NertcAdapter] onDisconnect reason=$reason');
    onConnectionLost();
  }

  @override
  void onReconnectingStart() => onConnectionLost();
}

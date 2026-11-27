// 文件用途：封装 AudioplayersOutgoingCallToneBackend 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AudioplayersOutgoingCallToneBackend 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 呼出回铃音后端；服务层借此独立测试异步开始、停止和释放顺序。
abstract interface class OutgoingCallToneBackend {
  Future<void> playLoop(String assetPath, {required double volume});

  Future<void> stop();

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  Future<void> dispose();
}

// 关键声明：outgoing call tone service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class AudioplayersOutgoingCallToneBackend implements OutgoingCallToneBackend {
  AudioplayersOutgoingCallToneBackend({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playLoop(
    String assetPath, {
    required double volume,
  }) async {
    // Ringback must stay audible on Samsung One UI while RTC is already in
    // MODE_IN_COMMUNICATION. USAGE_NOTIFICATION_RINGTONE + AUDIOFOCUS_NONE is
    // often silenced there; VOICE_COMMUNICATION_SIGNALLING is the telephony
    // ringback usage and survives in-communication sessions. Transient ducking
    // focus still lets NERTC/Agora keep the VoIP path.
    await _player.setAudioContext(
      const AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          audioMode: AndroidAudioMode.inCommunication,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.voiceCommunicationSignalling,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(volume);
    await _player.play(AssetSource(assetPath));
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } finally {
      // 部分 Android ROM 在 stop 返回后仍短暂持有回铃音播放器，释放底层
      // 资源可以避免接通或挂断后残留循环播放。
      await _player.release();
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}

/// 在呼出电话等待接听期间持有本地回铃音。
///
/// 服务生命周期独立于通话页面，窗口最小化或 Widget 重建不会提前中断声音。
/// start、stop 与 dispose 通过同一异步队列串行执行，避免旧 start 覆盖新状态。
class OutgoingCallToneService {
  OutgoingCallToneService({OutgoingCallToneBackend? backend})
      : _backend = backend ?? AudioplayersOutgoingCallToneBackend();

  static const String _assetPath = 'sounds/ringtone.mp3';
  static const double _volume = 1.0;

  final OutgoingCallToneBackend _backend;
  // 队列保证底层 AudioPlayer 不会被并发调用。
  Future<void> _backendQueue = Future<void>.value();
  bool _shouldPlay = false;
  bool _disposed = false;
  int _operation = 0;

  bool get isPlaying => _shouldPlay && !_disposed;

  Future<void> start() {
    if (_disposed || _shouldPlay) return _backendQueue;

    _shouldPlay = true;
    // stop/dispose 会推进令牌，使尚未执行的 start 直接失效。
    final operation = ++_operation;
    return _enqueue(() async {
      if (_disposed || !_shouldPlay || operation != _operation) return;
      try {
        await _backend.playLoop(_assetPath, volume: _volume);
      } catch (error) {
        if (operation == _operation) {
          _shouldPlay = false;
        }
        debugPrint('[OutgoingCallTone] Start error: $error');
      }
    });
  }

  Future<void> stop() {
    if (_disposed) return _backendQueue;

    final needsStop = _shouldPlay;
    _shouldPlay = false;
    _operation += 1;
    if (!needsStop) return _backendQueue;

    return _enqueue(() async {
      try {
        await _backend.stop();
      } catch (error) {
        debugPrint('[OutgoingCallTone] Stop error: $error');
      }
    });
  }

  Future<void> dispose() {
    if (_disposed) return _backendQueue;

    _disposed = true;
    _shouldPlay = false;
    _operation += 1;
    return _enqueue(() async {
      try {
        await _backend.stop();
      } catch (error) {
        debugPrint('[OutgoingCallTone] Dispose stop error: $error');
      }
      try {
        await _backend.dispose();
      } catch (error) {
        debugPrint('[OutgoingCallTone] Dispose error: $error');
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final scheduled = _backendQueue.then((_) => operation());
    // 保持内部队列可继续执行，同时让本次 scheduled 仍向调用方报告原始错误。
    _backendQueue = scheduled.catchError((Object error, StackTrace stack) {
      debugPrint('[OutgoingCallTone] Queue error: $error');
    });
    return scheduled;
  }
}

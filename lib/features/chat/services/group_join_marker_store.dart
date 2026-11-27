// 文件用途：本地持久化「刚加入群/频道」标记，供会话列表在无服务端预览时兜底展示。
// 核心逻辑：按账号隔离写入 SharedPreferences；有真实消息后清除；刷新会话列表时按标记回填预览。
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/app_localizations.dart';

String groupJoinPreviewText({AppLanguage language = AppLanguage.zhCN}) {
  switch (language) {
    case AppLanguage.en:
      return 'Joined the group';
    case AppLanguage.zhTW:
      return '已加入群組';
    case AppLanguage.zhCN:
      return '已加入群组';
  }
}

String groupJoinEmptyTitleText({AppLanguage language = AppLanguage.zhCN}) {
  switch (language) {
    case AppLanguage.en:
      return 'You joined this group';
    case AppLanguage.zhTW:
      return '你已加入本群';
    case AppLanguage.zhCN:
      return '你已加入本群';
  }
}

String groupJoinEmptySubtitleText({
  AppLanguage language = AppLanguage.zhCN,
  bool muted = false,
}) {
  if (muted) {
    switch (language) {
      case AppLanguage.en:
        return 'Messaging is currently restricted in this group.';
      case AppLanguage.zhTW:
        return '目前無法發言，但仍可查看群聊。';
      case AppLanguage.zhCN:
        return '当前无法发言，但仍可查看群聊。';
    }
  }
  switch (language) {
    case AppLanguage.en:
      return 'New messages will appear here.';
    case AppLanguage.zhTW:
      return '有新消息時會顯示在這裡。';
    case AppLanguage.zhCN:
      return '有新消息时会显示在这里。';
  }
}

@visibleForTesting
bool shouldApplyGroupJoinPreview(String? lastMessage) {
  return (lastMessage ?? '').trim().isEmpty;
}

@visibleForTesting
bool isGroupJoinPreviewText(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return false;
  return text == '已加入群组' ||
      text == '已加入群組' ||
      text == 'Joined the group';
}

/// 账号隔离的进群标记仓库。只存 chatId → 加入时间，不造假消息。
class GroupJoinMarkerStore {
  GroupJoinMarkerStore(this._accountId);

  final String _accountId;
  final Map<String, DateTime> _markers = <String, DateTime>{};
  bool _loaded = false;
  Future<void>? _loadFuture;

  String get _storageKey {
    final digest = sha256.convert(utf8.encode(_accountId.trim()));
    return 'acct_v1_${digest}_group_join_markers_v1';
  }

  Map<String, DateTime> get markers => Map<String, DateTime>.unmodifiable(_markers);

  bool has(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return false;
    return _markers.containsKey(id);
  }

  DateTime? joinedAt(String chatId) => _markers[chatId.trim()];

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    if (_accountId.trim().isEmpty) {
      _loaded = true;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _markers
        ..clear()
        ..addAll(_decode(raw));
    } catch (error) {
      debugPrint('[GroupJoinMarker] load failed: $error');
    } finally {
      _loaded = true;
    }
  }

  Future<void> markJoined(String chatId, {DateTime? at}) async {
    final id = chatId.trim();
    if (id.isEmpty || _accountId.trim().isEmpty) return;
    await ensureLoaded();
    _markers[id] = at ?? DateTime.now();
    await _persist();
  }

  Future<void> clear(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    await ensureLoaded();
    if (_markers.remove(id) == null) return;
    await _persist();
  }

  Future<void> clearMany(Iterable<String> chatIds) async {
    await ensureLoaded();
    var changed = false;
    for (final chatId in chatIds) {
      final id = chatId.trim();
      if (id.isEmpty) continue;
      if (_markers.remove(id) != null) changed = true;
    }
    if (changed) await _persist();
  }

  Future<void> _persist() async {
    if (_accountId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_markers.isEmpty) {
        await prefs.remove(_storageKey);
      } else {
        await prefs.setString(_storageKey, jsonEncode(_encode(_markers)));
      }
    } catch (error) {
      debugPrint('[GroupJoinMarker] persist failed: $error');
    }
  }

  static Map<String, dynamic> _encode(Map<String, DateTime> markers) {
    return <String, dynamic>{
      for (final entry in markers.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    };
  }

  static Map<String, DateTime> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, DateTime>{};
      final result = <String, DateTime>{};
      decoded.forEach((key, value) {
        final id = key.toString().trim();
        if (id.isEmpty) return;
        final parsed = DateTime.tryParse(value?.toString() ?? '');
        if (parsed == null) return;
        result[id] = parsed.toLocal();
      });
      return result;
    } catch (_) {
      return <String, DateTime>{};
    }
  }
}

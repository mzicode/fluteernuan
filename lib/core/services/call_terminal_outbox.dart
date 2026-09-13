import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CallTerminalAction {
  const CallTerminalAction({
    required this.ownerUserId,
    required this.callId,
    required this.sessionId,
    required this.action,
    required this.reason,
    required this.createdAt,
  });

  final String ownerUserId;
  final int callId;
  final String sessionId;
  final String action;
  final String reason;
  final DateTime createdAt;

  String get identity => '$ownerUserId:$callId:$sessionId';
  String get deliveryIdentity =>
      '$identity:$action:${createdAt.toUtc().toIso8601String()}';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'owner_user_id': ownerUserId,
        'call_id': callId,
        'session_id': sessionId,
        'action': action,
        'reason': reason,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static CallTerminalAction? fromJson(dynamic value) {
    if (value is! Map) return null;
    final callId = value['call_id'];
    final createdAt = DateTime.tryParse(value['created_at']?.toString() ?? '');
    final owner = value['owner_user_id']?.toString().trim() ?? '';
    final action = value['action']?.toString().trim() ?? '';
    if (callId is! num || callId <= 0 || createdAt == null || owner.isEmpty) {
      return null;
    }
    if (action != 'cancel' && action != 'end' && action != 'reject') {
      return null;
    }
    return CallTerminalAction(
      ownerUserId: owner,
      callId: callId.toInt(),
      sessionId: value['session_id']?.toString().trim() ?? '',
      action: action,
      reason: value['reason']?.toString().trim() ?? '',
      createdAt: createdAt.toUtc(),
    );
  }
}

/// Crash-safe terminal signalling queue. Entries are partitioned by owner and
/// are never returned to another signed-in account.
class CallTerminalOutbox {
  CallTerminalOutbox({
    this.retention = const Duration(hours: 24),
    this.maxEntries = 64,
  });

  static const String storageKey = 'call_terminal_outbox_v1';
  final Duration retention;
  final int maxEntries;
  Future<void> _writeTail = Future<void>.value();

  Future<List<CallTerminalAction>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return <CallTerminalAction>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CallTerminalAction>[];
      return decoded
          .map(CallTerminalAction.fromJson)
          .whereType<CallTerminalAction>()
          .toList();
    } catch (_) {
      return <CallTerminalAction>[];
    }
  }

  Future<void> _writeAll(List<CallTerminalAction> actions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(actions.map((action) => action.toJson()).toList()),
    );
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.catchError((_) {});
    return result;
  }

  Future<void> enqueue(CallTerminalAction action) => _serialize(() async {
        final actions = await _readAll();
        actions.removeWhere((item) => item.identity == action.identity);
        actions.add(action);
        actions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (actions.length > maxEntries) {
          actions.removeRange(0, actions.length - maxEntries);
        }
        await _writeAll(actions);
      });

  Future<void> remove(CallTerminalAction action) => _serialize(() async {
        final actions = await _readAll();
        actions.removeWhere(
          (item) => item.deliveryIdentity == action.deliveryIdentity,
        );
        await _writeAll(actions);
      });

  Future<void> removeOwner(String ownerUserId) => _serialize(() async {
        final normalized = ownerUserId.trim();
        if (normalized.isEmpty) return;
        final actions = await _readAll();
        actions.removeWhere((item) => item.ownerUserId == normalized);
        await _writeAll(actions);
      });

  Future<List<CallTerminalAction>> loadForOwner(
    String ownerUserId, {
    DateTime? now,
  }) async {
    await _writeTail;
    final current = (now ?? DateTime.now()).toUtc();
    final actions = await _readAll();
    return actions
        .where((action) =>
            action.ownerUserId == ownerUserId &&
            current.difference(action.createdAt) <= retention)
        .toList();
  }
}

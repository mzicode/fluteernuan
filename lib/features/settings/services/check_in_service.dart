import '../../../core/services/api/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CheckInStatus {
  final bool checkedIn;
  final DateTime? date;
  final int streakDays;
  final int totalDays;
  final bool kycRequired;
  final String? kycStatus;
  final bool canCheckIn;
  final String? blockReason;
  final String? action;

  const CheckInStatus({
    this.checkedIn = false,
    this.date,
    this.streakDays = 0,
    this.totalDays = 0,
    this.kycRequired = false,
    this.kycStatus,
    this.canCheckIn = true,
    this.blockReason,
    this.action,
  });

  bool get needsRealNamePage =>
      kycRequired &&
      !canCheckIn &&
      !checkedIn &&
      kycStatus != 'pending' &&
      kycStatus != 'approved' &&
      (action == 'open_real_name' ||
          kycStatus == 'not_submitted' ||
          kycStatus == 'rejected');

  bool get waitingForReview =>
      kycRequired && !canCheckIn && action == 'wait_for_review';

  factory CheckInStatus.fromJson(Map<String, dynamic> json) {
    final checkedIn = json['checked_in'] == true || json['checked_in'] == 1;
    final hasCanCheckIn = json.containsKey('can_check_in');
    return CheckInStatus(
      checkedIn: checkedIn,
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      totalDays: (json['total_days'] as num?)?.toInt() ?? 0,
      kycRequired: json['kyc_required'] == true,
      kycStatus: json['kyc_status']?.toString(),
      canCheckIn: hasCanCheckIn ? json['can_check_in'] == true : !checkedIn,
      blockReason: json['check_in_block_reason']?.toString(),
      action: json['check_in_action']?.toString(),
    );
  }
}

class CheckInFailure {
  final String? errorCode;
  final int? httpStatus;
  final String message;
  final String? kycStatus;
  final String? action;

  const CheckInFailure({
    this.errorCode,
    this.httpStatus,
    this.message = '',
    this.kycStatus,
    this.action,
  });

  bool get isKycRequired => errorCode == 'KYC_REQUIRED';

  bool get isKycUnavailable => errorCode == 'KYC_CHECK_UNAVAILABLE';

  bool get isKycStateChanged => errorCode == 'KYC_STATE_CHANGED';

  static CheckInFailure fromResponse(ApiResponse<Object?> response) {
    final raw = response.rawData ?? const <String, dynamic>{};
    return CheckInFailure(
      errorCode: response.errorCode,
      httpStatus: response.httpStatus ?? response.code,
      message: response.message,
      kycStatus: raw['kyc_status']?.toString(),
      action: raw['action']?.toString(),
    );
  }
}

class CheckInHistoryItem {
  final DateTime date;

  const CheckInHistoryItem({required this.date});

  static DateTime? _parseCheckDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    // 签到日期是北京时间的“日历日”，不能通过 DateTime.toLocal() 处理
    // 带 UTC 时间戳的 created_at，否则跨零点时会落到错误日期。
    final datePart = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(datePart);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }
    return DateTime.tryParse(raw);
  }

  static CheckInHistoryItem? tryFromJson(dynamic value) {
    if (value is String) {
      final date = _parseCheckDate(value);
      return date == null ? null : CheckInHistoryItem(date: date);
    }
    final json = Map<String, dynamic>.from(value as Map);
    final rawDate = json['check_date'] ?? json['date'] ?? json['check_in_date'];
    final date = _parseCheckDate(rawDate);
    return date == null ? null : CheckInHistoryItem(date: date);
  }
}

class CheckInService {
  final ApiClient _api;

  const CheckInService(this._api);

  Future<ApiResponse<CheckInStatus>> getStatus() => _api.get<CheckInStatus>(
        '/check-in/status',
        fromJson: (data) =>
            CheckInStatus.fromJson(Map<String, dynamic>.from(data as Map)),
      );

  Future<ApiResponse<CheckInStatus>> checkIn() => _api.post<CheckInStatus>(
        '/check-in',
        fromJson: (data) =>
            CheckInStatus.fromJson(Map<String, dynamic>.from(data as Map)),
      );

  Future<ApiResponse<List<CheckInHistoryItem>>> getHistory(
          {int page = 1, int pageSize = 20}) =>
      _api.get<List<CheckInHistoryItem>>(
        '/check-in/history?page=$page&page_size=$pageSize',
        fromJson: (data) {
          final rawList = data is List
              ? data
              : ((data as Map)['list'] ?? (data as Map)['items'] ?? const []);
          return (rawList as List)
              .map(CheckInHistoryItem.tryFromJson)
              .whereType<CheckInHistoryItem>()
              .toList();
        },
      );
}

final checkInServiceProvider = Provider<CheckInService>((ref) {
  return CheckInService(ref.watch(apiClientProvider));
});

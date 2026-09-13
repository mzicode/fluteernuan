import '../../../core/services/api/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CheckInStatus {
  final bool checkedIn;
  final DateTime? date;
  final int streakDays;
  final int totalDays;

  const CheckInStatus(
      {this.checkedIn = false,
      this.date,
      this.streakDays = 0,
      this.totalDays = 0});

  factory CheckInStatus.fromJson(Map<String, dynamic> json) => CheckInStatus(
        checkedIn: json['checked_in'] == true || json['checked_in'] == 1,
        date: DateTime.tryParse(json['date']?.toString() ?? ''),
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
        totalDays: (json['total_days'] as num?)?.toInt() ?? 0,
      );
}

class CheckInHistoryItem {
  final DateTime date;

  const CheckInHistoryItem({required this.date});

  static CheckInHistoryItem? tryFromJson(dynamic value) {
    if (value is String) {
      final date = DateTime.tryParse(value);
      return date == null ? null : CheckInHistoryItem(date: date);
    }
    final json = Map<String, dynamic>.from(value as Map);
    final rawDate = json['date'] ?? json['check_in_date'] ?? json['created_at'];
    final date = DateTime.tryParse(rawDate?.toString() ?? '');
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

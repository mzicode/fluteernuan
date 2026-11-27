import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/api/api_client.dart';

class RealNameStatus {
  final String status;
  final bool canSubmit;
  final String maskedRealName;
  final String maskedIdNumber;
  final String idNumberLast4;
  final String rejectReason;
  final String submittedAt;
  final String reviewedAt;

  const RealNameStatus({
    this.status = 'unsubmitted',
    this.canSubmit = true,
    this.maskedRealName = '',
    this.maskedIdNumber = '',
    this.idNumberLast4 = '',
    this.rejectReason = '',
    this.submittedAt = '',
    this.reviewedAt = '',
  });

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  bool get canEdit => status == 'unsubmitted' || isRejected;

  /// 将接口返回的 ISO 时间（含 T/Z）格式化为北京时间 `yyyy-MM-dd HH:mm:ss`
  static String formatBeijingDateTime(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final beijing = parsed.toUtc().add(const Duration(hours: 8));
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(beijing);
  }

  factory RealNameStatus.fromJson(Map<String, dynamic> json) {
    String text(List<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    return RealNameStatus(
      status: text(const ['status']).toLowerCase().isEmpty
          ? 'unsubmitted'
          : text(const ['status']).toLowerCase(),
      canSubmit: json['can_submit'] != false,
      maskedRealName:
          text(const ['masked_real_name', 'real_name_masked', 'real_name']),
      maskedIdNumber: text(const ['masked_id_number', 'id_number_masked']),
      idNumberLast4: text(const ['id_number_last4', 'id_card_last4']),
      rejectReason: text(const ['reject_reason', 'reason']),
      submittedAt: formatBeijingDateTime(
        text(const ['submitted_at', 'created_at']),
      ),
      reviewedAt: formatBeijingDateTime(
        text(const ['reviewed_at', 'updated_at']),
      ),
    );
  }
}

class RealNameService {
  final ApiClient _api;

  RealNameService(this._api);

  Future<ApiResponse<RealNameStatus>> getStatus() {
    return _api.get<RealNameStatus>(
      '/real-name/status',
      fromJson: (data) =>
          RealNameStatus.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<ApiResponse<RealNameStatus>> submit({
    required String realName,
    required String idNumber,
    required String idFrontUrl,
    required String idBackUrl,
  }) {
    return _api.post<RealNameStatus>(
      '/real-name/submit',
      data: {
        'real_name': realName.trim(),
        'id_number': idNumber.trim().toUpperCase(),
        'id_front_url': idFrontUrl.trim(),
        'id_back_url': idBackUrl.trim(),
      },
      fromJson: (data) => data is Map
          ? RealNameStatus.fromJson(Map<String, dynamic>.from(data))
          : const RealNameStatus(status: 'pending', canSubmit: false),
    );
  }
}

final realNameServiceProvider = Provider<RealNameService>((ref) {
  return RealNameService(ref.watch(apiClientProvider));
});

final realNameStatusProvider = FutureProvider<RealNameStatus>((ref) async {
  final response = await ref.watch(realNameServiceProvider).getStatus();
  if (!response.isSuccess || response.data == null) {
    throw StateError(response.message);
  }
  return response.data!;
});

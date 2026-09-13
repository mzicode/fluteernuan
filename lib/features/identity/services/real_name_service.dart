import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      submittedAt: text(const ['submitted_at', 'created_at']),
      reviewedAt: text(const ['reviewed_at', 'updated_at']),
    );
  }
}

bool isValidMainlandChinaIdNumber(String input) {
  final value = input.trim().toUpperCase();
  if (!RegExp(r'^\d{17}[\dX]$').hasMatch(value)) return false;

  final year = int.tryParse(value.substring(6, 10));
  final month = int.tryParse(value.substring(10, 12));
  final day = int.tryParse(value.substring(12, 14));
  if (year == null || month == null || day == null) return false;
  try {
    final birthday = DateTime(year, month, day);
    if (birthday.year != year ||
        birthday.month != month ||
        birthday.day != day ||
        birthday.isAfter(DateTime.now())) {
      return false;
    }
  } catch (_) {
    return false;
  }

  const weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  const checks = ['1', '0', 'X', '9', '8', '7', '6', '5', '4', '3', '2'];
  var sum = 0;
  for (var index = 0; index < 17; index++) {
    sum += int.parse(value[index]) * weights[index];
  }
  return checks[sum % 11] == value[17];
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

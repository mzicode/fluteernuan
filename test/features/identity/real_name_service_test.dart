import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/identity/services/real_name_service.dart';

void main() {
  test('parses all real-name review states and masked fields', () {
    final status = RealNameStatus.fromJson(const {
      'status': 'rejected',
      'can_submit': true,
      'masked_real_name': '张*',
      'id_number_last4': '002X',
      'reject_reason': '图片不清晰',
    });

    expect(status.isRejected, isTrue);
    expect(status.canEdit, isTrue);
    expect(status.maskedRealName, '张*');
    expect(status.idNumberLast4, '002X');
    expect(status.rejectReason, '图片不清晰');
  });

  test('pending and approved states never allow another submission', () {
    final pending = RealNameStatus.fromJson(const {'status': 'pending'});
    final approved = RealNameStatus.fromJson(const {'status': 'approved'});

    expect(pending.canEdit, isFalse);
    expect(approved.canEdit, isFalse);
  });

  test('formats submitted_at and reviewed_at as Beijing wall time', () {
    final status = RealNameStatus.fromJson(const {
      'status': 'pending',
      'submitted_at': '2026-10-01T16:30:00Z',
      'reviewed_at': '2026-10-01T18:05:45.123Z',
    });

    expect(status.submittedAt, '2026-10-02 00:30:00');
    expect(status.reviewedAt, '2026-10-02 02:05:45');
    expect(status.submittedAt.contains('T'), isFalse);
    expect(status.submittedAt.contains('Z'), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/identity/services/real_name_service.dart';

void main() {
  test('validates mainland China ID checksum and birthday', () {
    expect(isValidMainlandChinaIdNumber('11010519491231002X'), isTrue);
    expect(isValidMainlandChinaIdNumber('110105194912310021'), isFalse);
    expect(isValidMainlandChinaIdNumber('11010520991231002X'), isFalse);
  });

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
}

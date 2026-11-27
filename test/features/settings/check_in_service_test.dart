import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/settings/services/check_in_service.dart';

void main() {
  test('history uses check_date instead of UTC created_at', () {
    final item = CheckInHistoryItem.tryFromJson({
      'check_date': '2026-09-14',
      'created_at': '2026-09-13T16:30:00Z',
    });

    expect(item, isNotNull);
    expect(item!.date, DateTime(2026, 9, 14));
  });

  test('history treats a calendar date as a local calendar value', () {
    final item = CheckInHistoryItem.tryFromJson({
      'check_date': '2026-09-14T00:00:00Z',
    });

    expect(item, isNotNull);
    expect(item!.date.year, 2026);
    expect(item.date.month, 9);
    expect(item.date.day, 14);
  });

  test('history does not fall back to created_at', () {
    final item = CheckInHistoryItem.tryFromJson({
      'created_at': '2026-09-14T00:00:00Z',
    });

    expect(item, isNull);
  });
}

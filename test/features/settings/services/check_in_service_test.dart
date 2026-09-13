import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/settings/services/check_in_service.dart';

void main() {
  test('check-in status parses authoritative server totals', () {
    final status = CheckInStatus.fromJson({
      'checked_in': true,
      'date': '2026-09-13',
      'streak_days': 4,
      'total_days': 19,
    });

    expect(status.checkedIn, isTrue);
    expect(status.date, DateTime(2026, 9, 13));
    expect(status.streakDays, 4);
    expect(status.totalDays, 19);
  });

  test('check-in history accepts documented and compatible date fields', () {
    final values = [
      '2026-09-13',
      {'date': '2026-09-12'},
      {'check_in_date': '2026-09-11'},
      {'created_at': '2026-09-10T08:20:00+08:00'},
      {'date': 'invalid'},
    ];

    final items = values
        .map(CheckInHistoryItem.tryFromJson)
        .whereType<CheckInHistoryItem>()
        .toList();

    expect(items, hasLength(4));
    expect(items.first.date, DateTime(2026, 9, 13));
    expect(items.last.date.day, 10);
  });
}

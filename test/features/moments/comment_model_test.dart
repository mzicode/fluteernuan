import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/moments/providers/moment_provider.dart';

void main() {
  test('Comment parses server like state and nested replies', () {
    final comment = Comment.fromJson({
      'id': 10,
      'moment_id': 3,
      'user_id': 7,
      'user_name': 'Alice',
      'content': 'root',
      'like_count': 2,
      'is_liked': true,
      'created_at': '2026-08-11T10:00:00Z',
      'replies': [
        {
          'id': 11,
          'moment_id': 3,
          'user_id': 8,
          'user_name': 'Bob',
          'content': 'reply',
          'parent_id': 10,
          'reply_to_id': 10,
          'like_count': 1,
          'is_liked': false,
          'created_at': '2026-08-11T10:01:00Z',
        },
      ],
    });

    expect(comment.id, '10');
    expect(comment.isLiked, isTrue);
    expect(comment.likeCount, 2);
    expect(comment.replies, hasLength(1));
    expect(comment.replies.single.parentId, '10');
    expect(comment.replies.single.replyToId, '10');
  });

  test('Comment copyWith updates authoritative like response only', () {
    final original = Comment(
      id: '10',
      momentId: '3',
      userId: '7',
      userName: 'Alice',
      content: 'hello',
      createdAt: DateTime.utc(2026, 8, 11),
    );

    final updated = original.copyWith(isLiked: true, likeCount: 4);

    expect(updated.isLiked, isTrue);
    expect(updated.likeCount, 4);
    expect(updated.id, original.id);
    expect(updated.content, original.content);
  });
}

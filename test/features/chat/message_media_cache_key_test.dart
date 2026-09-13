import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:customer/features/chat/providers/message_provider.dart';
import 'package:customer/features/chat/widgets/message_bubble.dart';

Widget _app(MessageItem message) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MessageBubble(message: message),
      ),
    ),
  );
}

MessageItem _mediaMessage({
  required MessageItemType type,
  required String mediaId,
  String? thumbnailMediaId,
  String? thumbnail,
}) {
  return MessageItem(
    id: 'message-$mediaId',
    chatId: 'chat-1',
    senderId: 'user-2',
    senderName: 'User 2',
    type: type,
    content: '',
    mediaId: mediaId,
    mediaUrl: 'https://s3.example.com/object?X-Amz-Signature=video',
    thumbnailMediaId: thumbnailMediaId,
    thumbnail: thumbnail,
    mediaSize: 1024,
    mediaDuration: type == MessageItemType.video ? 5000 : null,
    isOutgoing: false,
    status: MessageStatus.sent,
    createdAt: DateTime(2026, 7, 27),
    seq: 1,
  );
}

void main() {
  testWidgets('video thumbnail cache identity survives signed URL rotation',
      (tester) async {
    await tester.pumpWidget(
      _app(
        _mediaMessage(
          type: MessageItemType.video,
          mediaId: 'video-media-id',
          thumbnailMediaId: 'thumbnail-media-id',
          thumbnail:
              'https://s3.example.com/thumb.jpg?X-Amz-Signature=short-lived',
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, 'media:thumbnail-media-id');
  });

  testWidgets('image cache identity uses the private media id', (tester) async {
    await tester.pumpWidget(
      _app(
        _mediaMessage(
          type: MessageItemType.image,
          mediaId: 'image-media-id',
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, 'media:image-media-id');
  });

  testWidgets('zoomed image keeps pan gesture and base image can dismiss',
      (tester) async {
    final message = MessageItem(
      id: 'long-image-message',
      chatId: 'chat-1',
      senderId: 'user-2',
      senderName: 'User 2',
      type: MessageItemType.image,
      content: '',
      mediaUrl:
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      mediaWidth: 1080,
      mediaHeight: 4000,
      isOutgoing: false,
      status: MessageStatus.sent,
      createdAt: DateTime(2026, 8, 5),
    );

    await tester.pumpWidget(_app(message));
    await tester.tap(find.byType(CachedNetworkImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final galleryFinder = find.byType(PhotoViewGallery);
    expect(galleryFinder, findsOneWidget);

    final photoView = tester.widget<PhotoView>(find.byType(PhotoView));
    final maxScale = photoView.maxScale! as PhotoViewComputedScale;
    expect(maxScale.multiplier, 8);
    expect(photoView.scaleStateController, isNotNull);

    photoView.scaleStateController!.scaleState = PhotoViewScaleState.zoomedIn;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(galleryFinder, const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(galleryFinder, findsOneWidget);

    photoView.scaleStateController!.scaleState = PhotoViewScaleState.initial;
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      photoView.scaleStateController!.scaleState,
      PhotoViewScaleState.initial,
    );

    final dismissGesture =
        await tester.startGesture(tester.getCenter(galleryFinder));
    await dismissGesture.moveBy(const Offset(0, 180));
    await tester.pump();
    final outerTransforms = tester.widgetList<Transform>(
      find.ancestor(of: galleryFinder, matching: find.byType(Transform)),
    );
    expect(
      outerTransforms.any((widget) => widget.transform.storage[13] >= 175),
      isTrue,
    );
    await dismissGesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(galleryFinder, findsNothing);
  });
}

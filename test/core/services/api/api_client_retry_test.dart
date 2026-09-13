import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/api/api_client.dart';

void main() {
  test('multipart request data is deep-cloned after the first send', () async {
    final original = FormData.fromMap(<String, dynamic>{
      'client_request_id': 'message-1',
      'file': MultipartFile.fromBytes(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        filename: 'image.jpg',
      ),
    });

    final firstBody = await original.readAsBytes();
    final retry = cloneRequestDataForRetry(original);

    expect(retry, isA<FormData>());
    expect(identical(retry, original), isFalse);
    expect(await (retry! as FormData).readAsBytes(), firstBody);
  });

  test('ordinary retry request data keeps its original identity', () {
    final data = <String, dynamic>{'client_msg_id': 'message-1'};

    expect(identical(cloneRequestDataForRetry(data), data), isTrue);
  });

  test('startup request can explicitly disable automatic network retries', () {
    final error = DioException(
      requestOptions: RequestOptions(
        extra: const <String, dynamic>{'disableNetworkRetry': true},
      ),
      type: DioExceptionType.connectionError,
    );

    expect(shouldRetryNetworkRequest(error), isFalse);
  });

  test('ordinary connection errors remain retryable', () {
    final error = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionError,
    );

    expect(shouldRetryNetworkRequest(error), isTrue);
  });

  test('detects the macOS missing-keychain-entitlement error', () {
    final error = PlatformException(
      code: 'Unexpected security result code',
      message: 'A required entitlement is not present.',
      details: -34018,
    );

    expect(isMissingKeychainEntitlementError(error), isTrue);
  });

  test('does not downgrade storage for unrelated platform errors', () {
    final error = PlatformException(
      code: 'read_failed',
      message: 'The keychain is temporarily unavailable.',
    );

    expect(isMissingKeychainEntitlementError(error), isFalse);
  });
}

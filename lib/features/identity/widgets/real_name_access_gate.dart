import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/real_name_page.dart';
import '../services/real_name_service.dart';

class RealNameAccessGate extends ConsumerWidget {
  final Widget child;

  const RealNameAccessGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realNameStatusProvider);
    return status.when(
      data: (value) => value.isApproved
          ? child
          : RealNamePage(
              onApproved: () => ref.invalidate(realNameStatusProvider),
            ),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => RealNamePage(
        onApproved: () => ref.invalidate(realNameStatusProvider),
      ),
    );
  }
}

// 文件用途：P3 机器人应用市场与 Mini App 客户端入口。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/api_client.dart';
import '../../../shared/widgets/in_app_browser.dart';

class BotMarketListing {
  final String id;
  final String name;
  final String description;
  final String category;
  final String pricingType;
  final int priceCents;
  final int ratingMilli;
  final int installs;
  final String? miniAppId;

  const BotMarketListing({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.pricingType,
    required this.priceCents,
    required this.ratingMilli,
    required this.installs,
    this.miniAppId,
  });

  factory BotMarketListing.fromJson(Map<String, dynamic> json) {
    return BotMarketListing(
      id: (json['uuid'] ?? json['id']).toString(),
      name: json['name']?.toString() ?? '机器人应用',
      description: json['short_description']?.toString() ?? '',
      category: json['category']?.toString() ?? '其他',
      pricingType: json['pricing_type']?.toString() ?? 'free',
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      ratingMilli: (json['rating_milli'] as num?)?.toInt() ?? 0,
      installs: (json['install_count'] as num?)?.toInt() ?? 0,
      miniAppId: json['mini_app_id']?.toString(),
    );
  }
}

final botMarketplaceProvider =
    FutureProvider.autoDispose<List<BotMarketListing>>((ref) async {
  final response = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
        '/bot-marketplace',
        fromJson: (raw) => Map<String, dynamic>.from(raw as Map),
      );
  if (!response.isSuccess || response.data == null) {
    throw Exception(response.message.isEmpty ? '读取应用市场失败' : response.message);
  }
  return ((response.data!['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((item) => BotMarketListing.fromJson(Map<String, dynamic>.from(item)))
      .toList();
});

class BotMarketplacePage extends ConsumerWidget {
  const BotMarketplacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(botMarketplaceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('机器人应用市场'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(botMarketplaceProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: listings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：$error'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Center(child: Text('暂无已审核上架的机器人应用'))
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(botMarketplaceProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 76),
                  itemBuilder: (context, index) =>
                      _ListingTile(item: items[index]),
                ),
              ),
      ),
    );
  }
}

class _ListingTile extends ConsumerStatefulWidget {
  final BotMarketListing item;
  const _ListingTile({required this.item});

  @override
  ConsumerState<_ListingTile> createState() => _ListingTileState();
}

class _ListingTileState extends ConsumerState<_ListingTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final price = item.pricingType == 'free'
        ? '免费'
        : '¥${(item.priceCents / 100).toStringAsFixed(2)}${item.pricingType == 'subscription' ? '/月' : ''}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 25,
        child: Text(item.name.isEmpty ? '机' : item.name.characters.first),
      ),
      title: Row(
        children: [
          Expanded(
              child: Text(item.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(price,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
            '${item.description}\n${item.category} · ${(item.ratingMilli / 1000).toStringAsFixed(1)} 分 · ${item.installs} 次安装'),
      ),
      isThreeLine: true,
      trailing: _busy
          ? const SizedBox.square(
              dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : FilledButton.tonal(
              onPressed: _installAndOpen,
              child: Text(item.miniAppId == null ? '安装' : '打开'),
            ),
      onTap: _installAndOpen,
    );
  }

  Future<void> _installAndOpen() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final install = await api.post<Map<String, dynamic>>(
        '/bot-marketplace/${widget.item.id}/install',
        data: const <String, dynamic>{},
        fromJson: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      if (!install.isSuccess) throw Exception(install.message);
      if (widget.item.pricingType != 'free') {
        final order = await api.post<Map<String, dynamic>>(
          '/bot-orders',
          data: {
            'listing_id': widget.item.id,
            'idempotency_key':
                'mobile-${widget.item.id}-${DateTime.now().millisecondsSinceEpoch}',
          },
          fromJson: (raw) => Map<String, dynamic>.from(raw as Map),
        );
        if (!order.isSuccess || order.data == null)
          throw Exception(order.message);
        final orderId = (order.data!['uuid'] ?? '').toString();
        final paid = await api
            .post('/bot-orders/$orderId/pay', data: const <String, dynamic>{});
        if (!paid.isSuccess) throw Exception(paid.message);
      }
      if (!mounted) return;
      final miniAppId = widget.item.miniAppId;
      if (miniAppId == null || miniAppId.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('应用已安装')));
        return;
      }
      final launch = await api.post<Map<String, dynamic>>(
        '/mini-apps/$miniAppId/launch',
        data: const <String, dynamic>{},
        fromJson: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      if (!launch.isSuccess || launch.data == null)
        throw Exception(launch.message);
      final launchUrl = launch.data!['launch_url']?.toString() ?? '';
      if (launchUrl.isEmpty) throw Exception('Mini App 启动地址为空');
      final allowedDomains =
          ((launch.data!['allowed_domains'] as List?) ?? const <dynamic>[])
              .map((value) => value.toString().trim().toLowerCase())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList();
      if (allowedDomains.isEmpty) {
        throw Exception('Mini App 未配置安全域名');
      }
      final appId = launch.data!['mini_app_id']?.toString() ?? miniAppId;
      final sdkVersion = launch.data!['sdk_version']?.toString() ?? '1.0';
      if (!mounted) return;
      await InAppBrowser.open(
        context,
        launchUrl,
        title: widget.item.name,
        hideAddressBar: true,
        miniApp: MiniAppBrowserConfig(
          appId: appId,
          allowedDomains: allowedDomains,
          sdkVersion: sdkVersion,
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

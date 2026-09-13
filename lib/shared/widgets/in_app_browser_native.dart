// 文件用途：提供 in app browser 在原生平台的实现，服务于跨模块共享能力。
// 核心逻辑：实现 InAppBrowser 的原生平台分支，封装系统权限或文件能力，并保持跨平台调用契约一致。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:http_parser/http_parser.dart';

import '../../core/i18n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/android_webview_support.dart';
import 'mini_app_bridge_protocol.dart';
import 'mini_app_browser_config.dart';
import 'mini_app_navigation_policy.dart';

String _browserText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

class _DnsPolicyCacheEntry {
  final bool isPublic;
  final DateTime expiresAt;

  const _DnsPolicyCacheEntry({
    required this.isPublic,
    required this.expiresAt,
  });
}

// 关键声明：in app browser native 是原生平台实现，集中处理系统权限、文件或窗口能力，避免业务层散落平台判断。
/// 内置浏览器页面（Telegram 风格，支持下拉关闭）
class InAppBrowser extends StatefulWidget {
  final String url;
  final String? title;
  final bool hideAddressBar;
  final MiniAppBrowserConfig? miniApp;

  const InAppBrowser({
    super.key,
    required this.url,
    this.title,
    this.hideAddressBar = false,
    this.miniApp,
  });

  /// 打开内置浏览器
  static Future<void> open(BuildContext context, String url,
      {String? title,
      bool hideAddressBar = false,
      MiniAppBrowserConfig? miniApp}) async {
    // 输入可为完整 HTTP(S) URL 或裸域名；裸值统一按 HTTPS 解释。
    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return InAppBrowser(
            url: finalUrl,
            title: title,
            hideAddressBar: hideAddressBar,
            miniApp: miniApp,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<InAppBrowser> createState() => _InAppBrowserState();
}

class _InAppBrowserState extends State<InAppBrowser>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  final Dio _downloadDio = Dio();
  bool _isLoading = true;
  double _loadingProgress = 0;
  String _currentUrl = '';
  String _pageTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isSecure = false;
  bool _controllerReady = false;
  bool _miniMainButtonVisible = false;
  bool _miniMainButtonEnabled = true;
  String _miniMainButtonText = '继续';
  Brightness? _lastBrightness;
  final List<DateTime> _bridgeCalls = <DateTime>[];
  final Map<String, _DnsPolicyCacheEntry> _dnsPolicyCache = {};
  late String _bridgeNonce;

  // 下拉关闭相关
  double _dragOffset = 0;
  bool _isDragging = false;
  final double _dismissThreshold = 150; // 下拉超过这个距离就关闭

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _pageTitle = widget.title ?? '';
    _isSecure = widget.url.startsWith('https://');
    _bridgeNonce = _newBridgeNonce();
    _initWebView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness != null &&
        _lastBrightness != brightness &&
        widget.miniApp != null &&
        _controllerReady) {
      unawaited(_installMiniAppSdk());
      unawaited(_emitMiniAppEvent('themeChanged', _miniAppThemePayload()));
    }
    _lastBrightness = brightness;
  }

  void _initWebView() {
    // 仅对 HTTPS 页面启用 JS；页面后续跳转时也会重新应用同一策略。
    final jsMode = widget.url.startsWith('https://')
        ? JavaScriptMode.unrestricted
        : JavaScriptMode.disabled;

    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);
    controller
      ..setJavaScriptMode(jsMode)
      ..setBackgroundColor(Colors.white);

    if (widget.miniApp != null) {
      controller.addJavaScriptChannel(
        'CustomerMiniApp',
        onMessageReceived: (message) => _handleMiniAppBridge(message.message),
      );
    }

    controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _loadingProgress = progress / 100;
            _isLoading = progress < 100;
          });
        },
        onPageStarted: (url) {
          if (!mounted) return;
          final miniApp = widget.miniApp;
          if (miniApp != null &&
              !MiniAppNavigationPolicy.evaluate(
                url,
                miniApp.allowedDomains,
              ).allowed) {
            unawaited(_recoverFromBlockedNavigation());
            _showMiniAppSecurityBlock();
            return;
          }
          setState(() {
            _isLoading = true;
            _currentUrl = url;
            _isSecure = url.startsWith('https://');
          });
          _bridgeNonce = _newBridgeNonce();
          _controller.setJavaScriptMode(
            url.startsWith('https://')
                ? JavaScriptMode.unrestricted
                : JavaScriptMode.disabled,
          );
          if (miniApp != null) unawaited(_installMiniAppSdk());
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _currentUrl = url;
          });
          if (widget.miniApp != null) await _installMiniAppSdk();
          final title = await _controller.getTitle();
          if (title != null && title.isNotEmpty && mounted) {
            setState(() => _pageTitle = title);
          }
          await _updateNavigationState();
        },
        onUrlChange: (change) {
          final miniApp = widget.miniApp;
          final url = change.url;
          if (miniApp == null || url == null) return;
          if (!MiniAppNavigationPolicy.evaluate(
            url,
            miniApp.allowedDomains,
          ).allowed) {
            unawaited(_recoverFromBlockedNavigation());
            _showMiniAppSecurityBlock();
          }
        },
        onWebResourceError: (error) {
          debugPrint('[WebView] Error: ${error.description}');
        },
        onNavigationRequest: (request) async {
          if (widget.miniApp != null) {
            return _decideMiniAppNavigation(request.url);
          }
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (_isDownloadRequest(uri)) {
            await _downloadFile(uri);
            return NavigationDecision.prevent;
          }
          if (_shouldOpenExternally(uri)) {
            await _launchExternalUri(uri);
            return NavigationDecision.prevent;
          }
          if (uri.scheme != 'http' && uri.scheme != 'https') {
            debugPrint('[WebView] Blocked dangerous scheme: ${uri.scheme}');
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    AndroidWebViewSupport.configure(controller, logTag: 'InAppBrowser');

    _controller = controller;
    _controllerReady = true;
    final miniApp = widget.miniApp;
    if (miniApp != null &&
        !MiniAppNavigationPolicy.evaluate(
          widget.url,
          miniApp.allowedDomains,
        ).allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showMiniAppSecurityBlock();
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _controller.loadRequest(Uri.parse(widget.url));
  }

  Future<NavigationDecision> _decideMiniAppNavigation(String rawUrl) async {
    final miniApp = widget.miniApp!;
    final decision = MiniAppNavigationPolicy.evaluate(
      rawUrl,
      miniApp.allowedDomains,
    );
    if (!decision.allowed || decision.uri == null) {
      debugPrint(
        '[MiniApp] Blocked navigation: ${decision.reason} $rawUrl',
      );
      _showMiniAppSecurityBlock();
      return NavigationDecision.prevent;
    }
    if (!await _hostResolvesPublic(decision.uri!.host)) {
      debugPrint('[MiniApp] Blocked private/unresolved DNS target: $rawUrl');
      _showMiniAppSecurityBlock();
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _recoverFromBlockedNavigation() async {
    if (!_controllerReady) return;
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }
    final miniApp = widget.miniApp;
    if (miniApp != null &&
        MiniAppNavigationPolicy.evaluate(
          widget.url,
          miniApp.allowedDomains,
        ).allowed) {
      await _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  Future<bool> _hostResolvesPublic(String host) async {
    final normalized = MiniAppNavigationPolicy.normalizeHost(host);
    final literal = InternetAddress.tryParse(normalized);
    if (literal != null)
      return MiniAppNavigationPolicy.isPublicAddress(literal);

    final cached = _dnsPolicyCache[normalized];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached.isPublic;
    }
    var isPublic = false;
    try {
      final addresses = await InternetAddress.lookup(normalized)
          .timeout(const Duration(seconds: 4));
      isPublic = addresses.isNotEmpty &&
          addresses.every(MiniAppNavigationPolicy.isPublicAddress);
    } on Object catch (error) {
      debugPrint('[MiniApp] DNS validation failed for $normalized: $error');
    }
    _dnsPolicyCache[normalized] = _DnsPolicyCacheEntry(
      isPublic: isPublic,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    return isPublic;
  }

  void _showMiniAppSecurityBlock() {
    if (!mounted) return;
    _showMessage(
      _browserText(
        context,
        zhCN: '已阻止 Mini App 跳转到未授权或不安全的地址',
        zhTW: '已阻止 Mini App 跳轉至未授權或不安全的位址',
        en: 'Blocked an unauthorized or unsafe Mini App navigation',
      ),
    );
  }

  Future<void> _installMiniAppSdk() async {
    final miniApp = widget.miniApp;
    if (!_controllerReady || miniApp == null) return;
    final config = <String, dynamic>{
      'appId': miniApp.appId,
      'version': miniApp.sdkVersion,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'colorScheme':
          Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
      'themeParams': _miniAppThemeParams(),
      'safeAreaInset': <String, double>{
        'top': MediaQuery.paddingOf(context).top,
        'right': MediaQuery.paddingOf(context).right,
        'bottom': MediaQuery.paddingOf(context).bottom,
        'left': MediaQuery.paddingOf(context).left,
      },
      'bridgeNonce': _bridgeNonce,
    };
    final configJson = jsonEncode(config);
    final script = '''
(function(config) {
  if (!window.Customer) window.Customer = {};
  if (window.Customer.WebApp && window.Customer.WebApp._bridgeVersion === config.version) {
    window.Customer.WebApp._updateConfig(config);
    return;
  }
  var listeners = Object.create(null);
  var pending = Object.create(null);
  var sequence = 0;
  function emit(name, payload) {
    (listeners[name] || []).slice().forEach(function(handler) {
      try { handler(payload); } catch (_) {}
    });
    try { window.dispatchEvent(new CustomEvent('customer:' + name, { detail: payload })); } catch (_) {}
  }
  function request(method, params) {
    return new Promise(function(resolve, reject) {
      var requestId = Date.now().toString(36) + '-' + (++sequence).toString(36);
      pending[requestId] = { resolve: resolve, reject: reject };
      try {
        window.CustomerMiniApp.postMessage(JSON.stringify({
          request_id: requestId,
          bridge_nonce: config.bridgeNonce,
          method: method,
          params: params || {}
        }));
      } catch (error) {
        delete pending[requestId];
        reject(error);
      }
    });
  }
  var webApp = {
    _bridgeVersion: config.version,
    version: config.version,
    platform: config.platform,
    appId: config.appId,
    colorScheme: config.colorScheme,
    themeParams: config.themeParams,
    safeAreaInset: config.safeAreaInset,
    isExpanded: true,
    ready: function() { return request('ready'); },
    close: function() { return request('close'); },
    back: function() { return request('back'); },
    setHeaderTitle: function(title) { return request('setTitle', { title: String(title || '') }); },
    share: function(options) { return request('share', options || {}); },
    openLink: function(url) { return request('openLink', { url: String(url || '') }); },
    getTheme: function() { return request('getTheme'); },
    onEvent: function(name, handler) {
      if (typeof handler !== 'function') return;
      (listeners[name] || (listeners[name] = [])).push(handler);
    },
    offEvent: function(name, handler) {
      if (!listeners[name]) return;
      listeners[name] = listeners[name].filter(function(item) { return item !== handler; });
    },
    HapticFeedback: {
      impactOccurred: function(style) { return request('hapticFeedback', { style: style || 'light' }); }
    },
    MainButton: {
      text: '', isVisible: false, isActive: true,
      setText: function(text) { this.text = String(text || ''); request('setMainButton', { text: this.text }); return this; },
      show: function() { this.isVisible = true; request('setMainButton', { visible: true }); return this; },
      hide: function() { this.isVisible = false; request('setMainButton', { visible: false }); return this; },
      enable: function() { this.isActive = true; request('setMainButton', { enabled: true }); return this; },
      disable: function() { this.isActive = false; request('setMainButton', { enabled: false }); return this; },
      onClick: function(handler) { webApp.onEvent('mainButtonClicked', handler); return this; },
      offClick: function(handler) { webApp.offEvent('mainButtonClicked', handler); return this; }
    },
    BackButton: {
      onClick: function(handler) { webApp.onEvent('backButtonClicked', handler); return this; },
      offClick: function(handler) { webApp.offEvent('backButtonClicked', handler); return this; }
    },
    _updateConfig: function(next) {
      config = next;
      this.colorScheme = next.colorScheme;
      this.themeParams = next.themeParams;
      this.safeAreaInset = next.safeAreaInset;
    },
    _receiveEvent: function(name, payload) {
      if (name === 'bridgeResult' && payload && pending[payload.requestId]) {
        var task = pending[payload.requestId];
        delete pending[payload.requestId];
        payload.ok ? task.resolve(payload.result) : task.reject(new Error(payload.error || 'Bridge request failed'));
        return;
      }
      emit(name, payload);
    }
  };
  window.Customer.WebApp = webApp;
  emit('sdkReady', config);
})( $configJson );
''';
    try {
      await _controller.runJavaScript(script);
    } on Object catch (error) {
      debugPrint('[MiniApp] SDK injection deferred/failed: $error');
    }
  }

  Future<void> _handleMiniAppBridge(String raw) async {
    final miniApp = widget.miniApp;
    if (miniApp == null || !_isCurrentMiniAppOriginAllowed()) return;
    final request = MiniAppBridgeRequest.tryParse(raw);
    if (request == null ||
        request.bridgeNonce != _bridgeNonce ||
        !_consumeBridgeRateLimit()) {
      debugPrint('[MiniApp] Rejected invalid or rate-limited bridge message');
      return;
    }

    try {
      Object? result;
      switch (request.method) {
        case 'ready':
          result = <String, dynamic>{
            'version': miniApp.sdkVersion,
            'platform': Platform.isAndroid ? 'android' : 'ios',
          };
          await _emitMiniAppEvent('themeChanged', _miniAppThemePayload());
          break;
        case 'close':
          await _bridgeResult(
              request.requestId, true, const <String, dynamic>{});
          if (mounted) Navigator.of(context).pop();
          return;
        case 'back':
          if (await _controller.canGoBack()) {
            await _controller.goBack();
          } else {
            await _emitMiniAppEvent(
                'backButtonClicked', const <String, dynamic>{});
          }
          result = const <String, dynamic>{};
          break;
        case 'setTitle':
          final title = request.params['title']?.toString().trim() ?? '';
          if (title.isEmpty || title.length > 120) {
            throw const FormatException('Invalid title');
          }
          if (mounted) setState(() => _pageTitle = title);
          result = const <String, dynamic>{};
          break;
        case 'setMainButton':
          final text = request.params['text']?.toString().trim();
          if (text != null && (text.isEmpty || text.length > 64)) {
            throw const FormatException('Invalid main button text');
          }
          if (mounted) {
            setState(() {
              if (text != null) _miniMainButtonText = text;
              if (request.params['visible'] is bool) {
                _miniMainButtonVisible = request.params['visible'] as bool;
              }
              if (request.params['enabled'] is bool) {
                _miniMainButtonEnabled = request.params['enabled'] as bool;
              }
            });
          }
          result = const <String, dynamic>{};
          break;
        case 'share':
          final text = request.params['text']?.toString() ?? '';
          final url = request.params['url']?.toString() ?? '';
          if (text.length > 2000 || url.length > 2048) {
            throw const FormatException('Share payload too large');
          }
          if (url.isNotEmpty && !await _isSafePublicHttps(url)) {
            throw const FormatException('Unsafe share URL');
          }
          await Share.share([text.trim(), url.trim()]
              .where((value) => value.isNotEmpty)
              .join('\n'));
          result = const <String, dynamic>{};
          break;
        case 'openLink':
          final url = request.params['url']?.toString() ?? '';
          result = <String, dynamic>{
            'opened': await _openMiniAppExternalLink(url)
          };
          break;
        case 'hapticFeedback':
          await _performMiniAppHaptic(request.params['style']?.toString());
          result = const <String, dynamic>{};
          break;
        case 'getTheme':
          result = _miniAppThemePayload();
          break;
      }
      await _bridgeResult(request.requestId, true, result);
    } on Object catch (error) {
      await _bridgeResult(request.requestId, false, null, error.toString());
    }
  }

  bool _isCurrentMiniAppOriginAllowed() {
    final miniApp = widget.miniApp;
    return miniApp != null &&
        MiniAppNavigationPolicy.evaluate(
          _currentUrl,
          miniApp.allowedDomains,
        ).allowed;
  }

  bool _consumeBridgeRateLimit() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
    _bridgeCalls.removeWhere((time) => time.isBefore(cutoff));
    if (_bridgeCalls.length >= 60) return false;
    _bridgeCalls.add(DateTime.now());
    return true;
  }

  String _newBridgeNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<void> _bridgeResult(
    String requestId,
    bool ok,
    Object? result, [
    String? error,
  ]) {
    return _emitMiniAppEvent('bridgeResult', <String, dynamic>{
      'requestId': requestId,
      'ok': ok,
      if (ok) 'result': result,
      if (!ok) 'error': error ?? 'Bridge request failed',
    });
  }

  Future<void> _emitMiniAppEvent(String name, Object? payload) async {
    if (!_controllerReady || widget.miniApp == null) return;
    final script =
        'window.Customer?.WebApp?._receiveEvent(${jsonEncode(name)}, ${jsonEncode(payload)});';
    try {
      await _controller.runJavaScript(script);
    } on Object catch (error) {
      debugPrint('[MiniApp] Event delivery failed: $error');
    }
  }

  Map<String, dynamic> _miniAppThemePayload() => <String, dynamic>{
        'colorScheme':
            Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
        'themeParams': _miniAppThemeParams(),
      };

  Map<String, String> _miniAppThemeParams() {
    String hex(Color color) =>
        '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
    return <String, String>{
      'bg_color': hex(AppColors.surfaceFor(context)),
      'text_color': hex(AppColors.textPrimaryFor(context)),
      'hint_color': hex(AppColors.textSecondaryFor(context)),
      'link_color': hex(AppColors.linkFor(context)),
      'button_color': hex(Theme.of(context).colorScheme.primary),
      'button_text_color': hex(Theme.of(context).colorScheme.onPrimary),
    };
  }

  Future<bool> _isSafePublicHttps(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final decision =
        MiniAppNavigationPolicy.evaluate(rawUrl, <String>[uri.host]);
    return decision.allowed && await _hostResolvesPublic(uri.host);
  }

  Future<bool> _openMiniAppExternalLink(String rawUrl) async {
    if (!await _isSafePublicHttps(rawUrl) || !mounted) {
      throw const FormatException('Unsafe external URL');
    }
    final uri = Uri.parse(rawUrl);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('打开外部网站'),
            content: Text('即将离开 Mini App 并打开：\n${uri.host}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _performMiniAppHaptic(String? style) async {
    switch (style) {
      case 'medium':
        return HapticFeedback.mediumImpact();
      case 'heavy':
        return HapticFeedback.heavyImpact();
      case 'selection':
        return HapticFeedback.selectionClick();
      default:
        return HapticFeedback.lightImpact();
    }
  }

  bool _shouldOpenExternally(Uri uri) {
    // 仅允许明确列出的系统/第三方 scheme 离开沙箱，其余非 HTTP(S) scheme 拒绝。
    const externalSchemes = <String>{
      'tel',
      'mailto',
      'sms',
      'weixin',
      'alipays',
      'mqqapi',
      'iosamap',
      'androidamap',
      'baidumap',
      'intent',
      'market',
    };

    return externalSchemes.contains(uri.scheme);
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        debugPrint('[WebView] Failed to launch external url: $uri');
      }
    } catch (error) {
      debugPrint('[WebView] External launch failed: $error');
    }
  }

  bool _isDownloadRequest(Uri uri) {
    // WebView 插件不暴露所有响应头，这里只能按扩展名和显式查询参数预判下载。
    const downloadExtensions = <String>{
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.zip',
      '.rar',
      '.7z',
      '.apk',
      '.txt',
      '.csv',
    };

    final path = uri.path.toLowerCase();
    if (downloadExtensions.any(path.endsWith)) {
      return true;
    }

    return uri.queryParameters.containsKey('download') ||
        uri.queryParameters['attachment'] == '1';
  }

  Future<void> _downloadFile(Uri uri) async {
    try {
      _showMessage(
        _browserText(
          context,
          zhCN: '开始下载文件...',
          zhTW: '開始下載檔案...',
          en: 'Starting file download...',
        ),
      );
      final directory = await _resolveDownloadDirectory();
      final response = await _downloadDio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

      final filename = _resolveDownloadFilename(uri, response.headers);
      final savePath = '${directory.path}${Platform.pathSeparator}$filename';
      final file = File(savePath);
      await file.writeAsBytes(response.data ?? <int>[]);

      _showDownloadSuccess(file);
    } catch (error) {
      debugPrint('[WebView] Download failed: $error');
      _showMessage(
        _browserText(
          context,
          zhCN: '文件下载失败',
          zhTW: '檔案下載失敗',
          en: 'File download failed',
        ),
      );
    }
  }

  Future<Directory> _resolveDownloadDirectory() async {
    // 系统下载目录不可用时回退应用文档目录，保证文件仍有可持久访问的位置。
    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      if (!await downloadsDirectory.exists()) {
        await downloadsDirectory.create(recursive: true);
      }
      return downloadsDirectory;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    if (!await documentsDirectory.exists()) {
      await documentsDirectory.create(recursive: true);
    }
    return documentsDirectory;
  }

  String _resolveDownloadFilename(Uri uri, Headers headers) {
    final disposition = headers.value('content-disposition');
    if (disposition != null) {
      final filenameStarMatch =
          RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
              .firstMatch(disposition);
      if (filenameStarMatch != null) {
        return Uri.decodeFull(filenameStarMatch.group(1)!);
      }

      final filenameMatch =
          RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
              .firstMatch(disposition);
      if (filenameMatch != null) {
        return filenameMatch.group(1)!;
      }
    }

    final lastSegment =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (lastSegment.isNotEmpty) {
      return lastSegment;
    }

    final contentType = headers.value(Headers.contentTypeHeader);
    final extension = _extensionForContentType(contentType);
    return 'download_${DateTime.now().millisecondsSinceEpoch}$extension';
  }

  String _extensionForContentType(String? contentType) {
    if (contentType == null || contentType.isEmpty) {
      return '';
    }

    final mediaType = MediaType.parse(contentType);
    final subtype = mediaType.subtype.toLowerCase();
    const mapping = <String, String>{
      'pdf': '.pdf',
      'zip': '.zip',
      'msword': '.doc',
      'vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
      'vnd.ms-excel': '.xls',
      'vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
      'plain': '.txt',
      'csv': '.csv',
      'json': '.json',
    };

    return mapping[subtype] ?? '';
  }

  void _showDownloadSuccess(File file) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _browserText(
            context,
            zhCN: '文件已保存：${file.path.split(Platform.pathSeparator).last}',
            zhTW: '檔案已儲存：${file.path.split(Platform.pathSeparator).last}',
            en: 'File saved: ${file.path.split(Platform.pathSeparator).last}',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: _browserText(
            context,
            zhCN: '分享',
            zhTW: '分享',
            en: 'Share',
          ),
          onPressed: () {
            Share.shareXFiles([XFile(file.path)]);
          },
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _updateNavigationState() async {
    // WebView 查询为异步操作，页面关闭后只丢弃结果，不再更新状态。
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 400.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset > _dismissThreshold ||
        details.velocity.pixelsPerSecond.dy > 500) {
      // 关闭浏览器
      Navigator.of(context).pop();
    } else {
      // 弹回原位
      setState(() {
        _dragOffset = 0;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;

    // 颜色配置
    final headerBg = AppColors.surfaceFor(context);
    final contentBg = isDark ? const Color(0xFF000000) : Colors.white;

    // 计算透明度（下拉时背景变暗）
    final double opacity = (1 - (_dragOffset / 300)).clamp(0.3, 1.0);
    final double scale = (1 - (_dragOffset / 2000)).clamp(0.95, 1.0);

    return GestureDetector(
      onTap: () {}, // 阻止点击穿透
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.5 * opacity),
        body: AnimatedContainer(
          duration:
              _isDragging ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translate(0.0, _dragOffset)
            ..scale(scale),
          child: Container(
            margin: EdgeInsets.only(top: topPadding),
            decoration: BoxDecoration(
              color: contentBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // 可拖动的顶部区域
                GestureDetector(
                  onVerticalDragStart: _onVerticalDragStart,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  behavior: HitTestBehavior.opaque,
                  child: _buildTelegramHeader(isDark, headerBg),
                ),
                // 加载进度条
                if (_isLoading)
                  LinearProgressIndicator(
                    value: _loadingProgress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.controlActiveFor(context),
                    ),
                    minHeight: 2,
                  )
                else
                  const SizedBox(height: 2),
                // WebView
                Expanded(
                  child: WebViewWidget(controller: _controller),
                ),
                if (widget.miniApp != null && _miniMainButtonVisible)
                  _buildMiniAppMainButton(),
                // Telegram 风格底部栏
                _buildTelegramBottomBar(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Telegram 风格顶部导航栏（可下拉关闭）
  Widget _buildTelegramHeader(bool isDark, Color headerBg) {
    final buttonBg = isDark
        ? AppColors.darkControlBackgroundStrong
        : Colors.black.withOpacity(0.06);
    final addressBarBg = AppColors.inputBackgroundFor(context);
    final textColor = AppColors.textPrimaryFor(context);

    return Container(
      color: headerBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 下拉指示器
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.dividerFor(context),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          // 导航栏内容
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                // 关闭按钮 (X)
                _buildCircleButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context),
                  backgroundColor: buttonBg,
                  iconColor: textColor,
                ),
                const SizedBox(width: 10),
                // 地址栏（hideAddressBar 为 true 时隐藏）
                if (!widget.hideAddressBar)
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: addressBarBg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isSecure)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.lock,
                                size: 14,
                                color: AppColors.textSecondaryFor(context),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              _getDomain(_currentUrl),
                              style: TextStyle(
                                fontSize: 15,
                                color: textColor,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isLoading) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.textSecondaryFor(context),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 10),
                // 更多按钮（hideAddressBar 时一并隐藏）
                if (!widget.hideAddressBar)
                  _buildCircleButton(
                    icon: Icons.more_horiz,
                    onTap: () => _showMoreOptions(isDark),
                    backgroundColor: buttonBg,
                    iconColor: textColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Telegram 风格底部工具栏
  Widget _buildTelegramBottomBar(bool isDark) {
    final barBg = AppColors.surfaceFor(context);
    final iconColor = AppColors.linkFor(context);
    final disabledColor = AppColors.textTertiaryFor(context);

    return Container(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          top: BorderSide(
            color: AppColors.dividerFor(context),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 后退
              _buildBottomButton(
                icon: Icons.chevron_left,
                onTap: _canGoBack ? () => _controller.goBack() : null,
                color: _canGoBack ? iconColor : disabledColor,
                size: 32,
              ),
              // 前进
              _buildBottomButton(
                icon: Icons.chevron_right,
                onTap: _canGoForward ? () => _controller.goForward() : null,
                color: _canGoForward ? iconColor : disabledColor,
                size: 32,
              ),
              // 分享
              _buildBottomButton(
                icon: Icons.ios_share,
                onTap: () => Share.share(_currentUrl),
                color: iconColor,
                size: 26,
              ),
              // 刷新
              _buildBottomButton(
                icon: Icons.refresh,
                onTap: () => _controller.reload(),
                color: iconColor,
                size: 26,
              ),
              // 在浏览器中打开
              _buildBottomButton(
                icon: Icons.open_in_browser,
                onTap: widget.miniApp == null
                    ? () {
                        launchUrl(
                          Uri.parse(_currentUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    : () => _openMiniAppExternalLink(_currentUrl),
                color: iconColor,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniAppMainButton() {
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            key: const ValueKey('mini_app_main_button'),
            onPressed: _miniMainButtonEnabled
                ? () => _emitMiniAppEvent(
                      'mainButtonClicked',
                      const <String, dynamic>{},
                    )
                : null,
            child: Text(
              _miniMainButtonText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor,
        ),
      ),
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: size,
          color: color,
        ),
      ),
    );
  }

  void _showMoreOptions(bool isDark) {
    final bgColor = AppColors.cardFor(context);
    final textColor = AppColors.textPrimaryFor(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              // 页面标题
              if (_pageTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _pageTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_pageTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  child: Text(
                    _currentUrl,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryFor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (_pageTitle.isEmpty) const SizedBox(height: 8),
              // 选项列表
              _buildOptionItem(
                icon: Icons.copy_rounded,
                title: _browserText(
                  context,
                  zhCN: '拷贝链接',
                  zhTW: '複製連結',
                  en: 'Copy Link',
                ),
                isDark: isDark,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _currentUrl));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _browserText(
                          context,
                          zhCN: '链接已拷贝',
                          zhTW: '連結已複製',
                          en: 'Link copied',
                        ),
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
              ),
              _buildOptionItem(
                icon: Icons.refresh_rounded,
                title: _browserText(
                  context,
                  zhCN: '刷新',
                  zhTW: '重新整理',
                  en: 'Refresh',
                ),
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _controller.reload();
                },
              ),
              const SizedBox(height: 8),
              // 取消按钮
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: isDark
                        ? AppColors.darkControlBackgroundStrong
                        : Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _browserText(
                      context,
                      zhCN: '取消',
                      zhTW: '取消',
                      en: 'Cancel',
                    ),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: AppColors.linkFor(context),
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textPrimaryFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return url;
    }
  }
}

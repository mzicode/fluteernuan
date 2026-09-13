import 'dart:io';

enum MiniAppNavigationBlockReason {
  invalidUrl,
  insecureScheme,
  credentialsInUrl,
  disallowedPort,
  localHost,
  privateAddress,
  domainNotAllowed,
}

class MiniAppNavigationDecision {
  final bool allowed;
  final Uri? uri;
  final MiniAppNavigationBlockReason? reason;

  const MiniAppNavigationDecision._({
    required this.allowed,
    this.uri,
    this.reason,
  });

  const MiniAppNavigationDecision.allow(Uri uri)
      : this._(allowed: true, uri: uri);

  const MiniAppNavigationDecision.block(MiniAppNavigationBlockReason reason)
      : this._(allowed: false, reason: reason);
}

class MiniAppNavigationPolicy {
  const MiniAppNavigationPolicy._();

  static MiniAppNavigationDecision evaluate(
    String rawUrl,
    Iterable<String> allowedDomains,
  ) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const MiniAppNavigationDecision.block(
        MiniAppNavigationBlockReason.invalidUrl,
      );
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return const MiniAppNavigationDecision.block(
        MiniAppNavigationBlockReason.insecureScheme,
      );
    }
    if (uri.userInfo.isNotEmpty) {
      return const MiniAppNavigationDecision.block(
        MiniAppNavigationBlockReason.credentialsInUrl,
      );
    }
    if (uri.hasPort && uri.port != 443) {
      return const MiniAppNavigationDecision.block(
        MiniAppNavigationBlockReason.disallowedPort,
      );
    }

    final host = normalizeHost(uri.host);
    if (isLocalHostname(host)) {
      return const MiniAppNavigationDecision.block(
        MiniAppNavigationBlockReason.localHost,
      );
    }
    final literal = InternetAddress.tryParse(host);
    if (literal != null && !isPublicAddress(literal)) {
      return const MiniAppNavigationDecision.block(
        MiniAppNavigationBlockReason.privateAddress,
      );
    }
    final normalizedAllowed = allowedDomains
        .map(normalizeHost)
        .where((domain) => domain.isNotEmpty)
        .toSet();
    if (!normalizedAllowed.contains(host)) {
      return const MiniAppNavigationDecision.block(
        MiniAppNavigationBlockReason.domainNotAllowed,
      );
    }
    return MiniAppNavigationDecision.allow(uri);
  }

  static String normalizeHost(String host) {
    var normalized = host.trim().toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool isLocalHostname(String host) {
    final normalized = normalizeHost(host);
    if (normalized.isEmpty || !normalized.contains('.')) return true;
    return normalized == 'localhost' ||
        normalized.endsWith('.localhost') ||
        normalized.endsWith('.local') ||
        normalized.endsWith('.internal') ||
        normalized.endsWith('.lan') ||
        normalized.endsWith('.home') ||
        normalized.endsWith('.corp');
  }

  static bool isPublicAddress(InternetAddress address) {
    if (address.isLoopback ||
        address.isLinkLocal ||
        address.isMulticast ||
        address.rawAddress.every((value) => value == 0)) {
      return false;
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      final a = bytes[0];
      final b = bytes[1];
      return !(a == 10 ||
          a == 0 ||
          a == 127 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 0) ||
          (a == 192 && b == 168) ||
          (a == 198 && (b == 18 || b == 19)) ||
          a >= 224);
    }

    // IPv4-mapped IPv6 addresses keep the IPv4 policy.
    if (bytes.length == 16 &&
        bytes.take(10).every((value) => value == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff) {
      return isPublicAddress(InternetAddress.fromRawAddress(bytes.sublist(12)));
    }
    // fc00::/7 unique-local and the documentation range are not public Mini
    // App navigation targets. Documentation ranges are blocked fail-closed.
    return !((bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0x20 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0x0d &&
            bytes[3] == 0xb8));
  }
}

# Source Delivery

This file is the handoff entry point for a customer source package.

## Included

- Flutter client for Android, iOS, Web, Windows and macOS.
- Vue H5/PWA client.
- Go API, database models, migrations and WebSocket services.
- Operations admin and customer-service admin frontends.
- Docker, reverse-proxy, build and deployment scripts.
- Architecture, configuration, security and operations documentation.

## Excluded

The delivery package must not contain:

- Git history or private worktree metadata.
- `node_modules`, `.dart_tool`, `build`, `dist`, caches or test artifacts.
- `.env` files containing values, signing files or cloud credentials.
- Database dumps, user uploads, logs, crash dumps or release binaries.
- `google-services.json`, `GoogleService-Info.plist`, keystores or private keys.

## Start Here

1. Read `README.md`.
2. Read `docs/客户源码交付使用指南.md` for the complete customer handoff flow.
3. Customer contracts and signed handoff records are supplied separately from the source ZIP.
4. Copy the example configuration and fill deployment-specific values.
5. Read `docs/CONFIGURATION.md` before starting services.
6. Start local dependencies with `docker compose up -d --build`.
7. Read `docs/API接口完整参考.md` for the generated method/path inventory, then read `docs/接口与数据流说明.md` for business data flows.
8. Open `docs/客户源码交付一键部署手册.html` for the offline combined tutorial, port/domain matrix, per-platform packaging, API, Docker and operations handbook.
9. Read `docs/客户域名替换与Docker一键交付小白教程.md` for customer DNS, Baota, HTTPS, prebuilt online package generation and one-command deployment.
10. Read `docs/源码使用与合规责任协议.md` before opening the hosted handbook. The API route `/delivery/handbook` shows the agreement first and only returns the handbook after server-side confirmation.
11. The delivery-side generators and identity scanner have already checked the generated documents before the ZIP was created; those internal tools are not included in the customer archive.
12. Run the backend, H5 and Flutter checks listed in `docs/OPERATIONS.md`.

客户包在压缩前必须通过交付方身份脱敏门禁。产品品牌和功能兼容标识可按授权范围保留；交付方公司联系方式、生产域名、自有版权归属信息和其他内部身份资料必须清除，第三方许可证按许可证要求保留。

## Build Reproducibility

Record the following values in the private delivery manifest:

- Customer delivery identifier.
- Git commit or source snapshot identifier.
- Go, Flutter, Dart, Node and package-manager versions.
- Database migration version.
- Release artifact SHA256 values.
- Storage, push, RTC and payment provider configuration fingerprints.

The customer package should be generated from a reviewed source snapshot. If
the current developer worktree is intentionally used, record its baseline
commit, review every local change and run the delivery verifier against the
staged package before handoff.

## Security Boundary

The source package contains no production secrets or delivery-owner domains.
Deployment examples must use customer-owned or explicit placeholder domains.
The customer is responsible for generating deployment secrets, restricting
database and Redis network access, configuring HTTPS and setting production
CORS/WebSocket origins.

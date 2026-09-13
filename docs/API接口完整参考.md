# API 接口完整参考

> 本文件由 `scripts/generate-api-reference.py` 从后端 Gin 路由注册自动生成。生成时间和路由数量仅用于追踪，不能替代目标环境验收。

## 1. 连接约定

- HTTP 根地址：`https://<customer-api-host>`；接口前缀：`/api/v1`。部署时由客户配置反向代理和 HTTPS。
- 除公开接口外使用 `Authorization: Bearer <access_token>`。WebSocket 握手优先使用同一鉴权头；仅在浏览器限制下允许短时 `?token=`，普通 HTTP 不应把 Token 放在 URL。
- JSON 请求使用 `Content-Type: application/json`；上传接口使用 `multipart/form-data`，分片接口按下文协议执行。
- 成功和业务失败通常都返回 JSON；HTTP 状态码与业务 `code` 必须同时检查。

## 2. 统一响应与错误码

```json
{"code":0,"message":"success","data":{}}
```

分页数据约定：`data.list`、`data.total`、`data.page`、`data.page_size`、`data.has_more`。分页参数通常为 `page`（从 1 开始）和 `page_size`；具体上限以处理器校验为准。

| code | 含义 |
| ---: | --- |
| 0 | 成功 |
| 1002 | 需要先绑定手机号 |
| 1008 | 账号被限制或封禁 |
| 400 | 请求参数错误 |
| 401 | 未认证或 Token 无效 |
| 403 | 无权限 |
| 404 | 资源不存在 |
| 429 | 请求过于频繁 |
| 1429 | 直传限流 |
| 1430 | 直传存储不可用 |
| 1431 | 直传功能关闭 |
| 1432 | 直传平台未启用 |
| 1433 | 不在直传灰度范围 |
| 500 | 服务端错误 |

未列出的业务错误码由对应模块定义；客户集成时应按 `code` 分支处理并保留 `message` 供日志定位。

## 3. 鉴权分层

| 标记 | 说明 |
| --- | --- |
| 公开 | 登录、注册、健康检查、公共配置或支付回调；仍需限流和参数校验 |
| 交付文档 | HTTPS + 独立 HTTP Basic 凭据；通过后仍需确认使用协议 |
| Bearer Token | 用户登录态；部分接口额外要求手机号绑定或功能开关 |
| 管理员会话 | 管理后台 Token 和角色权限；写操作通常拒绝演示角色 |
| 内部监控鉴权 | 仅绑定内部网络/观测配置，不应暴露到公网 |

## 4. HTTP 路由目录

共 **580** 条从 `setupRouter` 及其容量注册辅助函数解析出的字面量路由。每条记录包含注册源码行号，路由变更后请重新运行生成器。

| 方法 | 路径 | 鉴权 | 处理器线索 | 注册位置 |
| --- | --- | --- | --- | --- |
| `GET` | `/` | HTTPS + 文档独立认证 + 协议确认 | `apiHomeHandler` | `backend/cmd/server/main.go:1018` |
| `DELETE` | `/api/v1/admin/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1637` |
| `POST` | `/api/v1/admin/agreement/accept` | 管理员会话（角色权限由中间件决定） | `func` | `backend/cmd/server/main.go:1581` |
| `GET` | `/api/v1/admin/agreement/current` | 管理员会话（角色权限由中间件决定） | `func` | `backend/cmd/server/main.go:1578` |
| `POST` | `/api/v1/admin/ai/automation-runs/:id/approve` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1624` |
| `GET` | `/api/v1/admin/ai/bots` | 管理员会话（角色权限由中间件决定） | `aiHandler.ListBots` | `backend/cmd/server/main.go:1607` |
| `PUT` | `/api/v1/admin/ai/bots/:uuid` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1608` |
| `GET` | `/api/v1/admin/ai/governance-cases` | 管理员会话（角色权限由中间件决定） | `aiHandler.ListGovernanceCases` | `backend/cmd/server/main.go:1620` |
| `PUT` | `/api/v1/admin/ai/governance-cases/:id/review` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1621` |
| `GET` | `/api/v1/admin/ai/groups/:chat_id/automation-rules` | 管理员会话（角色权限由中间件决定） | `aiHandler.ListAutomationRules` | `backend/cmd/server/main.go:1622` |
| `POST` | `/api/v1/admin/ai/groups/:chat_id/automation-rules` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1623` |
| `GET` | `/api/v1/admin/ai/groups/:chat_id/policy` | 管理员会话（角色权限由中间件决定） | `aiHandler.GetGroupPolicy` | `backend/cmd/server/main.go:1616` |
| `PUT` | `/api/v1/admin/ai/groups/:chat_id/policy` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1617` |
| `GET` | `/api/v1/admin/ai/groups/:chat_id/summaries` | 管理员会话（角色权限由中间件决定） | `aiHandler.ListGroupSummaries` | `backend/cmd/server/main.go:1619` |
| `POST` | `/api/v1/admin/ai/groups/:chat_id/summaries` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1618` |
| `GET` | `/api/v1/admin/ai/knowledge-bases` | 管理员会话（角色权限由中间件决定） | `aiHandler.ListKnowledgeBases` | `backend/cmd/server/main.go:1610` |
| `POST` | `/api/v1/admin/ai/knowledge-bases` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1611` |
| `PUT` | `/api/v1/admin/ai/knowledge-bases/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1612` |
| `GET` | `/api/v1/admin/ai/knowledge-bases/:id/documents` | 管理员会话（角色权限由中间件决定） | `aiHandler.ListKnowledgeDocuments` | `backend/cmd/server/main.go:1613` |
| `POST` | `/api/v1/admin/ai/knowledge-bases/:id/documents` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1614` |
| `DELETE` | `/api/v1/admin/ai/knowledge-bases/:id/documents/:document_id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1615` |
| `GET` | `/api/v1/admin/ai/providers` | 管理员会话（角色权限由中间件决定） | `aiHandler.ListProviders` | `backend/cmd/server/main.go:1604` |
| `PUT` | `/api/v1/admin/ai/providers/:provider` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1605` |
| `POST` | `/api/v1/admin/ai/providers/:provider/test` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1606` |
| `GET` | `/api/v1/admin/ai/usage` | 管理员会话（角色权限由中间件决定） | `aiHandler.Usage` | `backend/cmd/server/main.go:1609` |
| `DELETE` | `/api/v1/admin/banned-words/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1756` |
| `PUT` | `/api/v1/admin/banned-words/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1755` |
| `POST` | `/api/v1/admin/banned-words/batch` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1754` |
| `POST` | `/api/v1/admin/banned-words/create` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1753` |
| `GET` | `/api/v1/admin/banned-words/list` | 管理员会话（角色权限由中间件决定） | `momentMgmtHandler.ListBannedWords` | `backend/cmd/server/main.go:1751` |
| `GET` | `/api/v1/admin/bot-marketplace` | 管理员会话（角色权限由中间件决定） | `ecosystemHandler.AdminListListings` | `backend/cmd/server/main.go:1626` |
| `POST` | `/api/v1/admin/bot-marketplace` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1627` |
| `PUT` | `/api/v1/admin/bot-marketplace/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1628` |
| `POST` | `/api/v1/admin/broadcast` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1837` |
| `DELETE` | `/api/v1/admin/broadcast/clear` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1839` |
| `GET` | `/api/v1/admin/broadcast/list` | 管理员会话（角色权限由中间件决定） | `broadcastHandler.ListBroadcasts` | `backend/cmd/server/main.go:1838` |
| `DELETE` | `/api/v1/admin/calls/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1934` |
| `GET` | `/api/v1/admin/calls/:id` | 管理员会话（角色权限由中间件决定） | `callAdminHandler.GetCallDetail` | `backend/cmd/server/main.go:1932` |
| `POST` | `/api/v1/admin/calls/:id/force-end` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1933` |
| `GET` | `/api/v1/admin/calls/active-user/:user_id` | 管理员会话（角色权限由中间件决定） | `callAdminHandler.GetUserActiveCall` | `backend/cmd/server/main.go:1928` |
| `POST` | `/api/v1/admin/calls/batch-delete` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1935` |
| `POST` | `/api/v1/admin/calls/cleanup-stale` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1930` |
| `GET` | `/api/v1/admin/calls/events` | 管理员会话（角色权限由中间件决定） | `callAdminHandler.ListCallEvents` | `backend/cmd/server/main.go:1927` |
| `POST` | `/api/v1/admin/calls/force-user/:user_id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1929` |
| `GET` | `/api/v1/admin/calls/list` | 管理员会话（角色权限由中间件决定） | `callAdminHandler.ListCalls` | `backend/cmd/server/main.go:1924` |
| `GET` | `/api/v1/admin/calls/metrics` | 管理员会话（角色权限由中间件决定） | `callAdminHandler.GetObservabilityMetrics` | `backend/cmd/server/main.go:1926` |
| `GET` | `/api/v1/admin/calls/stats` | 管理员会话（角色权限由中间件决定） | `callAdminHandler.GetCallStats` | `backend/cmd/server/main.go:1925` |
| `GET` | `/api/v1/admin/calls/user/:user_id` | 管理员会话（角色权限由中间件决定） | `callAdminHandler.GetUserCallHistory` | `backend/cmd/server/main.go:1931` |
| `POST` | `/api/v1/admin/capacity/assessments` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/internal/handlers/capacity_handler.go:51` |
| `GET` | `/api/v1/admin/capacity/assessments/:uuid/report` | 管理员会话（角色权限由中间件决定） | `handler.GetReport` | `backend/internal/handlers/capacity_handler.go:50` |
| `GET` | `/api/v1/admin/capacity/bandwidth-results` | 管理员会话（角色权限由中间件决定） | `handler.ListBandwidthResults` | `backend/internal/handlers/capacity_handler.go:44` |
| `POST` | `/api/v1/admin/capacity/bandwidth-tests` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/internal/handlers/capacity_handler.go:45` |
| `GET` | `/api/v1/admin/capacity/cluster` | 管理员会话（角色权限由中间件决定） | `handler.GetClusterOverview` | `backend/internal/handlers/capacity_handler.go:46` |
| `GET` | `/api/v1/admin/capacity/history` | 管理员会话（角色权限由中间件决定） | `handler.ListHistory` | `backend/internal/handlers/capacity_handler.go:47` |
| `GET` | `/api/v1/admin/capacity/history/compare` | 管理员会话（角色权限由中间件决定） | `handler.CompareHistory` | `backend/internal/handlers/capacity_handler.go:48` |
| `GET` | `/api/v1/admin/capacity/model` | 管理员会话（角色权限由中间件决定） | `handler.GetModel` | `backend/internal/handlers/capacity_handler.go:41` |
| `GET` | `/api/v1/admin/capacity/nodes` | 管理员会话（角色权限由中间件决定） | `handler.ListNodes` | `backend/internal/handlers/capacity_handler.go:42` |
| `GET` | `/api/v1/admin/capacity/nodes/:uuid` | 管理员会话（角色权限由中间件决定） | `handler.GetNode` | `backend/internal/handlers/capacity_handler.go:43` |
| `GET` | `/api/v1/admin/capacity/overview` | 管理员会话（角色权限由中间件决定） | `handler.GetOverview` | `backend/internal/handlers/capacity_handler.go:40` |
| `POST` | `/api/v1/admin/capacity/simulate` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/internal/handlers/capacity_handler.go:49` |
| `GET` | `/api/v1/admin/captcha` | 公开 | `adminHandler.GetCaptcha` | `backend/cmd/server/main.go:1570` |
| `DELETE` | `/api/v1/admin/chats/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1695` |
| `GET` | `/api/v1/admin/chats/:id` | 管理员会话（角色权限由中间件决定） | `chatMgmtHandler.GetChatDetail` | `backend/cmd/server/main.go:1682` |
| `PUT` | `/api/v1/admin/chats/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1687` |
| `POST` | `/api/v1/admin/chats/:id/ban` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1689` |
| `POST` | `/api/v1/admin/chats/:id/dissolve` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1691` |
| `GET` | `/api/v1/admin/chats/:id/join-requests` | 管理员会话（角色权限由中间件决定） | `chatMgmtHandler.GetJoinRequests` | `backend/cmd/server/main.go:1685` |
| `POST` | `/api/v1/admin/chats/:id/join-requests/:request_id/review` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1693` |
| `GET` | `/api/v1/admin/chats/:id/members` | 管理员会话（角色权限由中间件决定） | `chatMgmtHandler.GetChatMembers` | `backend/cmd/server/main.go:1684` |
| `POST` | `/api/v1/admin/chats/:id/members` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1692` |
| `DELETE` | `/api/v1/admin/chats/:id/members/:member_id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1698` |
| `PUT` | `/api/v1/admin/chats/:id/members/:member_id/mute` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1697` |
| `PUT` | `/api/v1/admin/chats/:id/members/:member_id/role` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1696` |
| `GET` | `/api/v1/admin/chats/:id/messages` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1683` |
| `PUT` | `/api/v1/admin/chats/:id/owner` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1694` |
| `PUT` | `/api/v1/admin/chats/:id/status` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1688` |
| `POST` | `/api/v1/admin/chats/:id/unban` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1690` |
| `GET` | `/api/v1/admin/chats/channels` | 管理员会话（角色权限由中间件决定） | `chatMgmtHandler.ListChannels` | `backend/cmd/server/main.go:1680` |
| `GET` | `/api/v1/admin/chats/groups` | 管理员会话（角色权限由中间件决定） | `chatMgmtHandler.ListGroups` | `backend/cmd/server/main.go:1679` |
| `GET` | `/api/v1/admin/chats/list` | 管理员会话（角色权限由中间件决定） | `chatMgmtHandler.ListChats` | `backend/cmd/server/main.go:1678` |
| `GET` | `/api/v1/admin/chats/stats` | 管理员会话（角色权限由中间件决定） | `chatMgmtHandler.GetChatStats` | `backend/cmd/server/main.go:1681` |
| `POST` | `/api/v1/admin/create` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1636` |
| `GET` | `/api/v1/admin/emoji-store/packs` | 管理员会话（角色权限由中间件决定） | `emojiStoreAdminHandler.ListPacks` | `backend/cmd/server/main.go:1845` |
| `POST` | `/api/v1/admin/emoji-store/packs` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1846` |
| `DELETE` | `/api/v1/admin/emoji-store/packs/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1849` |
| `PUT` | `/api/v1/admin/emoji-store/packs/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1847` |
| `PUT` | `/api/v1/admin/emoji-store/packs/:id/active` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1848` |
| `GET` | `/api/v1/admin/hot-update/patches` | 管理员会话（角色权限由中间件决定） | `hotUpdateHandler.ListPatches` | `backend/cmd/server/main.go:1824` |
| `POST` | `/api/v1/admin/hot-update/patches` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1827` |
| `DELETE` | `/api/v1/admin/hot-update/patches/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1829` |
| `GET` | `/api/v1/admin/hot-update/patches/:id` | 管理员会话（角色权限由中间件决定） | `hotUpdateHandler.GetPatch` | `backend/cmd/server/main.go:1825` |
| `PUT` | `/api/v1/admin/hot-update/patches/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1828` |
| `POST` | `/api/v1/admin/hot-update/patches/:id/pause` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1831` |
| `POST` | `/api/v1/admin/hot-update/patches/:id/publish` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1830` |
| `POST` | `/api/v1/admin/hot-update/patches/:id/rollback` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1832` |
| `GET` | `/api/v1/admin/hot-update/reports` | 管理员会话（角色权限由中间件决定） | `hotUpdateHandler.ListPatchReports` | `backend/cmd/server/main.go:1826` |
| `GET` | `/api/v1/admin/list` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1634` |
| `POST` | `/api/v1/admin/login` | 公开 | `adminHandler.Login` | `backend/cmd/server/main.go:1571` |
| `GET` | `/api/v1/admin/login-logs` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1635` |
| `GET` | `/api/v1/admin/me` | 管理员会话（角色权限由中间件决定） | `adminHandler.GetCurrentAdmin` | `backend/cmd/server/main.go:1592` |
| `GET` | `/api/v1/admin/messages/search` | 管理员会话（角色权限由中间件决定） | `msgAdminHandler.SearchMessages` | `backend/cmd/server/main.go:1853` |
| `GET` | `/api/v1/admin/mini-apps` | 管理员会话（角色权限由中间件决定） | `ecosystemHandler.AdminListMiniApps` | `backend/cmd/server/main.go:1629` |
| `POST` | `/api/v1/admin/mini-apps` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1630` |
| `PUT` | `/api/v1/admin/mini-apps/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1631` |
| `DELETE` | `/api/v1/admin/moments/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1733` |
| `PUT` | `/api/v1/admin/moments/:id/status` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1732` |
| `GET` | `/api/v1/admin/moments/list` | 管理员会话（角色权限由中间件决定） | `momentMgmtHandler.ListMoments` | `backend/cmd/server/main.go:1729` |
| `GET` | `/api/v1/admin/moments/stats` | 管理员会话（角色权限由中间件决定） | `momentMgmtHandler.GetMomentStats` | `backend/cmd/server/main.go:1730` |
| `PUT` | `/api/v1/admin/password` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1597` |
| `POST` | `/api/v1/admin/password/reset-by-code` | 公开 | `adminHandler.ResetPasswordByCode` | `backend/cmd/server/main.go:1573` |
| `POST` | `/api/v1/admin/password/send-reset-code` | 公开 | `adminHandler.SendPasswordResetCode` | `backend/cmd/server/main.go:1572` |
| `GET` | `/api/v1/admin/push/devices` | 管理员会话（角色权限由中间件决定） | `pushAdminHandler.ListDevices` | `backend/cmd/server/main.go:1663` |
| `POST` | `/api/v1/admin/push/devices/:id/disable-token` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1664` |
| `POST` | `/api/v1/admin/push/invalid-tokens/cleanup` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1665` |
| `GET` | `/api/v1/admin/push/logs` | 管理员会话（角色权限由中间件决定） | `pushAdminHandler.ListLogs` | `backend/cmd/server/main.go:1661` |
| `GET` | `/api/v1/admin/push/stats` | 管理员会话（角色权限由中间件决定） | `pushAdminHandler.Stats` | `backend/cmd/server/main.go:1662` |
| `POST` | `/api/v1/admin/push/test` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1660` |
| `DELETE` | `/api/v1/admin/reports/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1767` |
| `POST` | `/api/v1/admin/reports/:id/process` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1766` |
| `GET` | `/api/v1/admin/reports/list` | 管理员会话（角色权限由中间件决定） | `reportHandler.ListReports` | `backend/cmd/server/main.go:1763` |
| `GET` | `/api/v1/admin/reports/stats` | 管理员会话（角色权限由中间件决定） | `reportHandler.GetReportStats` | `backend/cmd/server/main.go:1764` |
| `GET` | `/api/v1/admin/security-events` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1671` |
| `GET` | `/api/v1/admin/settings` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetAllSettings` | `backend/cmd/server/main.go:1785` |
| `PUT` | `/api/v1/admin/settings` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1792` |
| `GET` | `/api/v1/admin/settings/:key` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetSetting` | `backend/cmd/server/main.go:1790` |
| `GET` | `/api/v1/admin/settings/discover-banners` | 管理员会话（角色权限由中间件决定） | `discoverHandler.ListDiscoverBanners` | `backend/cmd/server/main.go:1813` |
| `POST` | `/api/v1/admin/settings/discover-banners` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1814` |
| `DELETE` | `/api/v1/admin/settings/discover-banners/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1816` |
| `PUT` | `/api/v1/admin/settings/discover-banners/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1815` |
| `POST` | `/api/v1/admin/settings/discover-banners/upload-image` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1817` |
| `GET` | `/api/v1/admin/settings/discover-items` | 管理员会话（角色权限由中间件决定） | `discoverHandler.ListDiscoverItems` | `backend/cmd/server/main.go:1808` |
| `POST` | `/api/v1/admin/settings/discover-items` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1809` |
| `DELETE` | `/api/v1/admin/settings/discover-items/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1811` |
| `PUT` | `/api/v1/admin/settings/discover-items/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1810` |
| `POST` | `/api/v1/admin/settings/discover-items/upload-icon` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1812` |
| `GET` | `/api/v1/admin/settings/official-channels` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetOfficialChannels` | `backend/cmd/server/main.go:1804` |
| `POST` | `/api/v1/admin/settings/official-channels` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1805` |
| `DELETE` | `/api/v1/admin/settings/official-channels/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1806` |
| `GET` | `/api/v1/admin/settings/official-groups` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetOfficialGroups` | `backend/cmd/server/main.go:1800` |
| `POST` | `/api/v1/admin/settings/official-groups` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1801` |
| `DELETE` | `/api/v1/admin/settings/official-groups/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1802` |
| `GET` | `/api/v1/admin/settings/official-users` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetOfficialUsers` | `backend/cmd/server/main.go:1794` |
| `POST` | `/api/v1/admin/settings/official-users` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1796` |
| `DELETE` | `/api/v1/admin/settings/official-users/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1798` |
| `PUT` | `/api/v1/admin/settings/official-users/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1797` |
| `GET` | `/api/v1/admin/settings/official-users/:id/invitees` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetOfficialUserInvitees` | `backend/cmd/server/main.go:1795` |
| `GET` | `/api/v1/admin/settings/sms-gateway/config` | 管理员会话（角色权限由中间件决定） | `smsSettingsHandler.GetSmsGatewayConfig` | `backend/cmd/server/main.go:1786` |
| `PUT` | `/api/v1/admin/settings/sms-gateway/config` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1787` |
| `GET` | `/api/v1/admin/settings/storage/status` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetStorageStatus` | `backend/cmd/server/main.go:1788` |
| `POST` | `/api/v1/admin/settings/storage/test-upload` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1789` |
| `GET` | `/api/v1/admin/stats/dashboard` | 管理员会话（角色权限由中间件决定） | `statsHandler.GetDashboardStats` | `backend/cmd/server/main.go:1706` |
| `GET` | `/api/v1/admin/stats/messages` | 管理员会话（角色权限由中间件决定） | `statsHandler.GetMessageStats` | `backend/cmd/server/main.go:1709` |
| `GET` | `/api/v1/admin/stats/runtime` | 管理员会话（角色权限由中间件决定） | `statsHandler.GetRuntimeStatus` | `backend/cmd/server/main.go:1707` |
| `GET` | `/api/v1/admin/stats/users` | 管理员会话（角色权限由中间件决定） | `statsHandler.GetUserStats` | `backend/cmd/server/main.go:1708` |
| `GET` | `/api/v1/admin/storage/status` | 管理员会话（角色权限由中间件决定） | `settingHandler.GetStorageStatus` | `backend/cmd/server/main.go:1782` |
| `POST` | `/api/v1/admin/storage/test-upload` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1783` |
| `GET` | `/api/v1/admin/system/alerts` | 管理员会话（角色权限由中间件决定） | `statsHandler.GetObservabilityAlerts` | `backend/cmd/server/main.go:1712` |
| `POST` | `/api/v1/admin/system/alerts/:id/ack` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1716` |
| `POST` | `/api/v1/admin/system/alerts/:id/unack` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1717` |
| `GET` | `/api/v1/admin/system/data-governance/capacity` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1669` |
| `GET` | `/api/v1/admin/system/data-governance/insights` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1670` |
| `GET` | `/api/v1/admin/system/health-detail` | 管理员会话（角色权限由中间件决定） | `statsHandler.GetHealthDetail` | `backend/cmd/server/main.go:1710` |
| `GET` | `/api/v1/admin/system/health-stream` | 管理员会话（角色权限由中间件决定） | `statsHandler.StreamHealth` | `backend/cmd/server/main.go:1713` |
| `GET` | `/api/v1/admin/system/health-trend` | 管理员会话（角色权限由中间件决定） | `statsHandler.GetHealthTrend` | `backend/cmd/server/main.go:1711` |
| `GET` | `/api/v1/admin/system/maintenance` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1719` |
| `GET` | `/api/v1/admin/system/maintenance/preview` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1720` |
| `POST` | `/api/v1/admin/system/maintenance/run` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1721` |
| `POST` | `/api/v1/admin/system/maintenance/run-formal` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1722` |
| `POST` | `/api/v1/admin/system/queue/clear-dead` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1715` |
| `POST` | `/api/v1/admin/system/queue/retry-dead` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1714` |
| `DELETE` | `/api/v1/admin/topics/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1744` |
| `PUT` | `/api/v1/admin/topics/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1743` |
| `POST` | `/api/v1/admin/topics/create` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1742` |
| `GET` | `/api/v1/admin/topics/list` | 管理员会话（角色权限由中间件决定） | `momentMgmtHandler.ListTopics` | `backend/cmd/server/main.go:1740` |
| `POST` | `/api/v1/admin/totp/disable` | 管理员会话（角色权限由中间件决定） | `adminHandler.DisableTOTP` | `backend/cmd/server/main.go:1596` |
| `POST` | `/api/v1/admin/totp/enable` | 管理员会话（角色权限由中间件决定） | `adminHandler.EnableTOTP` | `backend/cmd/server/main.go:1595` |
| `POST` | `/api/v1/admin/totp/setup` | 管理员会话（角色权限由中间件决定） | `adminHandler.SetupTOTP` | `backend/cmd/server/main.go:1594` |
| `GET` | `/api/v1/admin/totp/status` | 管理员会话（角色权限由中间件决定） | `adminHandler.GetTOTPStatus` | `backend/cmd/server/main.go:1593` |
| `POST` | `/api/v1/admin/upload/image` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1598` |
| `GET` | `/api/v1/admin/upload/logs` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1667` |
| `GET` | `/api/v1/admin/upload/media-objects` | 管理员会话（角色权限由中间件决定） | `middleware.RequireRole` | `backend/cmd/server/main.go:1668` |
| `PUT` | `/api/v1/admin/users/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1647` |
| `POST` | `/api/v1/admin/users/:id/ban` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1650` |
| `GET` | `/api/v1/admin/users/:id/diagnostics` | 管理员会话（角色权限由中间件决定） | `userMgmtHandler.GetUserDiagnostics` | `backend/cmd/server/main.go:1645` |
| `POST` | `/api/v1/admin/users/:id/freeze` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1652` |
| `POST` | `/api/v1/admin/users/:id/kick` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1649` |
| `POST` | `/api/v1/admin/users/:id/reset-password` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1654` |
| `PUT` | `/api/v1/admin/users/:id/status` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1648` |
| `POST` | `/api/v1/admin/users/:id/test-push` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1655` |
| `POST` | `/api/v1/admin/users/:id/unban` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1651` |
| `POST` | `/api/v1/admin/users/:id/unfreeze` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1653` |
| `GET` | `/api/v1/admin/users/list` | 管理员会话（角色权限由中间件决定） | `userMgmtHandler.ListUsers` | `backend/cmd/server/main.go:1643` |
| `GET` | `/api/v1/admin/users/stats` | 管理员会话（角色权限由中间件决定） | `userMgmtHandler.GetUserStats` | `backend/cmd/server/main.go:1644` |
| `POST` | `/api/v1/admin/vip/badge-icon` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1911` |
| `GET` | `/api/v1/admin/vip/free-entitlements` | 管理员会话（角色权限由中间件决定） | `vipAdminHandler.GetFreeEntitlements` | `backend/cmd/server/main.go:1906` |
| `PUT` | `/api/v1/admin/vip/free-entitlements` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1907` |
| `GET` | `/api/v1/admin/vip/orders` | 管理员会话（角色权限由中间件决定） | `vipAdminHandler.ListOrders` | `backend/cmd/server/main.go:1917` |
| `GET` | `/api/v1/admin/vip/plans` | 管理员会话（角色权限由中间件决定） | `vipAdminHandler.ListPlans` | `backend/cmd/server/main.go:1908` |
| `POST` | `/api/v1/admin/vip/plans` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1909` |
| `PUT` | `/api/v1/admin/vip/plans/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1910` |
| `GET` | `/api/v1/admin/vip/users` | 管理员会话（角色权限由中间件决定） | `vipAdminHandler.ListUsers` | `backend/cmd/server/main.go:1912` |
| `POST` | `/api/v1/admin/vip/users/:user_id/cancel` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1914` |
| `POST` | `/api/v1/admin/vip/users/:user_id/freeze` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1915` |
| `POST` | `/api/v1/admin/vip/users/:user_id/grant` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1913` |
| `POST` | `/api/v1/admin/vip/users/:user_id/unfreeze` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1916` |
| `GET` | `/api/v1/admin/wallet/methods` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.ListWithdrawMethods` | `backend/cmd/server/main.go:1874` |
| `POST` | `/api/v1/admin/wallet/methods` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1875` |
| `DELETE` | `/api/v1/admin/wallet/methods/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1877` |
| `PUT` | `/api/v1/admin/wallet/methods/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1876` |
| `GET` | `/api/v1/admin/wallet/payment-config` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetPaymentGatewayConfig` | `backend/cmd/server/main.go:1889` |
| `PUT` | `/api/v1/admin/wallet/payment-config` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1890` |
| `GET` | `/api/v1/admin/wallet/recharge-methods` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.ListRechargeMethods` | `backend/cmd/server/main.go:1892` |
| `POST` | `/api/v1/admin/wallet/recharge-methods` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1893` |
| `DELETE` | `/api/v1/admin/wallet/recharge-methods/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1895` |
| `PUT` | `/api/v1/admin/wallet/recharge-methods/:id` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1894` |
| `GET` | `/api/v1/admin/wallet/recharge-orders` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.ListRechargeOrders` | `backend/cmd/server/main.go:1897` |
| `POST` | `/api/v1/admin/wallet/recharge-orders/:id/review` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1898` |
| `GET` | `/api/v1/admin/wallet/red-packets` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.ListRedPackets` | `backend/cmd/server/main.go:1879` |
| `GET` | `/api/v1/admin/wallet/red-packets/:id` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetRedPacketDetail` | `backend/cmd/server/main.go:1880` |
| `POST` | `/api/v1/admin/wallet/red-packets/:id/refund` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1881` |
| `GET` | `/api/v1/admin/wallet/settings` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetWalletSettings` | `backend/cmd/server/main.go:1887` |
| `POST` | `/api/v1/admin/wallet/settings` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1888` |
| `GET` | `/api/v1/admin/wallet/stats` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetWalletStats` | `backend/cmd/server/main.go:1859` |
| `GET` | `/api/v1/admin/wallet/transfers` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.ListTransfers` | `backend/cmd/server/main.go:1883` |
| `GET` | `/api/v1/admin/wallet/transfers/:id` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetTransferDetail` | `backend/cmd/server/main.go:1884` |
| `POST` | `/api/v1/admin/wallet/transfers/:id/refund` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1885` |
| `GET` | `/api/v1/admin/wallet/user/:user_id` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetUserWallet` | `backend/cmd/server/main.go:1862` |
| `POST` | `/api/v1/admin/wallet/user/:user_id/balance` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1864` |
| `POST` | `/api/v1/admin/wallet/user/:user_id/clear-pay-password` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1866` |
| `POST` | `/api/v1/admin/wallet/user/:user_id/lock` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1867` |
| `POST` | `/api/v1/admin/wallet/user/:user_id/reset-pay-password` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1865` |
| `GET` | `/api/v1/admin/wallet/user/:user_id/transactions` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetUserTransactions` | `backend/cmd/server/main.go:1863` |
| `POST` | `/api/v1/admin/wallet/user/:user_id/unlock` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1868` |
| `GET` | `/api/v1/admin/wallet/users` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.ListUserWallets` | `backend/cmd/server/main.go:1861` |
| `POST` | `/api/v1/admin/wallet/withdraw/:id/review` | 管理员会话（角色权限由中间件决定） | `middleware.RequireWriteRole` | `backend/cmd/server/main.go:1872` |
| `GET` | `/api/v1/admin/wallet/withdraw/list` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.ListWithdrawRequests` | `backend/cmd/server/main.go:1870` |
| `GET` | `/api/v1/admin/wallet/withdraw/stats` | 管理员会话（角色权限由中间件决定） | `walletAdminHandler.GetWithdrawStats` | `backend/cmd/server/main.go:1871` |
| `GET` | `/api/v1/app/broadcasts` | 公开 | `broadcastAppHandler.GetRecentBroadcasts` | `backend/cmd/server/main.go:1954` |
| `GET` | `/api/v1/app/check-official/chat/:uuid` | 公开 | `settingHandler.CheckChatOfficial` | `backend/cmd/server/main.go:1953` |
| `GET` | `/api/v1/app/check-official/user/:uuid` | 公开 | `settingHandler.CheckUserOfficial` | `backend/cmd/server/main.go:1952` |
| `GET` | `/api/v1/app/discovery` | 公开 | `discoverHandler.GetAppDiscoverItems` | `backend/cmd/server/main.go:1950` |
| `GET` | `/api/v1/app/discovery/banners` | 公开 | `discoverHandler.GetAppDiscoverBanners` | `backend/cmd/server/main.go:1951` |
| `GET` | `/api/v1/app/hot-update/check` | 公开 | `hotUpdateHandler.CheckPatch` | `backend/cmd/server/main.go:1948` |
| `POST` | `/api/v1/app/hot-update/report` | 公开 | `middleware.OptionalAuth` | `backend/cmd/server/main.go:1949` |
| `GET` | `/api/v1/app/privacy-policy` | 公开 | `settingHandler.GetPrivacyPolicy` | `backend/cmd/server/main.go:1956` |
| `GET` | `/api/v1/app/settings` | 公开 | `settingHandler.GetAppSettings` | `backend/cmd/server/main.go:1947` |
| `GET` | `/api/v1/app/user-agreement` | 公开 | `settingHandler.GetUserAgreement` | `backend/cmd/server/main.go:1955` |
| `POST` | `/api/v1/auth/carrier-login` | 公开 | `authHandler.CarrierLogin` | `backend/cmd/server/main.go:1095` |
| `POST` | `/api/v1/auth/change-password` | Bearer Token（该路由显式鉴权） | `middleware.Auth` | `backend/cmd/server/main.go:1106` |
| `POST` | `/api/v1/auth/check-username` | 公开 | `authHandler.CheckUsername` | `backend/cmd/server/main.go:1096` |
| `POST` | `/api/v1/auth/device-lock/verify` | 公开 | `authHandler.VerifyDeviceLockLogin` | `backend/cmd/server/main.go:1099` |
| `PUT` | `/api/v1/auth/initialize-credentials` | Bearer Token（该路由显式鉴权） | `middleware.Auth` | `backend/cmd/server/main.go:1107` |
| `POST` | `/api/v1/auth/login` | 公开 | `authHandler.Login` | `backend/cmd/server/main.go:1089` |
| `POST` | `/api/v1/auth/logout` | Bearer Token（该路由显式鉴权） | `middleware.Auth` | `backend/cmd/server/main.go:1105` |
| `POST` | `/api/v1/auth/password/reset-by-code` | 公开 | `authHandler.ResetPasswordByCode` | `backend/cmd/server/main.go:1098` |
| `POST` | `/api/v1/auth/password/send-reset-code` | 公开 | `authHandler.SendPasswordResetCode` | `backend/cmd/server/main.go:1097` |
| `POST` | `/api/v1/auth/qr-login/confirm/:ticket` | Bearer Token（该路由显式鉴权） | `middleware.Auth` | `backend/cmd/server/main.go:1103` |
| `POST` | `/api/v1/auth/qr-login/create` | 公开 | `qrLoginHandler.Create` | `backend/cmd/server/main.go:1101` |
| `GET` | `/api/v1/auth/qr-login/status/:ticket` | 公开 | `qrLoginHandler.GetStatus` | `backend/cmd/server/main.go:1102` |
| `POST` | `/api/v1/auth/quick-register` | 公开 | `authHandler.QuickRegister` | `backend/cmd/server/main.go:1094` |
| `POST` | `/api/v1/auth/refresh` | 公开 | `authHandler.RefreshToken` | `backend/cmd/server/main.go:1104` |
| `POST` | `/api/v1/auth/register` | 公开 | `authHandler.Register` | `backend/cmd/server/main.go:1090` |
| `POST` | `/api/v1/auth/register/send-code` | 公开 | `authHandler.SendRegisterCode` | `backend/cmd/server/main.go:1091` |
| `POST` | `/api/v1/auth/register/send-email-code` | 公开 | `authHandler.SendRegisterEmailCode` | `backend/cmd/server/main.go:1093` |
| `POST` | `/api/v1/auth/register/verify-code` | 公开 | `authHandler.VerifyRegisterCode` | `backend/cmd/server/main.go:1092` |
| `POST` | `/api/v1/auth/two-step/verify` | 公开 | `authHandler.VerifyTwoStepLogin` | `backend/cmd/server/main.go:1100` |
| `GET` | `/api/v1/bot-marketplace` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.ListMarketplace` | `backend/cmd/server/main.go:1135` |
| `POST` | `/api/v1/bot-marketplace/:id/install` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.InstallListing` | `backend/cmd/server/main.go:1136` |
| `POST` | `/api/v1/bot-marketplace/:id/reviews` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.ReviewMarketplace` | `backend/cmd/server/main.go:1137` |
| `POST` | `/api/v1/bot-orders` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.CreateOrder` | `backend/cmd/server/main.go:1138` |
| `GET` | `/api/v1/bot-orders/:id/ledger` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.OrderLedger` | `backend/cmd/server/main.go:1141` |
| `POST` | `/api/v1/bot-orders/:id/pay` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.PayOrder` | `backend/cmd/server/main.go:1139` |
| `POST` | `/api/v1/bot-orders/:id/refund` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.RefundOrder` | `backend/cmd/server/main.go:1140` |
| `GET` | `/api/v1/bots` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.List` | `backend/cmd/server/main.go:1119` |
| `POST` | `/api/v1/bots` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.Create` | `backend/cmd/server/main.go:1118` |
| `DELETE` | `/api/v1/bots/:bot_id` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.Delete` | `backend/cmd/server/main.go:1132` |
| `GET` | `/api/v1/bots/:bot_id` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.Get` | `backend/cmd/server/main.go:1120` |
| `PUT` | `/api/v1/bots/:bot_id/commands` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.SetCommands` | `backend/cmd/server/main.go:1126` |
| `GET` | `/api/v1/bots/:bot_id/diagnostics` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.Diagnostics` | `backend/cmd/server/main.go:1128` |
| `GET` | `/api/v1/bots/:bot_id/diagnostics/updates` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.DiagnosticUpdates` | `backend/cmd/server/main.go:1129` |
| `POST` | `/api/v1/bots/:bot_id/diagnostics/updates/:update_id/replay` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.ReplayUpdate` | `backend/cmd/server/main.go:1130` |
| `POST` | `/api/v1/bots/:bot_id/inline-query` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.InlineQuery` | `backend/cmd/server/main.go:1122` |
| `DELETE` | `/api/v1/bots/:bot_id/session` | Bearer Token；通常要求已绑定手机号 | `botInteractionHandler.Stop` | `backend/cmd/server/main.go:1125` |
| `POST` | `/api/v1/bots/:bot_id/start` | Bearer Token；通常要求已绑定手机号 | `botInteractionHandler.Start` | `backend/cmd/server/main.go:1121` |
| `POST` | `/api/v1/bots/:bot_id/token/reset` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.ResetToken` | `backend/cmd/server/main.go:1127` |
| `POST` | `/api/v1/bots/:bot_id/webhook/test` | Bearer Token；通常要求已绑定手机号 | `botDeveloperHandler.TestWebhook` | `backend/cmd/server/main.go:1131` |
| `POST` | `/api/v1/bots/inline-queries/:id/chosen` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.MarkInlineChosen` | `backend/cmd/server/main.go:1124` |
| `DELETE` | `/api/v1/call/:call_id` | Bearer Token；通常要求已绑定手机号 | `callHandler.CancelCall` | `backend/cmd/server/main.go:1395` |
| `POST` | `/api/v1/call/accept` | Bearer Token；通常要求已绑定手机号 | `callHandler.AcceptCall` | `backend/cmd/server/main.go:1388` |
| `GET` | `/api/v1/call/active` | Bearer Token；通常要求已绑定手机号 | `callHandler.GetActiveCall` | `backend/cmd/server/main.go:1394` |
| `GET` | `/api/v1/call/config` | Bearer Token；通常要求已绑定手机号 | `callHandler.GetRTCConfig` | `backend/cmd/server/main.go:1385` |
| `POST` | `/api/v1/call/connected` | Bearer Token；通常要求已绑定手机号 | `callHandler.MarkCallMediaReady` | `backend/cmd/server/main.go:1389` |
| `POST` | `/api/v1/call/create` | Bearer Token；通常要求已绑定手机号 | `callHandler.CreateCall` | `backend/cmd/server/main.go:1387` |
| `POST` | `/api/v1/call/end` | Bearer Token；通常要求已绑定手机号 | `callHandler.EndCall` | `backend/cmd/server/main.go:1391` |
| `POST` | `/api/v1/call/heartbeat` | Bearer Token；通常要求已绑定手机号 | `callHandler.HeartbeatCall` | `backend/cmd/server/main.go:1392` |
| `GET` | `/api/v1/call/history` | Bearer Token；通常要求已绑定手机号 | `callHandler.GetCallHistory` | `backend/cmd/server/main.go:1396` |
| `POST` | `/api/v1/call/media-state` | Bearer Token；通常要求已绑定手机号 | `callHandler.UpdateCallMediaState` | `backend/cmd/server/main.go:1393` |
| `POST` | `/api/v1/call/reject` | Bearer Token；通常要求已绑定手机号 | `callHandler.RejectCall` | `backend/cmd/server/main.go:1390` |
| `GET` | `/api/v1/call/token` | Bearer Token；通常要求已绑定手机号 | `callHandler.GetToken` | `backend/cmd/server/main.go:1386` |
| `POST` | `/api/v1/capacity-agent/bandwidth-results` | 容量 Agent 签名鉴权 | `handler.SubmitBandwidthResult` | `backend/internal/handlers/capacity_handler.go:60` |
| `GET` | `/api/v1/capacity-agent/bandwidth-tasks` | 容量 Agent 签名鉴权 | `handler.ListBandwidthTasks` | `backend/internal/handlers/capacity_handler.go:61` |
| `POST` | `/api/v1/capacity-agent/heartbeat` | 容量 Agent 签名鉴权 | `handler.Heartbeat` | `backend/internal/handlers/capacity_handler.go:58` |
| `POST` | `/api/v1/capacity-agent/register` | 容量 Agent 签名鉴权 | `handler.Register` | `backend/internal/handlers/capacity_handler.go:57` |
| `POST` | `/api/v1/capacity-agent/samples` | 容量 Agent 签名鉴权 | `handler.SubmitSample` | `backend/internal/handlers/capacity_handler.go:59` |
| `DELETE` | `/api/v1/chat/:id` | Bearer Token；通常要求已绑定手机号 | `chatHandler.DeleteChat` | `backend/cmd/server/main.go:1216` |
| `GET` | `/api/v1/chat/:id` | Bearer Token；通常要求已绑定手机号 | `chatHandler.GetChat` | `backend/cmd/server/main.go:1214` |
| `PUT` | `/api/v1/chat/:id` | Bearer Token；通常要求已绑定手机号 | `chatHandler.UpdateChat` | `backend/cmd/server/main.go:1215` |
| `GET` | `/api/v1/chat/:id/ai-automation-rules` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.ListAutomationRules` | `backend/cmd/server/main.go:1275` |
| `POST` | `/api/v1/chat/:id/ai-automation-rules` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.CreateAutomationRule` | `backend/cmd/server/main.go:1276` |
| `GET` | `/api/v1/chat/:id/ai-policy` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.GetGroupPolicy` | `backend/cmd/server/main.go:1271` |
| `PUT` | `/api/v1/chat/:id/ai-policy` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.SaveGroupPolicy` | `backend/cmd/server/main.go:1272` |
| `GET` | `/api/v1/chat/:id/ai-summaries` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.ListSummaries` | `backend/cmd/server/main.go:1274` |
| `POST` | `/api/v1/chat/:id/ai-summary` | Bearer Token；通常要求已绑定手机号 | `aiInteractionHandler.GenerateSummary` | `backend/cmd/server/main.go:1273` |
| `GET` | `/api/v1/chat/:id/announcements` | Bearer Token；通常要求已绑定手机号 | `announcementHandler.GetAnnouncements` | `backend/cmd/server/main.go:1249` |
| `POST` | `/api/v1/chat/:id/announcements` | Bearer Token；通常要求已绑定手机号 | `announcementHandler.CreateAnnouncement` | `backend/cmd/server/main.go:1250` |
| `DELETE` | `/api/v1/chat/:id/announcements/:announcement_id` | Bearer Token；通常要求已绑定手机号 | `announcementHandler.DeleteAnnouncement` | `backend/cmd/server/main.go:1252` |
| `PUT` | `/api/v1/chat/:id/announcements/:announcement_id` | Bearer Token；通常要求已绑定手机号 | `announcementHandler.UpdateAnnouncement` | `backend/cmd/server/main.go:1251` |
| `POST` | `/api/v1/chat/:id/announcements/:announcement_id/acknowledge` | Bearer Token；通常要求已绑定手机号 | `announcementHandler.AcknowledgeAnnouncement` | `backend/cmd/server/main.go:1253` |
| `GET` | `/api/v1/chat/:id/auto-messages` | Bearer Token；通常要求已绑定手机号 | `chatHandler.ListAutoMessages` | `backend/cmd/server/main.go:1254` |
| `POST` | `/api/v1/chat/:id/auto-messages` | Bearer Token；通常要求已绑定手机号 | `chatHandler.CreateAutoMessage` | `backend/cmd/server/main.go:1255` |
| `DELETE` | `/api/v1/chat/:id/auto-messages/:auto_message_id` | Bearer Token；通常要求已绑定手机号 | `chatHandler.DeleteAutoMessage` | `backend/cmd/server/main.go:1257` |
| `PUT` | `/api/v1/chat/:id/auto-messages/:auto_message_id` | Bearer Token；通常要求已绑定手机号 | `chatHandler.UpdateAutoMessage` | `backend/cmd/server/main.go:1256` |
| `GET` | `/api/v1/chat/:id/bot-automation-runs` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.AutomationRuns` | `backend/cmd/server/main.go:1270` |
| `POST` | `/api/v1/chat/:id/bot-callback` | Bearer Token；通常要求已绑定手机号 | `botInteractionHandler.Callback` | `backend/cmd/server/main.go:1264` |
| `GET` | `/api/v1/chat/:id/bot-keywords` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.ListKeywords` | `backend/cmd/server/main.go:1266` |
| `POST` | `/api/v1/chat/:id/bot-keywords` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.CreateKeyword` | `backend/cmd/server/main.go:1267` |
| `DELETE` | `/api/v1/chat/:id/bot-keywords/:rule_id` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.DeleteKeyword` | `backend/cmd/server/main.go:1269` |
| `PUT` | `/api/v1/chat/:id/bot-keywords/:rule_id` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.UpdateKeyword` | `backend/cmd/server/main.go:1268` |
| `GET` | `/api/v1/chat/:id/bot-welcome` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.GetWelcome` | `backend/cmd/server/main.go:1262` |
| `PUT` | `/api/v1/chat/:id/bot-welcome` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.SetWelcome` | `backend/cmd/server/main.go:1263` |
| `GET` | `/api/v1/chat/:id/bots` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.List` | `backend/cmd/server/main.go:1258` |
| `POST` | `/api/v1/chat/:id/bots` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.Add` | `backend/cmd/server/main.go:1259` |
| `DELETE` | `/api/v1/chat/:id/bots/:bot_id` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.Remove` | `backend/cmd/server/main.go:1261` |
| `PUT` | `/api/v1/chat/:id/bots/:bot_id/permissions` | Bearer Token；通常要求已绑定手机号 | `groupBotHandler.UpdatePermission` | `backend/cmd/server/main.go:1260` |
| `POST` | `/api/v1/chat/:id/clear` | Bearer Token；通常要求已绑定手机号 | `chatHandler.ClearChatHistory` | `backend/cmd/server/main.go:1278` |
| `POST` | `/api/v1/chat/:id/clear-both` | Bearer Token；通常要求已绑定手机号 | `chatHandler.ClearChatHistoryForBoth` | `backend/cmd/server/main.go:1279` |
| `POST` | `/api/v1/chat/:id/clear-messages` | Bearer Token；通常要求已绑定手机号 | `chatHandler.ClearGroupMessages` | `backend/cmd/server/main.go:1280` |
| `POST` | `/api/v1/chat/:id/hide` | Bearer Token；通常要求已绑定手机号 | `chatHandler.HideChat` | `backend/cmd/server/main.go:1228` |
| `POST` | `/api/v1/chat/:id/join` | Bearer Token；通常要求已绑定手机号 | `chatHandler.JoinChat` | `backend/cmd/server/main.go:1230` |
| `GET` | `/api/v1/chat/:id/join-requests` | Bearer Token；通常要求已绑定手机号 | `chatHandler.GetJoinRequests` | `backend/cmd/server/main.go:1232` |
| `POST` | `/api/v1/chat/:id/join-requests/:request_id/review` | Bearer Token；通常要求已绑定手机号 | `chatHandler.ReviewJoinRequest` | `backend/cmd/server/main.go:1233` |
| `POST` | `/api/v1/chat/:id/leave` | Bearer Token；通常要求已绑定手机号 | `chatHandler.LeaveChat` | `backend/cmd/server/main.go:1227` |
| `GET` | `/api/v1/chat/:id/members` | Bearer Token；通常要求已绑定手机号 | `chatHandler.GetMembers` | `backend/cmd/server/main.go:1219` |
| `POST` | `/api/v1/chat/:id/members` | Bearer Token；通常要求已绑定手机号 | `chatHandler.AddMembers` | `backend/cmd/server/main.go:1221` |
| `DELETE` | `/api/v1/chat/:id/members/:user_id` | Bearer Token；通常要求已绑定手机号 | `chatHandler.RemoveMember` | `backend/cmd/server/main.go:1222` |
| `PUT` | `/api/v1/chat/:id/members/:user_id/nickname` | Bearer Token；通常要求已绑定手机号 | `chatHandler.UpdateMemberNickname` | `backend/cmd/server/main.go:1223` |
| `GET` | `/api/v1/chat/:id/members/:user_id/permissions` | Bearer Token；通常要求已绑定手机号 | `chatHandler.GetMemberPermissions` | `backend/cmd/server/main.go:1225` |
| `PUT` | `/api/v1/chat/:id/members/:user_id/permissions` | Bearer Token；通常要求已绑定手机号 | `chatHandler.UpdateMemberPermissions` | `backend/cmd/server/main.go:1226` |
| `PUT` | `/api/v1/chat/:id/members/:user_id/role` | Bearer Token；通常要求已绑定手机号 | `chatHandler.SetMemberRole` | `backend/cmd/server/main.go:1224` |
| `GET` | `/api/v1/chat/:id/members/search` | Bearer Token；通常要求已绑定手机号 | `chatHandler.SearchMembers` | `backend/cmd/server/main.go:1220` |
| `POST` | `/api/v1/chat/:id/mute` | Bearer Token；通常要求已绑定手机号 | `chatHandler.MuteMember` | `backend/cmd/server/main.go:1235` |
| `POST` | `/api/v1/chat/:id/mute-chat` | Bearer Token；通常要求已绑定手机号 | `chatHandler.ToggleMuteChat` | `backend/cmd/server/main.go:1240` |
| `GET` | `/api/v1/chat/:id/mute-status` | Bearer Token；通常要求已绑定手机号 | `chatHandler.GetMemberMuteStatus` | `backend/cmd/server/main.go:1237` |
| `GET` | `/api/v1/chat/:id/my-permissions` | Bearer Token；通常要求已绑定手机号 | `chatHandler.GetMyPermissions` | `backend/cmd/server/main.go:1218` |
| `PUT` | `/api/v1/chat/:id/owner` | Bearer Token；通常要求已绑定手机号 | `chatHandler.TransferChatOwner` | `backend/cmd/server/main.go:1217` |
| `POST` | `/api/v1/chat/:id/pin` | Bearer Token；通常要求已绑定手机号 | `chatHandler.TogglePin` | `backend/cmd/server/main.go:1239` |
| `DELETE` | `/api/v1/chat/:id/pin-message` | Bearer Token；通常要求已绑定手机号 | `pinHandler.UnpinMessage` | `backend/cmd/server/main.go:1245` |
| `GET` | `/api/v1/chat/:id/pin-message` | Bearer Token；通常要求已绑定手机号 | `pinHandler.GetPinnedMessage` | `backend/cmd/server/main.go:1246` |
| `POST` | `/api/v1/chat/:id/pin-message` | Bearer Token；通常要求已绑定手机号 | `pinHandler.PinMessage` | `backend/cmd/server/main.go:1244` |
| `GET` | `/api/v1/chat/:id/search` | Bearer Token；通常要求已绑定手机号 | `chatHandler.SearchMessages` | `backend/cmd/server/main.go:1281` |
| `POST` | `/api/v1/chat/:id/toggle-unread` | Bearer Token；通常要求已绑定手机号 | `chatHandler.ToggleUnread` | `backend/cmd/server/main.go:1241` |
| `POST` | `/api/v1/chat/:id/unmute` | Bearer Token；通常要求已绑定手机号 | `chatHandler.UnmuteMember` | `backend/cmd/server/main.go:1236` |
| `GET` | `/api/v1/chat/bot-callbacks/:callback_id` | Bearer Token；通常要求已绑定手机号 | `botInteractionHandler.CallbackStatus` | `backend/cmd/server/main.go:1265` |
| `POST` | `/api/v1/chat/create` | Bearer Token；通常要求已绑定手机号 | `chatHandler.CreateChat` | `backend/cmd/server/main.go:1213` |
| `POST` | `/api/v1/chat/invite/:invite_link/join` | Bearer Token；通常要求已绑定手机号 | `chatHandler.JoinChatByInviteLink` | `backend/cmd/server/main.go:1229` |
| `GET` | `/api/v1/chat/list` | Bearer Token；通常要求已绑定手机号 | `chatHandler.GetChatList` | `backend/cmd/server/main.go:1212` |
| `GET` | `/api/v1/client/bootstrap` | 公开 | `clientBootstrapHandler.GetBootstrap` | `backend/cmd/server/main.go:1084` |
| `DELETE` | `/api/v1/contact/:id` | Bearer Token；通常要求已绑定手机号 | `contactHandler.DeleteContact` | `backend/cmd/server/main.go:1326` |
| `PUT` | `/api/v1/contact/:id/remark` | Bearer Token；通常要求已绑定手机号 | `contactHandler.UpdateRemark` | `backend/cmd/server/main.go:1327` |
| `POST` | `/api/v1/contact/add` | Bearer Token；通常要求已绑定手机号 | `contactHandler.AddContact` | `backend/cmd/server/main.go:1321` |
| `GET` | `/api/v1/contact/list` | Bearer Token；通常要求已绑定手机号 | `contactHandler.GetContacts` | `backend/cmd/server/main.go:1320` |
| `GET` | `/api/v1/contact/requests` | Bearer Token；通常要求已绑定手机号 | `contactHandler.ListFriendRequests` | `backend/cmd/server/main.go:1322` |
| `POST` | `/api/v1/contact/requests` | Bearer Token；通常要求已绑定手机号 | `contactHandler.SendFriendRequest` | `backend/cmd/server/main.go:1323` |
| `POST` | `/api/v1/contact/requests/:id/accept` | Bearer Token；通常要求已绑定手机号 | `contactHandler.AcceptFriendRequest` | `backend/cmd/server/main.go:1324` |
| `POST` | `/api/v1/contact/requests/:id/reject` | Bearer Token；通常要求已绑定手机号 | `contactHandler.RejectFriendRequest` | `backend/cmd/server/main.go:1325` |
| `GET` | `/api/v1/link-preview` | Bearer Token；通常要求已绑定手机号 | `linkPreviewHandler.GetPreview` | `backend/cmd/server/main.go:1336` |
| `GET` | `/api/v1/media/:id/access-url` | Bearer Token；通常要求已绑定手机号 | `mediaUploadHandler.AccessURL` | `backend/cmd/server/main.go:1458` |
| `POST` | `/api/v1/media/access-urls` | Bearer Token；通常要求已绑定手机号 | `mediaUploadHandler.BatchAccessURLs` | `backend/cmd/server/main.go:1459` |
| `GET` | `/api/v1/media/uploads/:id` | Bearer Token；通常要求已绑定手机号 | `mediaUploadHandler.Status` | `backend/cmd/server/main.go:1453` |
| `POST` | `/api/v1/media/uploads/:id/abort` | Bearer Token；通常要求已绑定手机号 | `mediaUploadHandler.Abort` | `backend/cmd/server/main.go:1456` |
| `POST` | `/api/v1/media/uploads/:id/complete` | Bearer Token；通常要求已绑定手机号 | `mediaUploadHandler.Complete` | `backend/cmd/server/main.go:1455` |
| `POST` | `/api/v1/media/uploads/:id/parts/presign` | Bearer Token；通常要求已绑定手机号 | `mediaUploadHandler.PresignParts` | `backend/cmd/server/main.go:1454` |
| `POST` | `/api/v1/media/uploads/init` | Bearer Token；通常要求已绑定手机号 | `middleware.UploadInitRateLimit` | `backend/cmd/server/main.go:1452` |
| `GET` | `/api/v1/meeting/active` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.GetActiveMeeting` | `backend/cmd/server/main.go:1428` |
| `POST` | `/api/v1/meeting/create` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.CreateMeeting` | `backend/cmd/server/main.go:1416` |
| `GET` | `/api/v1/meeting/detail` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.GetMeetingDetail` | `backend/cmd/server/main.go:1427` |
| `POST` | `/api/v1/meeting/end` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.EndMeeting` | `backend/cmd/server/main.go:1422` |
| `POST` | `/api/v1/meeting/host/transfer` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.TransferHost` | `backend/cmd/server/main.go:1425` |
| `POST` | `/api/v1/meeting/invite` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.InviteMembers` | `backend/cmd/server/main.go:1421` |
| `POST` | `/api/v1/meeting/join` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.JoinMeeting` | `backend/cmd/server/main.go:1417` |
| `POST` | `/api/v1/meeting/join-request/review` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.ReviewJoinRequest` | `backend/cmd/server/main.go:1418` |
| `POST` | `/api/v1/meeting/leave` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.LeaveMeeting` | `backend/cmd/server/main.go:1420` |
| `POST` | `/api/v1/meeting/member/kick` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.KickMember` | `backend/cmd/server/main.go:1424` |
| `POST` | `/api/v1/meeting/member/mute` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.MuteMember` | `backend/cmd/server/main.go:1423` |
| `POST` | `/api/v1/meeting/title` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.UpdateMeetingTitle` | `backend/cmd/server/main.go:1419` |
| `GET` | `/api/v1/meeting/token` | Bearer Token；通常要求已绑定手机号 | `meetingHandler.GetToken` | `backend/cmd/server/main.go:1426` |
| `POST` | `/api/v1/message/delete` | Bearer Token；通常要求已绑定手机号 | `msgHandler.DeleteMessage` | `backend/cmd/server/main.go:1295` |
| `POST` | `/api/v1/message/delivered` | Bearer Token；通常要求已绑定手机号 | `msgHandler.MarkAsDelivered` | `backend/cmd/server/main.go:1298` |
| `GET` | `/api/v1/message/detail` | Bearer Token；通常要求已绑定手机号 | `msgHandler.GetMessageDetail` | `backend/cmd/server/main.go:1293` |
| `GET` | `/api/v1/message/e2ee/device-keys` | Bearer Token；通常要求已绑定手机号 | `msgHandler.GetChatDeviceKeys` | `backend/cmd/server/main.go:1289` |
| `POST` | `/api/v1/message/edit` | Bearer Token；通常要求已绑定手机号 | `msgHandler.EditMessage` | `backend/cmd/server/main.go:1308` |
| `POST` | `/api/v1/message/favorite` | Bearer Token；通常要求已绑定手机号 | `msgHandler.AddMessageFavorite` | `backend/cmd/server/main.go:1304` |
| `DELETE` | `/api/v1/message/favorite/:chat_id/:message_id` | Bearer Token；通常要求已绑定手机号 | `msgHandler.DeleteMessageFavorite` | `backend/cmd/server/main.go:1307` |
| `GET` | `/api/v1/message/favorites` | Bearer Token；通常要求已绑定手机号 | `msgHandler.ListMessageFavorites` | `backend/cmd/server/main.go:1305` |
| `GET` | `/api/v1/message/favorites/sync` | Bearer Token；通常要求已绑定手机号 | `msgHandler.SyncMessageFavorites` | `backend/cmd/server/main.go:1306` |
| `POST` | `/api/v1/message/forward` | Bearer Token；通常要求已绑定手机号 | `msgHandler.ForwardMessage` | `backend/cmd/server/main.go:1303` |
| `GET` | `/api/v1/message/list` | Bearer Token；通常要求已绑定手机号 | `msgHandler.GetMessages` | `backend/cmd/server/main.go:1292` |
| `GET` | `/api/v1/message/media` | Bearer Token；通常要求已绑定手机号 | `msgHandler.GetChatMedia` | `backend/cmd/server/main.go:1312` |
| `GET` | `/api/v1/message/media/count` | Bearer Token；通常要求已绑定手机号 | `msgHandler.GetChatMediaCount` | `backend/cmd/server/main.go:1313` |
| `POST` | `/api/v1/message/reaction/add` | Bearer Token；通常要求已绑定手机号 | `msgHandler.AddReaction` | `backend/cmd/server/main.go:1300` |
| `POST` | `/api/v1/message/reaction/remove` | Bearer Token；通常要求已绑定手机号 | `msgHandler.RemoveReaction` | `backend/cmd/server/main.go:1301` |
| `POST` | `/api/v1/message/read` | Bearer Token；通常要求已绑定手机号 | `msgHandler.MarkAsRead` | `backend/cmd/server/main.go:1297` |
| `GET` | `/api/v1/message/recovery-capabilities` | Bearer Token；通常要求已绑定手机号 | `msgHandler.GetRecoveryCapabilities` | `backend/cmd/server/main.go:1290` |
| `POST` | `/api/v1/message/revoke` | Bearer Token；通常要求已绑定手机号 | `msgHandler.RevokeMessage` | `backend/cmd/server/main.go:1294` |
| `POST` | `/api/v1/message/send` | Bearer Token；通常要求已绑定手机号 | `msgHandler.SendMessage` | `backend/cmd/server/main.go:1291` |
| `POST` | `/api/v1/message/sync` | Bearer Token；通常要求已绑定手机号 | `msgHandler.SyncMessages` | `backend/cmd/server/main.go:1296` |
| `POST` | `/api/v1/message/translate` | Bearer Token；通常要求已绑定手机号 | `msgHandler.TranslateMessage` | `backend/cmd/server/main.go:1310` |
| `POST` | `/api/v1/message/voice/transcribe` | Bearer Token；通常要求已绑定手机号 | `msgHandler.TranscribeVoiceMessage` | `backend/cmd/server/main.go:1309` |
| `POST` | `/api/v1/mini-apps/:id/launch` | Bearer Token；通常要求已绑定手机号 | `ecosystemHandler.LaunchMiniApp` | `backend/cmd/server/main.go:1134` |
| `POST` | `/api/v1/mini-apps/session/exchange` | 公开 | `ecosystemHandler.ExchangeMiniApp` | `backend/cmd/server/main.go:1056` |
| `POST` | `/api/v1/mini-apps/session/verify` | 公开 | `ecosystemHandler.VerifyMiniApp` | `backend/cmd/server/main.go:1057` |
| `DELETE` | `/api/v1/moment/:id` | Bearer Token；通常要求已绑定手机号 | `momentHandler.DeleteMoment` | `backend/cmd/server/main.go:1347` |
| `GET` | `/api/v1/moment/:id` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetMoment` | `backend/cmd/server/main.go:1343` |
| `PUT` | `/api/v1/moment/:id` | Bearer Token；通常要求已绑定手机号 | `momentHandler.UpdateMoment` | `backend/cmd/server/main.go:1346` |
| `POST` | `/api/v1/moment/:id/block` | Bearer Token；通常要求已绑定手机号 | `momentHandler.BlockMoment` | `backend/cmd/server/main.go:1362` |
| `POST` | `/api/v1/moment/:id/comment` | Bearer Token；通常要求已绑定手机号 | `momentHandler.AddComment` | `backend/cmd/server/main.go:1351` |
| `GET` | `/api/v1/moment/:id/comments` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetComments` | `backend/cmd/server/main.go:1350` |
| `GET` | `/api/v1/moment/:id/detail` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetMoment` | `backend/cmd/server/main.go:1344` |
| `POST` | `/api/v1/moment/:id/like` | Bearer Token；通常要求已绑定手机号 | `momentHandler.LikeMoment` | `backend/cmd/server/main.go:1348` |
| `POST` | `/api/v1/moment/:id/unlike` | Bearer Token；通常要求已绑定手机号 | `momentHandler.UnlikeMoment` | `backend/cmd/server/main.go:1349` |
| `POST` | `/api/v1/moment/block-user/:userId` | Bearer Token；通常要求已绑定手机号 | `momentHandler.BlockUser` | `backend/cmd/server/main.go:1363` |
| `POST` | `/api/v1/moment/comments/:commentId/like` | Bearer Token；通常要求已绑定手机号 | `momentHandler.LikeComment` | `backend/cmd/server/main.go:1352` |
| `POST` | `/api/v1/moment/comments/:commentId/unlike` | Bearer Token；通常要求已绑定手机号 | `momentHandler.UnlikeComment` | `backend/cmd/server/main.go:1353` |
| `GET` | `/api/v1/moment/list` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetMomentList` | `backend/cmd/server/main.go:1342` |
| `GET` | `/api/v1/moment/my/comments` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetMyComments` | `backend/cmd/server/main.go:1358` |
| `GET` | `/api/v1/moment/my/likes` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetMyLikes` | `backend/cmd/server/main.go:1357` |
| `GET` | `/api/v1/moment/my/moments` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetMyMoments` | `backend/cmd/server/main.go:1356` |
| `GET` | `/api/v1/moment/my/received-likes` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetReceivedLikes` | `backend/cmd/server/main.go:1359` |
| `POST` | `/api/v1/moment/publish` | Bearer Token；通常要求已绑定手机号 | `momentHandler.PublishMoment` | `backend/cmd/server/main.go:1345` |
| `GET` | `/api/v1/moment/search` | Bearer Token；通常要求已绑定手机号 | `momentHandler.SearchMoments` | `backend/cmd/server/main.go:1360` |
| `GET` | `/api/v1/moment/topics/hot` | Bearer Token；通常要求已绑定手机号 | `momentHandler.GetHotTopics` | `backend/cmd/server/main.go:1354` |
| `POST` | `/api/v1/payment/notify/alipay` | 公开 | `onlinePayHandler.AlipayNotify` | `backend/cmd/server/main.go:1071` |
| `POST` | `/api/v1/payment/notify/wechat` | 公开 | `onlinePayHandler.WeChatNotify` | `backend/cmd/server/main.go:1070` |
| `GET` | `/api/v1/ping` | 公开 | `func` | `backend/cmd/server/main.go:1074` |
| `GET` | `/api/v1/public/user/:id` | 公开 | `middleware.RateLimit` | `backend/cmd/server/main.go:1110` |
| `POST` | `/api/v1/report` | Bearer Token；通常要求已绑定手机号 | `reportHandler.CreateReport` | `backend/cmd/server/main.go:1332` |
| `GET` | `/api/v1/search/global` | Bearer Token；通常要求已绑定手机号 | `searchHandler.Search` | `backend/cmd/server/main.go:1207` |
| `GET` | `/api/v1/service-admin/agents/available` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.GetAvailableAgents` | `backend/cmd/server/main.go:1539` |
| `POST` | `/api/v1/service-admin/agreement/accept` | Bearer Token（该路由显式鉴权） | `func` | `backend/cmd/server/main.go:1522` |
| `GET` | `/api/v1/service-admin/agreement/current` | Bearer Token（该路由显式鉴权） | `func` | `backend/cmd/server/main.go:1519` |
| `POST` | `/api/v1/service-admin/auth/login` | 公开 | `serviceAdminHandler.Login` | `backend/cmd/server/main.go:1515` |
| `POST` | `/api/v1/service-admin/auth/logout` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.Logout` | `backend/cmd/server/main.go:1525` |
| `GET` | `/api/v1/service-admin/conversations` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.ListConversations` | `backend/cmd/server/main.go:1540` |
| `GET` | `/api/v1/service-admin/conversations/:uuid` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.GetConversation` | `backend/cmd/server/main.go:1541` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/accept` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.AcceptConversation` | `backend/cmd/server/main.go:1545` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/claim` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.ClaimConversation` | `backend/cmd/server/main.go:1544` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/close` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.CloseConversation` | `backend/cmd/server/main.go:1548` |
| `GET` | `/api/v1/service-admin/conversations/:uuid/messages` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.GetMessages` | `backend/cmd/server/main.go:1542` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/messages` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.SendMessage` | `backend/cmd/server/main.go:1543` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/read` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.MarkConversationRead` | `backend/cmd/server/main.go:1550` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/reopen` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.ReopenConversation` | `backend/cmd/server/main.go:1549` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/status` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.ChangeConversationStatus` | `backend/cmd/server/main.go:1547` |
| `POST` | `/api/v1/service-admin/conversations/:uuid/transfer` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.TransferConversation` | `backend/cmd/server/main.go:1546` |
| `GET` | `/api/v1/service-admin/customers` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.ListCustomers` | `backend/cmd/server/main.go:1555` |
| `GET` | `/api/v1/service-admin/customers/:uuid` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.GetCustomer` | `backend/cmd/server/main.go:1556` |
| `POST` | `/api/v1/service-admin/customers/:uuid/follow-ups` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.CreateFollowUp` | `backend/cmd/server/main.go:1559` |
| `PUT` | `/api/v1/service-admin/customers/:uuid/profile` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.UpdateCustomerProfile` | `backend/cmd/server/main.go:1557` |
| `GET` | `/api/v1/service-admin/dashboard` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.GetDashboard` | `backend/cmd/server/main.go:1531` |
| `GET` | `/api/v1/service-admin/follow-ups` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.ListFollowUps` | `backend/cmd/server/main.go:1558` |
| `PATCH` | `/api/v1/service-admin/follow-ups/:uuid` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.UpdateFollowUp` | `backend/cmd/server/main.go:1560` |
| `GET` | `/api/v1/service-admin/invite-code` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.GetInviteCode` | `backend/cmd/server/main.go:1532` |
| `GET` | `/api/v1/service-admin/invitees` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.GetInvitees` | `backend/cmd/server/main.go:1533` |
| `PUT` | `/api/v1/service-admin/password` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.UpdatePassword` | `backend/cmd/server/main.go:1527` |
| `POST` | `/api/v1/service-admin/phone/bind` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.BindPhone` | `backend/cmd/server/main.go:1529` |
| `POST` | `/api/v1/service-admin/phone/send-bind-code` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.SendPhoneBindCode` | `backend/cmd/server/main.go:1528` |
| `GET` | `/api/v1/service-admin/presence` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.GetPresence` | `backend/cmd/server/main.go:1536` |
| `PUT` | `/api/v1/service-admin/presence` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.UpdatePresence` | `backend/cmd/server/main.go:1537` |
| `POST` | `/api/v1/service-admin/presence/heartbeat` | Bearer Token（该路由显式鉴权） | `serviceWorkbenchHandler.Heartbeat` | `backend/cmd/server/main.go:1538` |
| `GET` | `/api/v1/service-admin/profile` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.GetProfile` | `backend/cmd/server/main.go:1530` |
| `GET` | `/api/v1/service-admin/quick-replies` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.ListQuickReplies` | `backend/cmd/server/main.go:1551` |
| `POST` | `/api/v1/service-admin/quick-replies` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.CreateQuickReply` | `backend/cmd/server/main.go:1552` |
| `DELETE` | `/api/v1/service-admin/quick-replies/:uuid` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.DeleteQuickReply` | `backend/cmd/server/main.go:1554` |
| `PUT` | `/api/v1/service-admin/quick-replies/:uuid` | Bearer Token（该路由显式鉴权） | `serviceOperationHandler.UpdateQuickReply` | `backend/cmd/server/main.go:1553` |
| `GET` | `/api/v1/service-admin/welcome-message` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.GetWelcomeMessage` | `backend/cmd/server/main.go:1534` |
| `PATCH` | `/api/v1/service-admin/welcome-message` | Bearer Token（该路由显式鉴权） | `serviceAdminHandler.UpdateWelcomeMessage` | `backend/cmd/server/main.go:1535` |
| `POST` | `/api/v1/upload/avatar` | Bearer Token；通常要求已绑定手机号 | `uploadHandler.UploadAvatar` | `backend/cmd/server/main.go:1443` |
| `POST` | `/api/v1/upload/file` | Bearer Token；通常要求已绑定手机号 | `uploadHandler.UploadFile` | `backend/cmd/server/main.go:1445` |
| `POST` | `/api/v1/upload/image` | Bearer Token；通常要求已绑定手机号 | `uploadHandler.UploadImage` | `backend/cmd/server/main.go:1440` |
| `POST` | `/api/v1/upload/images` | Bearer Token；通常要求已绑定手机号 | `uploadHandler.UploadMultipleImages` | `backend/cmd/server/main.go:1441` |
| `POST` | `/api/v1/upload/video` | Bearer Token；通常要求已绑定手机号 | `uploadHandler.UploadVideo` | `backend/cmd/server/main.go:1442` |
| `POST` | `/api/v1/upload/voice` | Bearer Token；通常要求已绑定手机号 | `uploadHandler.UploadVoice` | `backend/cmd/server/main.go:1444` |
| `GET` | `/api/v1/user-settings/official-service/profile` | 公开 | `settingHandler.GetMyOfficialServiceProfile` | `backend/cmd/server/main.go:1965` |
| `PUT` | `/api/v1/user-settings/official-service/profile` | 公开 | `settingHandler.UpdateMyOfficialServiceProfile` | `backend/cmd/server/main.go:1966` |
| `POST` | `/api/v1/user-settings/sync-official-contacts` | 公开 | `settingHandler.SyncOfficialContacts` | `backend/cmd/server/main.go:1964` |
| `GET` | `/api/v1/user/:id` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetUser` | `backend/cmd/server/main.go:1201` |
| `GET` | `/api/v1/user/:id/common-groups` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetCommonGroups` | `backend/cmd/server/main.go:1202` |
| `GET` | `/api/v1/user/:id/common-info` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetCommonInfo` | `backend/cmd/server/main.go:1200` |
| `DELETE` | `/api/v1/user/account` | Bearer Token；通常要求已绑定手机号 | `userHandler.DeleteAccount` | `backend/cmd/server/main.go:1198` |
| `POST` | `/api/v1/user/account/send-delete-code` | Bearer Token；通常要求已绑定手机号 | `middleware.WalletRateLimit` | `backend/cmd/server/main.go:1160` |
| `GET` | `/api/v1/user/blocked` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetBlockedUsers` | `backend/cmd/server/main.go:1176` |
| `POST` | `/api/v1/user/blocked` | Bearer Token；通常要求已绑定手机号 | `userHandler.BlockUser` | `backend/cmd/server/main.go:1178` |
| `DELETE` | `/api/v1/user/blocked/:blocked_id` | Bearer Token；通常要求已绑定手机号 | `userHandler.UnblockUser` | `backend/cmd/server/main.go:1179` |
| `GET` | `/api/v1/user/blocked/check` | Bearer Token；通常要求已绑定手机号 | `userHandler.CheckBlockStatus` | `backend/cmd/server/main.go:1177` |
| `POST` | `/api/v1/user/check-username` | Bearer Token；通常要求已绑定手机号 | `userHandler.CheckUsername` | `backend/cmd/server/main.go:1155` |
| `POST` | `/api/v1/user/device-identity/migrate` | Bearer Token；通常要求已绑定手机号 | `userHandler.MigrateDeviceIdentity` | `backend/cmd/server/main.go:1146` |
| `GET` | `/api/v1/user/devices` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetDevices` | `backend/cmd/server/main.go:1185` |
| `DELETE` | `/api/v1/user/devices/:device_id` | Bearer Token；通常要求已绑定手机号 | `userHandler.TerminateDevice` | `backend/cmd/server/main.go:1188` |
| `POST` | `/api/v1/user/devices/register-push` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdatePushToken` | `backend/cmd/server/main.go:1186` |
| `POST` | `/api/v1/user/devices/terminate-others` | Bearer Token；通常要求已绑定手机号 | `userHandler.TerminateOtherDevices` | `backend/cmd/server/main.go:1189` |
| `POST` | `/api/v1/user/devices/unbind-push` | Bearer Token；通常要求已绑定手机号 | `userHandler.DeletePushToken` | `backend/cmd/server/main.go:1187` |
| `DELETE` | `/api/v1/user/e2ee/device-key` | Bearer Token；通常要求已绑定手机号 | `userHandler.RevokeCurrentDeviceE2EEKey` | `backend/cmd/server/main.go:1149` |
| `PUT` | `/api/v1/user/e2ee/device-key` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdateCurrentDeviceE2EEKey` | `backend/cmd/server/main.go:1148` |
| `GET` | `/api/v1/user/e2ee/recovery/requests` | Bearer Token；通常要求已绑定手机号 | `userHandler.ListE2EERecoveryRequests` | `backend/cmd/server/main.go:1150` |
| `POST` | `/api/v1/user/e2ee/recovery/requests` | Bearer Token；通常要求已绑定手机号 | `userHandler.CreateE2EERecoveryRequest` | `backend/cmd/server/main.go:1151` |
| `DELETE` | `/api/v1/user/e2ee/recovery/requests/:id` | Bearer Token；通常要求已绑定手机号 | `userHandler.CancelE2EERecoveryRequest` | `backend/cmd/server/main.go:1154` |
| `POST` | `/api/v1/user/e2ee/recovery/requests/:id/approve` | Bearer Token；通常要求已绑定手机号 | `userHandler.ApproveE2EERecoveryRequest` | `backend/cmd/server/main.go:1152` |
| `POST` | `/api/v1/user/e2ee/recovery/requests/:id/consume` | Bearer Token；通常要求已绑定手机号 | `userHandler.ConsumeE2EERecoveryRequest` | `backend/cmd/server/main.go:1153` |
| `GET` | `/api/v1/user/emoji-store` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetEmojiStore` | `backend/cmd/server/main.go:1173` |
| `PUT` | `/api/v1/user/emoji-store` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdateEmojiStore` | `backend/cmd/server/main.go:1174` |
| `GET` | `/api/v1/user/emoji-store/catalog` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetEmojiStoreCatalog` | `backend/cmd/server/main.go:1172` |
| `GET` | `/api/v1/user/me` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetMe` | `backend/cmd/server/main.go:1145` |
| `PUT` | `/api/v1/user/me` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdateMe` | `backend/cmd/server/main.go:1147` |
| `GET` | `/api/v1/user/nearby` | Bearer Token；通常要求已绑定手机号 | `userHandler.SearchNearbyUsers` | `backend/cmd/server/main.go:1164` |
| `PUT` | `/api/v1/user/nearby-location` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdateNearbyLocation` | `backend/cmd/server/main.go:1165` |
| `POST` | `/api/v1/user/password/change-by-code` | Bearer Token；通常要求已绑定手机号 | `userHandler.ChangePasswordByCode` | `backend/cmd/server/main.go:1159` |
| `POST` | `/api/v1/user/password/send-change-code` | Bearer Token；通常要求已绑定手机号 | `middleware.WalletRateLimit` | `backend/cmd/server/main.go:1158` |
| `POST` | `/api/v1/user/phone/bind` | Bearer Token；通常要求已绑定手机号 | `handlers.GlobalFeatureGuard` | `backend/cmd/server/main.go:1157` |
| `POST` | `/api/v1/user/phone/send-bind-code` | Bearer Token；通常要求已绑定手机号 | `handlers.GlobalFeatureGuard` | `backend/cmd/server/main.go:1156` |
| `GET` | `/api/v1/user/privacy` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetPrivacySettings` | `backend/cmd/server/main.go:1166` |
| `PUT` | `/api/v1/user/privacy` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdatePrivacySettings` | `backend/cmd/server/main.go:1167` |
| `GET` | `/api/v1/user/push-settings` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetPushSettings` | `backend/cmd/server/main.go:1195` |
| `PUT` | `/api/v1/user/push-settings` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdatePushSettings` | `backend/cmd/server/main.go:1194` |
| `DELETE` | `/api/v1/user/push-token` | Bearer Token；通常要求已绑定手机号 | `userHandler.DeletePushToken` | `backend/cmd/server/main.go:1193` |
| `POST` | `/api/v1/user/push-token` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdatePushToken` | `backend/cmd/server/main.go:1191` |
| `POST` | `/api/v1/user/push-token/unbind` | Bearer Token；通常要求已绑定手机号 | `userHandler.DeletePushToken` | `backend/cmd/server/main.go:1192` |
| `GET` | `/api/v1/user/search` | Bearer Token；通常要求已绑定手机号 | `userHandler.SearchUsers` | `backend/cmd/server/main.go:1161` |
| `GET` | `/api/v1/user/search-all` | Bearer Token；通常要求已绑定手机号 | `userHandler.SearchAll` | `backend/cmd/server/main.go:1162` |
| `GET` | `/api/v1/user/sessions` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetSessions` | `backend/cmd/server/main.go:1181` |
| `DELETE` | `/api/v1/user/sessions/:session_id` | Bearer Token；通常要求已绑定手机号 | `userHandler.TerminateSession` | `backend/cmd/server/main.go:1183` |
| `POST` | `/api/v1/user/sessions/terminate-others` | Bearer Token；通常要求已绑定手机号 | `userHandler.TerminateOtherSessions` | `backend/cmd/server/main.go:1182` |
| `POST` | `/api/v1/user/two-step` | Bearer Token；通常要求已绑定手机号 | `userHandler.UpdateTwoStep` | `backend/cmd/server/main.go:1168` |
| `POST` | `/api/v1/user/two-step/disable` | Bearer Token；通常要求已绑定手机号 | `userHandler.DisableTwoStep` | `backend/cmd/server/main.go:1170` |
| `POST` | `/api/v1/user/two-step/enable` | Bearer Token；通常要求已绑定手机号 | `userHandler.EnableTwoStep` | `backend/cmd/server/main.go:1169` |
| `GET` | `/api/v1/user/web-push/config` | Bearer Token；通常要求已绑定手机号 | `userHandler.GetWebPushConfig` | `backend/cmd/server/main.go:1196` |
| `GET` | `/api/v1/vip/check-create` | Bearer Token；通常要求已绑定手机号 | `vipHandler.CheckCreatePermission` | `backend/cmd/server/main.go:1500` |
| `GET` | `/api/v1/vip/orders` | Bearer Token；通常要求已绑定手机号 | `vipHandler.ListMyOrders` | `backend/cmd/server/main.go:1502` |
| `GET` | `/api/v1/vip/plans` | Bearer Token；通常要求已绑定手机号 | `vipHandler.ListPlans` | `backend/cmd/server/main.go:1498` |
| `POST` | `/api/v1/vip/purchase` | Bearer Token；通常要求已绑定手机号 | `vipHandler.Purchase` | `backend/cmd/server/main.go:1501` |
| `GET` | `/api/v1/vip/status` | Bearer Token；通常要求已绑定手机号 | `vipHandler.GetStatus` | `backend/cmd/server/main.go:1499` |
| `GET` | `/api/v1/wallet` | Bearer Token；通常要求已绑定手机号 | `walletHandler.GetWallet` | `backend/cmd/server/main.go:1470` |
| `POST` | `/api/v1/wallet/online-pay/create` | Bearer Token；通常要求已绑定手机号 | `handlers.IOSComplianceFeatureGuard` | `backend/cmd/server/main.go:1468` |
| `GET` | `/api/v1/wallet/online-pay/options` | Bearer Token；通常要求已绑定手机号 | `handlers.IOSComplianceFeatureGuard` | `backend/cmd/server/main.go:1467` |
| `GET` | `/api/v1/wallet/online-pay/order/:out_trade_no` | Bearer Token；通常要求已绑定手机号 | `handlers.IOSComplianceFeatureGuard` | `backend/cmd/server/main.go:1469` |
| `POST` | `/api/v1/wallet/pay-password` | Bearer Token；通常要求已绑定手机号 | `walletHandler.SetPayPassword` | `backend/cmd/server/main.go:1475` |
| `POST` | `/api/v1/wallet/recharge` | Bearer Token；通常要求已绑定手机号 | `handlers.IOSComplianceFeatureGuard` | `backend/cmd/server/main.go:1478` |
| `GET` | `/api/v1/wallet/recharge-methods` | Bearer Token；通常要求已绑定手机号 | `handlers.IOSComplianceFeatureGuard` | `backend/cmd/server/main.go:1472` |
| `POST` | `/api/v1/wallet/recharge-order` | Bearer Token；通常要求已绑定手机号 | `handlers.IOSComplianceFeatureGuard` | `backend/cmd/server/main.go:1473` |
| `GET` | `/api/v1/wallet/recharge-orders` | Bearer Token；通常要求已绑定手机号 | `handlers.IOSComplianceFeatureGuard` | `backend/cmd/server/main.go:1474` |
| `GET` | `/api/v1/wallet/red-packet/:id` | Bearer Token；通常要求已绑定手机号 | `walletHandler.GetRedPacket` | `backend/cmd/server/main.go:1482` |
| `POST` | `/api/v1/wallet/red-packet/:id/claim` | Bearer Token；通常要求已绑定手机号 | `wrl10` | `backend/cmd/server/main.go:1481` |
| `POST` | `/api/v1/wallet/red-packet/send` | Bearer Token；通常要求已绑定手机号 | `wrl5` | `backend/cmd/server/main.go:1480` |
| `GET` | `/api/v1/wallet/settings` | Bearer Token；通常要求已绑定手机号 | `walletHandler.GetWalletSettings` | `backend/cmd/server/main.go:1471` |
| `GET` | `/api/v1/wallet/transactions` | Bearer Token；通常要求已绑定手机号 | `walletHandler.GetTransactions` | `backend/cmd/server/main.go:1477` |
| `GET` | `/api/v1/wallet/transfer/:id` | Bearer Token；通常要求已绑定手机号 | `walletHandler.GetTransfer` | `backend/cmd/server/main.go:1487` |
| `POST` | `/api/v1/wallet/transfer/:id/accept` | Bearer Token；通常要求已绑定手机号 | `wrl5` | `backend/cmd/server/main.go:1485` |
| `POST` | `/api/v1/wallet/transfer/:id/reject` | Bearer Token；通常要求已绑定手机号 | `wrl5` | `backend/cmd/server/main.go:1486` |
| `POST` | `/api/v1/wallet/transfer/send` | Bearer Token；通常要求已绑定手机号 | `wrl5` | `backend/cmd/server/main.go:1484` |
| `POST` | `/api/v1/wallet/verify-password` | Bearer Token；通常要求已绑定手机号 | `walletHandler.VerifyPayPassword` | `backend/cmd/server/main.go:1476` |
| `POST` | `/api/v1/wallet/withdraw` | Bearer Token；通常要求已绑定手机号 | `wrl5` | `backend/cmd/server/main.go:1490` |
| `GET` | `/api/v1/wallet/withdraw/methods` | Bearer Token；通常要求已绑定手机号 | `walletHandler.GetWithdrawMethods` | `backend/cmd/server/main.go:1489` |
| `GET` | `/api/v1/ws` | Bearer Token（该路由显式鉴权） | `middleware.Auth` | `backend/cmd/server/main.go:1507` |
| `Any` | `/bot-api/v1/*path` | 公开 | `botAPIHandler.Handle` | `backend/cmd/server/main.go:1047` |
| `GET` | `/delivery/handbook` | HTTPS + 文档独立认证 + 协议确认 | `handbookAuth` | `backend/cmd/server/main.go:1030` |
| `POST` | `/delivery/handbook/accept` | HTTPS + 文档独立认证 + 协议确认 | `handbookAuth` | `backend/cmd/server/main.go:1031` |
| `GET` | `/favicon.ico` | 公开 | `func` | `backend/cmd/server/main.go:1019` |
| `GET` | `/health` | 公开 | `func` | `backend/cmd/server/main.go:1036` |
| `POST` | `/internal/alerts/webhook` | 内部监控鉴权 | `observabilityManager.AlertWebhook` | `backend/cmd/server/main.go:224` |
| `GET` | `/ready` | 公开 | `readinessHandler` | `backend/cmd/server/main.go:1045` |
| `GET` | `/robots.txt` | 公开 | `func` | `backend/cmd/server/main.go:1024` |
| `GET` | `/ws/stats` | Bearer Token（该路由显式鉴权） | `middleware.AdminAuth` | `backend/cmd/server/main.go:1049` |

> 路由目录覆盖主服务中 `main.go` 的 Gin 字面量注册，以及当前由容量模块辅助函数注册的接口。新增路由辅助函数时必须扩展生成器或在交付前补充对应解析规则。

## 5. 上传与分片上传

1. 小文件使用 `/api/v1/upload/image|video|avatar|voice|file` 的 multipart 字段提交，成功后返回媒体标识或访问地址。
2. 大文件先 `POST /api/v1/media/uploads/init` 创建上传会话，再调用 `POST /api/v1/media/uploads/:id/parts/presign` 获取分片签名；客户端把每个分片上传到签名地址并保存 ETag。
3. 所有分片完成后 `POST /api/v1/media/uploads/:id/complete` 提交分片序号和 ETag；取消使用 `POST /api/v1/media/uploads/:id/abort`。状态查询为 `GET /api/v1/media/uploads/:id`，访问地址为 `GET /api/v1/media/:id/access-url`。
4. 上传地址、签名和媒体下载权限均为短期凭据，不得写入日志或交付文档。

## 6. WebSocket

握手地址为 `wss://<customer-api-host>/api/v1/ws`。连接后发送 `subscribe` 并携带 `{"chat_ids":[...]}`；客户端应处理 `pong`、`error`，按 `seq` 保存最后序号，断线后通过消息同步接口补拉，不能把 WebSocket 当作消息持久化来源。

客户端上行消息：`ping`、`subscribe`、`unsubscribe`、`message`、`typing`、`read`、`online`。服务端事件名称以消息 `type` 字段为准，常见事件如下：

| 事件 | 典型用途 |
| --- | --- |
| `new_message`、`message_edited`、`message_revoked` | 新消息及状态变化 |
| `read_sync`、`read`、`delivered` | 已读/送达回执 |
| `new_chat`、`chat_update`、`chat_left`、`chat_dissolved` | 会话和群组变更 |
| `member_role_changed`、`member_mute_status_changed`、`chat_permissions_updated` | 成员权限变更 |
| `typing`、`user_status`、`profile_updated` | 在线和输入状态 |
| `incoming_call`、`call_accepted`、`call_rejected`、`call_cancelled`、`call_ended`、`call_connected`、`call_media_changed` | 通话信令 |
| `meeting_invite`、`meeting_started`、`meeting_member_joined`、`meeting_member_left`、`meeting_ended`、`meeting_host_changed` | 会议事件 |
| `moment_like`、`moment_comment`、`moment_reply` | 动态互动 |
| `message_favorite_changed`、`chat_announcement`、`discover_items_updated` | 收藏、公告和发现页更新 |

事件外层结构为 `{"type":"...","seq":123,"data":{...}}`；`data` 的字段以对应 Go handler/service 的结构体和客户端模型为准。未知事件必须忽略并记录可脱敏的类型名。

## 7. Bot 接口

Bot 平台的机器接口另有 OpenAPI 文件：`docs/bot-api-p1.openapi.yaml`；接入说明见 `docs/Bot-API-P1开发者接入指南.md`。该文件与本目录的用户/管理 API 是两个鉴权域，不要混用 Token。

## 8. 同步与验收

```bash
python3 scripts/generate-api-reference.py
python3 scripts/generate-api-reference.py --check
```

`--check` 会在路由注册变化后返回非零状态，交付前应重新生成并把文档纳入 `MANIFEST-SHA256.txt`。接口联调仍需记录目标 App/后端版本、REST/WS 地址、迁移状态和功能开关，并完成最终用户可见结果验收。

<!-- api-reference:generated -->

# 客户域名替换与 Docker 一键交付小白教程

这份教程面向第一次部署的客户。照着顺序做即可完成：准备域名、生成线上 Docker 包、上传服务器、宝塔配置 HTTPS、启动服务和验收。

## 先看懂整体关系

浏览器只访问 80/443，数据库和 Docker 容器端口只在服务器本机监听。下面是一个完整示例，客户需要把 `example.com` 换成自己的域名。

| 用途 | 客户域名 | 服务器本机端口 | 是否开放公网 |
| --- | --- | ---: | --- |
| API、图片和 WebSocket | `api.example.com` | `127.0.0.1:18080` | 否 |
| Flutter Web 前端 | `web.example.com` | `127.0.0.1:18083` | 否 |
| 运营管理后台 | `admin.example.com` | `127.0.0.1:18084` | 否 |
| 客服后台 | `kf.example.com` | `127.0.0.1:18085` | 否 |
| MySQL（容器内部使用） | 无 | `127.0.0.1:13306` | 否 |
| MongoDB（容器内部使用） | 无 | `127.0.0.1:17017` | 否 |
| Redis（容器内部使用） | 无 | `127.0.0.1:16379` | 否 |

访问关系是：`https://admin.example.com` -> 宝塔 Nginx -> `127.0.0.1:18084`；API、Web、客服后台同理。客户不需要记住这些内部端口，外部统一使用 HTTPS 443。

## 一、客户需要准备什么

1. 一个已经实名认证并可修改 DNS 的域名，例如 `example.com`。
2. 一台 Linux 服务器（建议 Ubuntu 22.04/24.04 或 Debian 12），建议至少 4 核 CPU、8 GB 内存、80 GB SSD。
3. 服务器公网 IPv4 地址和 root 或 sudo 权限。
4. 宝塔面板（可选）。不用宝塔时，也可以只安装 Docker 和 Nginx。
5. 生产数据库、对象存储、短信、推送、支付等第三方账号。密码和密钥单独传递，不写进源码包。

第一次部署建议只准备一台全新服务器，先完成备份策略，再做正式域名切换。不要把测试数据库接到生产服务。

## 二、先配置 DNS（域名解析）

在域名服务商的 DNS 页面新增 4 条 A 记录：

| 主机记录 | 类型 | 记录值 |
| --- | --- | --- |
| `api` | A | 服务器公网 IP |
| `web` | A | 服务器公网 IP |
| `admin` | A | 服务器公网 IP |
| `kf` | A | 服务器公网 IP |

保存后等待解析生效。在自己的电脑检查：

```bash
nslookup api.example.com
nslookup web.example.com
nslookup admin.example.com
nslookup kf.example.com
```

四个域名都必须返回同一台服务器 IP。若使用 Cloudflare，代理云朵可以先关闭（DNS only），证书和反代确认无误后再开启；代理模式必须使用 Full 或 Full (strict)，不能使用 Flexible。

## 三、交付方如何生成“线上 Docker 包”

线上包不是客户在服务器上临时编译出来的，而是交付方在一台已安装 Node、Flutter、Go 和 PowerShell 的构建机上生成。构建机负责编译，客户服务器只运行已经编译好的文件，因此低配置宝塔服务器也可以部署。

### 1. 交付方填写客户参数

在源码根目录执行（PowerShell 7）：

```powershell
pwsh -File scripts/build-online-prebuilt-package.ps1 `
  -CustomerName "customer" `
  -PackageName "customer-online" `
  -ApiDomain "api.example.com" `
  -AdminDomain "admin.example.com" `
  -H5Domain "web.example.com" `
  -KfDomain "kf.example.com" `
  -H5Port "18083" `
  -AdminPort "18084" `
  -KfPort "18085" `
  -Scheme "https" `
  -InstallDir "/www/wwwroot/customer/customerim-online-server" `
  -DefaultAdminPassword "请填写一次性强密码"
```

不要把真实密码提交到 Git 或公开聊天。更稳妥的做法是先填一次性密码，客户首次登录后立即修改。

### 2. 这个命令会做什么

脚本会依次完成：

1. 构建 `admin/dist` 运营后台。
2. 构建 `admin-kf/dist` 客服后台。
3. 使用客户 API、WebSocket 和 Web 域名构建 Flutter Web 到 `build/web`。
4. 运行 Go 测试并生成 Linux `amd64`、`arm64` 两种后端二进制。
5. 复制 Docker、Nginx、宝塔部署、运维和日志轮转脚本。
6. 把客户域名、协议、端口和安装目录写入包内启动脚本。
7. 生成 ZIP、`tar.gz`、包内 `MANIFEST-SHA256.txt` 和压缩包 SHA-256 文件。

如果构建机缺少 Node、Flutter、Go 或 `pwsh`，脚本会失败，这不是客户服务器故障。应在构建机补齐工具版本后重新生成。

### 3. 生成后先检查包

查看 `artifacts/` 下最新目录，确认至少有：

```text
admin-dist/                 运营后台静态文件
kf-dist/                    客服后台静态文件
web-dist/                   Flutter Web 静态文件
backend/server-linux-amd64  Linux x86_64 后端
backend/server-linux-arm64  Linux ARM64 后端
scripts/baota_docker_deploy_prebuilt.sh
deploy-online-prebuilt.sh
README.md
MANIFEST-SHA256.txt
```

交付前执行：

```powershell
pwsh -File scripts/verify-source-delivery.ps1 -Root <源码交付暂存目录>
Get-FileHash artifacts/customer-online-*.tar.gz -Algorithm SHA256
```

线上预编译包和完整源码包是两种交付物。预编译包用于快速上线，完整源码包用于后续维护；两者的版本、配置和 SHA-256 必须记录在交付验收单中。

## 四、客户把线上包放到服务器

### 方案 A：宝塔文件管理器

1. 登录宝塔，打开“文件”。
2. 进入 `/www/wwwroot/`，上传 `customer-online-时间戳.tar.gz`。
3. 右键解压，目录建议命名为 `/www/wwwroot/customer-package`。
4. 打开终端，进入目录并赋予脚本执行权限：

```bash
cd /www/wwwroot/customer-package
chmod +x deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
```

由 `build-online-prebuilt-package.ps1` 生成的预编译包还会带一个 `deploy-customer.sh` 包装脚本；如果文件存在，给它也加执行权限，优先使用它，它会自动带入交付方生成包时写入的域名和端口：

```bash
chmod +x deploy-customer.sh
sudo bash deploy-customer.sh
```

如果客户临时换了域名，或包内没有这个包装脚本，再使用下面的显式参数命令。

### 方案 B：命令行上传

在客户电脑执行（把服务器 IP 和用户名换成客户自己的）：

```bash
scp customer-online-时间戳.tar.gz root@服务器IP:/www/wwwroot/
ssh root@服务器IP
mkdir -p /www/wwwroot/customer-package
tar -xzf /www/wwwroot/customer-online-时间戳.tar.gz -C /www/wwwroot/customer-package
cd /www/wwwroot/customer-package
chmod +x deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
```

解压后可先校验文件清单：

```bash
sha256sum -c MANIFEST-SHA256.txt
```

## 五、Docker 一键部署（推荐）

### 1. 先安装 Docker

宝塔用户：进入“软件商店”，安装 Docker 管理器，确认 `docker --version` 和 `docker compose version` 都能输出版本。

纯 Linux 用户：安装 Docker Engine 和 Compose v2，确认 Docker 服务已启动：

```bash
systemctl enable --now docker
docker version
docker compose version
```

### 2. 一条命令启动

在解压目录执行：

```bash
sudo env \
  ADMIN_DOMAIN=admin.example.com \
  API_DOMAIN=api.example.com \
  H5_DOMAIN=web.example.com \
  KF_DOMAIN=kf.example.com \
  SCHEME=https \
  ADMIN_PASSWORD='一次性强密码' \
  WRITE_NGINX=1 \
  bash deploy-online-prebuilt.sh
```

上面是环境变量写法。也可以直接调用底层脚本，参数更明确：

```bash
sudo bash scripts/baota_docker_deploy_prebuilt.sh \
  --admin-domain admin.example.com \
  --api-domain api.example.com \
  --h5-domain web.example.com \
  --kf-domain kf.example.com \
  --scheme https \
  --admin-port 18084 \
  --api-port 18080 \
  --h5-port 18083 \
  --kf-port 18085 \
  --mysql-port 13306 \
  --mongo-port 17017 \
  --redis-port 16379 \
  --write-nginx \
  --admin-password '一次性强密码' \
  -y
```

脚本会检查 Docker，选择对应 CPU 的后端二进制，生成本地 `.env.bt`，启动 API、Web、管理后台、客服后台、MySQL、MongoDB 和 Redis，并执行健康检查。服务器不会运行 Go、Node 或 Flutter 编译。

脚本默认把数据库端口绑定到 `127.0.0.1`。除非确实有跨服务器数据库需求，不要改成 `0.0.0.0`。

### 3. 查看部署状态

```bash
cd /www/wwwroot/customer/customerim-online-server
docker compose --env-file .env.bt -f compose.bt.yaml ps
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=100 api
curl -fsS http://127.0.0.1:18080/health
curl -I http://127.0.0.1:18083
curl -I http://127.0.0.1:18084
curl -I http://127.0.0.1:18085
```

看到容器 `Up` 只代表进程存活；必须继续用浏览器登录、发消息、上传文件等真实流程验收。

## 六、宝塔反向代理和 HTTPS

### 1. 用一键脚本写入反代

首次部署可以传 `--write-nginx`。脚本只新增反向代理片段，不应覆盖宝塔已有证书目录。执行后到宝塔“网站”中检查 4 个站点配置，再申请证书。

### 2. 手工配置（不会自动改 Nginx 时）

宝塔“网站 -> 添加站点”，分别添加 `api.example.com`、`web.example.com`、`admin.example.com`、`kf.example.com`。每个站点的“反向代理”目标分别是：

```text
api.example.com   http://127.0.0.1:18080
web.example.com   http://127.0.0.1:18083
admin.example.com http://127.0.0.1:18084
kf.example.com    http://127.0.0.1:18085
```

API 站点必须保留 WebSocket 头：

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-Proto $scheme;
```

在每个站点申请 Let's Encrypt 或客户自己的证书，开启“强制 HTTPS”。证书申请前 DNS 必须已经指向服务器，80 端口不能被安全组拦截。

## 七、安全组和端口怎么填

公网安全组只放行：

```text
22/tcp   SSH（最好限制为办公 IP）
80/tcp   HTTP，用于跳转 HTTPS 和证书验证
443/tcp  HTTPS
```

不要在云厂商安全组放行 `3306、27017、6379、13306、17017、16379、18080、18083、18084、18085`。这些是服务器内部端口。

部署前若想临时本机调试，可以在服务器执行 `curl 127.0.0.1:端口`，不要为了远程调试把端口永久暴露到公网。

## 八、客户换域名后必须重新生成什么

只改宝塔 Nginx 不够。域名会写入前端构建产物、API CORS、WebSocket 地址和移动端配置，换域名后按下面表格重新做：

| 产物 | 是否重新构建 | 需要替换的内容 |
| --- | --- | --- |
| Flutter Web | 是 | `CUSTOMER_IM_SERVER_URL`、`CUSTOMER_IM_WS_URL`、公开 Web 地址 |
| 运营后台 | 是 | `VITE_API_URL`、`VITE_API_BASE_URL` |
| 客服后台 | 是 | `VITE_API_BASE_URL` |
| Android APK/AAB | 是 | API/WS 地址、签名和推送配置 |
| iOS/macOS | 是 | API/WS 地址、Bundle 配置、推送配置 |
| Windows | 是 | API/WS 地址、安装包元数据 |
| Go API | 通常不用重新编译 | 修改生产环境变量中的 Origin、数据库和存储配置 |
| 宝塔 Nginx | 是 | 4 个域名的站点和证书 |

保留模块名、包名、Bundle ID、Go module、MethodChannel、通知频道和内部 `CUSTOMER_IM_*` 环境变量名称；只替换它们的值。随意改名容易导致编译或运行时报错。

重新构建线上包时，只需再次执行第三节的 `build-online-prebuilt-package.ps1`，并传入新域名。旧包不要覆盖，保留时间戳用于回滚。

## 九、前端单独打包示例

### Flutter Web

```bash
flutter pub get
flutter build web --release --no-web-resources-cdn \
  --dart-define=CUSTOMER_IM_SERVER_URL=https://api.example.com \
  --dart-define=CUSTOMER_IM_WS_URL=wss://api.example.com/api/v1/ws \
  --dart-define=CUSTOMER_IM_PUBLIC_H5_URL=https://web.example.com \
  --dart-define=CUSTOMER_IM_BOOTSTRAP_URL=https://api.example.com/api/v1/client/bootstrap
```

把 `build/web` 上传到客户的静态站点或重新生成预编译包。

### 运营后台和客服后台

```bash
cd admin
pnpm install --frozen-lockfile
VITE_API_URL=/api/v1 VITE_API_BASE_URL=/api/v1 pnpm build

cd ../admin-kf
pnpm install --frozen-lockfile
VITE_API_BASE_URL=/api/v1 VITE_USE_MOCK=false pnpm build
```

后台使用相对路径 `/api/v1` 时，浏览器会访问当前后台域名；若后台和 API 是不同域名，必须确认 Nginx CORS 和 HTTPS 配置正确。

## 十、上线验收（纯小白版）

按顺序打开：

1. `https://web.example.com` 能显示登录页，浏览器地址栏没有证书警告。
2. `https://admin.example.com` 能打开并登录运营后台。
3. `https://kf.example.com` 能打开客服后台。
4. `https://api.example.com/health` 返回健康结果。
5. 用两台真实手机注册不同账号，互发文本、图片和文件，确认消息能收到。
6. 退出并重新登录，确认 Token 刷新和 WebSocket 重连正常。
7. 检查上传文件能访问，数据库、Redis 和日志目录有持续写入。

HTTP 200、接口返回 `code=0`、Docker `Up` 或数据库出现一行记录，都不能单独作为“上线成功”。跨用户功能必须用两台真实设备完成最终可见结果验证，并记录 App ID/版本、REST/WS 地址、后端版本、迁移版本和功能开关。

## 十一、常见故障

| 现象 | 先检查 | 处理 |
| --- | --- | --- |
| 域名打不开 | `nslookup`、安全组 80/443、宝塔站点 | DNS 未生效就等待；确认 A 记录和服务器 IP |
| 502 Bad Gateway | `docker compose --env-file .env.bt -f compose.bt.yaml ps`、本机端口 curl | 容器未启动或反代端口写错，查看对应服务日志 |
| 后台白屏 | 浏览器开发者工具 Network | 检查 `/api/v1`、HTTPS 混合内容和 CORS |
| 消息发出后收不到 | WebSocket 头、`wss://` 地址、两台设备 | API 反代必须配置 Upgrade/Connection |
| 上传失败 | 对象存储变量、磁盘权限、反代 body 大小 | 先用本地存储验收，再配置 OSS/CDN |
| Docker 拉取慢 | Docker 镜像源和磁盘空间 | 选择正确镜像源，确认磁盘剩余空间 |
| 端口被占用 | `ss -lntp | grep 1808` | 修改内部端口并同步脚本、Nginx，不改公网 80/443 |
| 重启后数据消失 | `docker volume ls`、安装目录 | 不要删除 volume；确认 compose 使用持久化卷 |

查看完整日志：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=200 api
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=200 web
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=200 admin
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=200 kf
```

不要执行 `docker compose down -v`，它会删除数据库卷，可能造成不可恢复的数据丢失。升级前先备份 MySQL、MongoDB、Redis 配置和上传目录。

## 十二、升级与回滚

升级时上传新时间戳包到新目录，先执行健康检查，再切换宝塔反代到新目录的端口。旧目录和旧包至少保留 7 天。

```bash
docker compose --env-file .env.bt -f compose.bt.yaml pull
docker compose --env-file .env.bt -f compose.bt.yaml up -d
docker compose --env-file .env.bt -f compose.bt.yaml ps
```

若新版本异常，停止新目录服务，把 Nginx 反代端口改回旧目录对应端口，然后恢复数据库备份。回滚完成后仍需用两台设备做登录和消息冒烟测试。

## 十三、最终交付清单

- [ ] 四个域名 DNS 已解析到客户服务器。
- [ ] 线上包 ZIP/tar.gz 和 SHA-256 已交付并校验。
- [ ] Docker、Compose、宝塔和 HTTPS 证书已配置。
- [ ] 公网只开放 22/80/443，内部端口未暴露。
- [ ] API、Web、运营后台、客服后台均可访问。
- [ ] 数据库、Redis、上传目录已做备份方案。
- [ ] 两台真实设备完成注册、登录、聊天、上传和重连验收。
- [ ] 客户已修改一次性管理员密码和所有默认密钥。
- [ ] 记录了版本、域名、端口、迁移状态、功能开关和验收证据。

遇到问题时，提交脱敏后的 `docker compose ps`、相关服务最近 100 行日志、浏览器错误和复现步骤；不要提交密码、Token、私钥或完整用户数据。

## 十四、后端托管教程入口

正式部署后，优先让客户访问：

```text
https://api.example.com/delivery/handbook
```

第一次访问只显示本协议。客户勾选并提交后，后端会把协议版本、内容摘要、时间、IP、浏览器信息和匿名浏览器标识写入 `admin_agreement_acceptances`，随后才返回完整教程。未确认时不会由该入口返回教程正文。

后台管理员和客服管理员登录后也必须分别访问服务端协议接口并确认；协议版本更新后，旧确认记录自动失效。离线 HTML 只适合没有部署 API 时的本地备份，不能替代客户签署的正式授权与合规文件。

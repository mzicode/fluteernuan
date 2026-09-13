# Customer IM 5.0.0 前端原始碼分離說明

本包依來源專案 `docs/原始碼目錄說明.md` 與 `docs/客戶原始碼交付使用指南.md` 重新整理，並保留原始根目錄相對路徑。

## 前端範圍

### Flutter 多端客戶端

- `lib/`：共用業務原始碼，入口為 `lib/main.dart`
- `assets/`：隨客戶端建置的圖片、動畫、貼圖、音效等資源
- `android/`、`ios/`：行動端平台工程
- `windows/`、`macos/`：桌面端平台工程
- `web/`：Flutter Web 入口與 PWA 設定
- `pubspec.yaml`、`pubspec.lock`：Flutter 依賴與資源設定
- `third_party/`：`pubspec.yaml` 以相對路徑引用的本機套件
- `integration_test/`、`test/`、`test_driver/`：客戶端測試

### Web 管理介面與網站

- `admin/`：Vue 3 營運管理後台
- `admin-kf/`：Vue 3 官方客服後台
- `official-site/`：HTML/CSS/JavaScript 靜態官網、支援與隱私頁面

### 隨附文件

- `docs/`：原始交付的架構、設定、API、打包與驗收文件
- `README.md`、`SOURCE_DELIVERY.md`、`SOURCE_DELIVERY_README.md`

## H5 說明

這個版本沒有獨立的 `h5/` Vue 專案。文件明確指出，本快照中的 Web/H5 客戶端是由 `lib/` 與 `web/` 建置出的 Flutter Web，不應另找或執行 `cd h5`。

## 未包含內容

- `backend/`：Go 後端
- `database/`：資料庫結構與遷移
- `docker/`、`compose.yaml`：整套系統部署
- `uploads/`：內建或執行期服務端資源
- `scripts/`：同時混有前端、後端、部署與驗收腳本，沒有列入純前端原始碼包

## 最基本啟動命令

Flutter Web：

```powershell
flutter pub get
flutter run -d chrome --web-port 5175
```

營運管理後台：

```powershell
cd admin
pnpm install
pnpm dev
```

客服管理後台：

```powershell
cd admin-kf
pnpm install
pnpm dev
```

前端需要連接另行部署的後端 API 與 WebSocket；本包不包含伺服器程式。

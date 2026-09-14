# Windows 远程打包成功经验

记录 2026-09-14 在 GitHub Actions 上第一次打出可分享 Windows 安装包和便携版的做法。没有本机 Windows 时，按本文用远端 CI，不要在 macOS 上交叉编译。

## 1. 这次已经成功

| 项 | 值 |
| --- | --- |
| 仓库 | [mzicode/fluteernuan](https://github.com/mzicode/fluteernuan) |
| 首次成功 | [Windows Release #10](https://github.com/mzicode/fluteernuan/actions/runs/34808078679)，提交 `409546c` |
| 公开 Release | [windows-build-10](https://github.com/mzicode/fluteernuan/releases/tag/windows-build-10) |
| 安装包 | `NuanLin-Windows-Setup-1.0.1.exe`（约 71.5 MB） |
| 便携版 | `NuanLin-Windows-Release.zip`（约 95 MB，解压后运行 `customer.exe`） |
| Runner | `windows-2022`，不要用当时的 `windows-latest` |
| Flutter | `3.44.1` |
| 默认 API | `https://web.cybndo.com` |
| 默认 WS | `wss://web.cybndo.com/api/v1/ws` |

#10 从 Checkout 到 Publish GitHub Release 全部 success。安装包和便携 zip 都已经上传。

发给别人用 Release 页面，不要用 Actions Artifact。Artifact 大约 90 天后过期，且未登录通常下不了；公开 Release 的 `releases/download/...` 链接不需要 GitHub 账号。

## 2. 怎么分享

发这一页：

https://github.com/mzicode/fluteernuan/releases/tag/windows-build-10

普通用户发安装包：

https://github.com/mzicode/fluteernuan/releases/download/windows-build-10/NuanLin-Windows-Setup-1.0.1.exe

不想安装、解压即用发便携版：

https://github.com/mzicode/fluteernuan/releases/download/windows-build-10/NuanLin-Windows-Release.zip

解压后运行 `customer.exe`。Windows 可能提示「未知发布者」，选「仍要运行」。安装包没有代码签名。

仓库必须保持 Public，否则外人打不开上述链接。换 API 域名后必须重新构建，旧包里的地址改不了。

## 3. 再打一包

1. 只提交 Windows 打包相关文件。本地聊天/UI 改动不要混进这次提交。
2. 推到 `main`，或在 Actions 里手动跑 `Windows Release`。
3. 成功后会出现新的 `windows-build-<run_number>` Release。
4. 把新的 Setup.exe 或 zip 链接发出去。

关键文件：

| 路径 | 作用 |
| --- | --- |
| `.github/workflows/windows-release.yml` | CI：Flutter 构建、Inno、zip、Release |
| `tool/windows/prepare_windows_native_sdks.ps1` | 预下载 Agora / Firebase，修补 `jni` CMake |
| `tool/windows/build_windows_installer.ps1` | 生成 Inno 包装脚本并调用 ISCC |
| `windows/installer/customer_setup.iss` | 安装脚本，路径用正斜杠 |
| `windows/CMakeLists.txt` | 关闭 `/WX`，打开异常和 UTF-8，静音 STL1011 |

仓库变量可覆盖编译期地址：`CUSTOMER_IM_SERVER_URL`、`CUSTOMER_IM_WS_URL`、`CUSTOMER_IM_BOOTSTRAP_URL`、`CUSTOMER_IM_PUBLIC_H5_URL`。未设置时用上面的默认 `web.cybndo.com`。只接受 `https://` / `wss://`，拒绝 localhost。

## 4. 必须保留的约束

这些不是可选优化，拿掉会回到前 9 次失败。

1. **Runner 钉死 `windows-2022`。** `windows-latest` 当时是 VS 2026 / MSVC 14.51，`<experimental/coroutine>` 会变成硬错误 STL1011。受影响插件包括 `flutter_local_notifications_windows`、`local_auth_windows`、`audioplayers_windows`、`permission_handler_windows`。CMake 和 `CL` 都要加 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`。
2. **不要把警告当错误，不要关 C++ 异常。** Agora、Firebase、JNI、WebView2 需要 `/EHsc`。同时加 `/utf-8`，并忽略 4100/4244/4267/4996/4458/4819。
3. **先 `flutter pub get`，再跑 native SDK 准备脚本，再 `--no-pub` 构建。** Agora Iris/Native zip 和 Firebase C++ SDK（约 800 MB）不要交给 CMake 在编译中途下载。准备脚本会写 Agora `windows/.plugin_dev`，并设置 `FIREBASE_CPP_SDK_DIR`。
4. **改 pub cache 里的 CMake 必须无 BOM。** Windows PowerShell 5 的 `Set-Content -Encoding UTF8` 会写 UTF-8 BOM，CMake 解析失败。用 `New-Object System.Text.UTF8Encoding $false`。
5. **`jni` 的 WIN32 CMake 用了未定义的 `${TARGET_NAME}`。** 改成 `set_target_properties(jni PROPERTIES)`。PowerShell 替换时必须单引号；双引号会把 `${TARGET_NAME}` 展开成空。
6. **Inno 不要用未加引号的 `/D` 传 Windows 路径。** GitHub runner 在 `D:\a\...` 下。`\a`、`\f`、`\x64` 会被 ISPP 当转义。做法：正斜杠路径写入 `windows/installer/_ci_setup.iss`（已 gitignore），再 `#include "customer_setup.iss"`，并用 ISCC `/O` `/F`。安装脚本里的 `SourceDir`、`OutputDir`、`SetupIconFile` 也用正斜杠。
7. **choco 的 Inno 不一定带 `ChineseSimplified.isl`。** 语言包用 `compiler:Default.isl`。安装界面可以是英文，产品名仍是「暖邻」。
8. **产物文件名只用 ASCII。** `NuanLin-Windows-Setup-<version>`、`NuanLin-Windows-Release.zip`。中文文件名在 Artifact / Release 上容易出问题。
9. **PowerShell here-string 不要写进 workflow YAML。** `"@` 必须顶格，会把 YAML 弄非法。#9 就是这样秒失败，annotation 是 `Invalid workflow file ... line 151`。安装逻辑放在 `tool/windows/build_windows_installer.ps1`。
10. **`customer.exe` 一旦编出来，zip 和 Release 不要绑在 Setup.exe 是否成功上。** Artifact 用 `if: always()`。Release 用 archive 步骤的 `portable=true` 输出，不要用 `hashFiles(...)`——那是 job 开始时就算的。
11. **开启长路径。** `git config --system core.longpaths true`，并写注册表 `LongPathsEnabled=1`。
12. **workflow `permissions.contents: write`。** `softprops/action-gh-release` 需要它才能建 Release。

## 5. 前 9 次分别卡在哪

| 次数 | 失败点 | 原因 |
| --- | ---: | --- |
| 1–4 | Build Windows Release | 插件 symlink、Agora SDK 路径未就绪 |
| 5–6 | Build Windows Release | Agora `DownloadSDK.cmake` 路径、Firebase 在 CMake 里现下 |
| 7 | Build Windows Release | STL1011，`windows-latest` 上的新 MSVC |
| 8 | Build Setup.exe | Flutter 已成功；Inno `/D` 路径转义。当时 zip/Release 还依赖 Setup 成功，所以 exe 没发出去 |
| 9 | 未进 runner | workflow YAML 非法（here-string `"@`） |

#8 已经证明 Flutter Release 能编过。#10 把 Inno 路径和 YAML 拆开后，安装包也过了。

公开仓库匿名拉 Actions 日志经常 403。可用：

- 运行页 HTML 上的 annotation（YAML 错误会直接写行号）
- [nightly.link](https://nightly.link) 下 Artifact，例如 `https://nightly.link/mzicode/fluteernuan/actions/runs/<runId>/nuanlin-windows-release.zip`
- 失败时的 `nuanlin-windows-build-log` Artifact（`windows-build.log` 和 CMake 诊断）

## 6. 构建时间

#10 大约 10 分钟（05:00:50 开始，05:11:20 发布 Release）。超时设 120 分钟，主要是给 Firebase C++ SDK 下载留余量。SDK 准备脚本会复用 `%RUNNER_TEMP%` 里已下的 zip。

## 7. 不要做的事

- 不要在没有 Windows 的机器上本地 `flutter build windows` 当交付物。
- 不要把本地未完成的聊天/UI diff 推进 Windows 打包提交。
- 不要把 `windows/installer/_ci_setup.iss` 和 `dist/` 提交进 git。
- 不要假设换 Nginx 域名后旧 exe 会跟着变。地址是 `--dart-define` 编译进去的。
- 不要用 `Set-Content -Encoding UTF8` 改 CMake。
- 不要在 YAML 的 `run: |` 里写顶格 `"@` 的 here-string。改 YAML 后先本地 `yaml.safe_load` 再推。

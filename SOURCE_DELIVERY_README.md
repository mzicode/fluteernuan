# 客户完整源码交付说明

本包是当前已审核工作区的源码快照，包含：

- Android、iOS、Web、Windows、macOS 的 Flutter 客户端源码。
- Go 后端源码、数据库迁移和配置模板。
- 运营管理后台源码（admin）。
- 客服管理后台源码（admin-kf）。
- Flutter Web、Docker、宝塔部署和构建脚本。
- 产品图片、字体和表情资源。
- 全套功能表、源码目录说明、部署教程和接口资料。

源码基线：eb3cc1d49f28cb1d7ac23557c9fae9d3ee957689

本包不包含生产环境凭据、私钥和云服务私密配置。部署示例中的域名必须在交付前核对，并替换为客户自有域名或明确的占位域名。

安全边界：已排除 Git 历史、node_modules、构建缓存、二进制文件、数据库备份、日志、用户上传、Android 签名文件、SSL 证书、私钥和本地环境配置。

开始使用前可直接访问部署后的 /delivery/handbook，由后端先展示并记录合规协议确认；离线时优先打开 docs/客户源码交付一键部署手册.html。也可依次阅读 README.md、SOURCE_DELIVERY.md、docs/客户源码交付使用指南.md、docs/源码目录说明.md、docs/产品功能清单-前后台.md、docs/源码使用与合规责任协议.md、docs/交付环境端口域名与各端打包全教程.md、docs/客户域名替换与Docker一键交付小白教程.md、docs/API接口完整参考.md、docs/CONFIGURATION.md、docs/接口与数据流说明.md 和 docs/OPERATIONS.md。客户合同与签署资料在独立资料包内，不混入源码 ZIP。

本包已经通过交付方身份脱敏门禁；公司名称、联系方式、私有域名和自有版权归属信息命中都会阻止压缩。
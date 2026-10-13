# TechPie Watch — GT 系列开发工程

当前测试设备：HUAWEI WATCH GT 6 Pro / HarmonyOS 6.1，应用调测助手 1.2.1.600。最低目标机型：HUAWEI WATCH GT 3，允许要求更新至最新固件。

SDK 26 / API 18 以及首个 API 10 签名包在 GT 6 Pro 上安装报错误 40。发现首版配置适配器错误删除了编译生成的资源 ID，现已修复。当前最低和目标 API 为 10；编译工具仍是 SDK 26，GT 3 与 GT 6 Pro 真机支持均未验证。

独立的 Lite Wearable 工程，采用本机 DevEco Studio 自带 Lite Empty Ability 模板对应的 FA / JS / HML / CSS 构建方式。DevEco Studio 应打开本目录 `harmonyos_watch/`。

## 当前功能

- 本机时间与日期（进入页面和点击按钮时更新）。
- 首页与同步状态说明切换。
- 明确显示未绑定、未同步状态，没有模拟余额或付款码。

Wear Engine 通信、校园卡、课表、持久化和离线支付尚未接入。构建成功不等于 GT 6 真机安装或支付验证成功。

## 目录

- `entry/`：实际手表入口，`config.json` 声明 `liteWearable`。
- 根目录构建配置：不依赖 Flutter SDK 或主项目的 pubspec。
- `ohos/`：保留的手机端参考源码，不参与根工程构建。不要打开这个子目录来构建手表应用。

## 构建

### 官方开发指南对照（2026-10-13）

对照 [轻量级智能穿戴应用开发](https://developer.huawei.com/consumer/cn/doc/lite-wearable-guides/lite-wearable-bpta-guide)：FA 模型、JS/HML/CSS 页面、`.MainAbility`、`liteWearable`、入口页面与资源引用结构均符合其示例。`label` 引用名 `app_name` 为 8 个字符，低于指南提示的 22 字符上限。编译后的入口 JS 为 4777 字节，低于该指南针对错误 34 提到的 48KB。

指南的错误 40 排查明确列出编译 SDK、label 引用名长度和图标尺寸。原工程使用本地模板的 104×104 图标，现改为 `icon.png` 114×114，并增加 `icon_small.png` 80×80；编译产物中两种图标及其转换后的 BIN 均已生成。独立对照包为 `TechPie-watch-api10-iconfix-signed.hap`，已通过 HAP 验签，但尚未完成真机验证。

编译 SDK 仍为 26.0.0，兼容/目标声明为 API 10，且存在自定义打包配置适配器。指南没有证明这个组合支持 GT 3 或 GT 6 Pro。修改 API 声明不能替代实际编译 SDK 对照；应继续核实设备支持清单及安装日志。该指南运行章节还限定辅助手机为 HarmonyOS 5 以前的华为手机，当前用于安装的具体手机型号与系统尚未核实。

本机 DevEco Studio 26.0 工具链已通过构建。编译 SDK 为 26.0.0，目标和兼容 SDK 为 4.0.0(10)。这只是 API 10 对照包，不等同于使用官方 Lite API 10 编译 SDK；最终支持范围需要真机验证。

```powershell
cd E:\Projects\TechPie-flutter\harmonyos_watch
.\build.ps1
```

其他 DevEco 安装目录可通过 `-DevEcoHome` 指定；发布模式可通过 `-BuildMode release` 指定。实际应用版本是 `entry/src/main/config.json` 中的 `0.1.0`；oh-package 文件中的 `1.0.0` 是构建模块元数据版本。

产物位于 `entry/build/default/outputs/default/`。没有签名配置时为 `entry-default-unsigned.hap`；产品关联签名配置后为 `entry-default-signed.hap`。真机安装使用后者，签名需匹配 `com.geekpie.techpie.watch` 和调试设备。

### SDK 26 的 Lite 配置兼容

本机 SDK 26 共用的 FA 配置处理器会向最终配置添加额外字段，并把 API 18 编码为 `50100018`。`entry/hvigorfile.ts` 在 `LegacyGenerateLiteCode` 任务前调用 `scripts/lite-profile.cjs`：保留 Lite 字段及编译生成的 `iconId`、`labelId`、`descriptionId`，恢复整数 API 级别，然后正常生成 BIN 和签名 HAP。证书和签名后的文件不做修改。

源码 schema 不能用来裁剪编译后的安装配置：官方 [Lite 手表解析器](https://github.com/openharmony/bundlemanager_bundle_framework_lite/blob/master/services/bundlemgr_lite/src/gt_bundle_parser.cpp) 的 `ParseAbilityInfo` 要求 `$string` 标签带 `labelId`，并要求图标带 `iconId`。首版适配器删除这些 ID，导致资源引用无法解析。已增加缺失 ID 时停止构建的检查，并从干净缓存重新生成资源。修正版单独命名为 `TechPie-watch-api10-resourcefix-signed.hap`，仍需真机安装验证。OpenHarmony 开源解析器是排查参考，不能证明 GT 6 Pro 固件内部实现完全相同。修改打包配置不等于更换 JS 编译器、资源格式或 Lite BIN 工具链。

兼容逻辑测试：`node --test scripts/lite-profile.test.cjs`。修改目标 API 时仍以根 `build-profile.json5` 为准。

### 经典 Lite 工具链获取情况

官方历史 Command Line Tools 2.0.0.2 已下载至 `E:\SDKs\harmonyos-legacy-cli`，并按华为历史下载页的 SHA-256 校验。用户已同意 HarmonyOS SDK 许可。但官方 `sdkmgr install js:6 toolchains:6` 返回 `Could not found download url`，因此 SDK API 6 尚未安装，不能执行经典 SDK 对照构建。SDK 6 指 API 级别 6（HarmonyOS 2.2.0），并非手表显示的 HarmonyOS 6.x 系统版本。

`local.properties` 为本机 SDK 路径，已忽略。其他机器需设置 `DEVECO_SDK_HOME` 或在 DevEco 中配置 SDK。没有保存证书或私钥。

## 后续移植

1. 验证 GT 6 安装、页面与生命周期。
2. 接入 Android / HarmonyOS 手机侧 Wear Engine，定义统一快照和回执。
3. 同步卡片信息、今日课程和近期截止日期。
4. 验证安全存储、SM2/SM3 和二进制 QR 后，再加入离线付款码。

业务参考位于主项目的 `lib/services/watch_sync_service.dart`、`lib/features/campus_card/`、`ios/TechPieWatch/` 和 `ios/WatchSupport/`。保留安装身份、递增版本、授权到期与撤销规则。

<div align="center">
<a href="https://techpie.geekpie.club">
<img src="./assets/logo/Logo-1.png" alt="TechPie logo" style="border-radius:50%"/>
</a>

# TechPie

**🥧 **TechPie** 是一个由 GeekPie 开发的 **开源、轻量、美观** 的 ShanghaiTech 第三方校园服务平台！ 🚀**

</div>

> [!WARNING]
>
> 注意，由于 HarmonyOS 支持的破坏性加入，上游 Dart/flutter 版本需要回退，部分特性无法使用。相关 SDK 需要降级。

## Support Platform

理论支持多平台，实际测试如下平台：

- [x] Linux
- [x] Windows
- [x] MacOS
- [x] Android
- [x] iOS
- [x] HarmonyOS NEXT

## Roadmap

- UI
  - [x] Schedule
  - [x] Login
  - [ ] Assignment
  - [ ] Homepage
  - [ ] iOS
    - [x] Liquid Glass
    - [ ] Dynamic Island
  - [ ] HarmonyOS NEXT
    - [ ] Native Card
    - [ ] Realtime Window
  - [ ] Android (Including other customized OS)
    - [ ] Soooo many...
- API
  - [x] GeekPie SSO (Casdoor) login + token refresh
  - [x] eGate binding / CpDaily keep-alive (via /api/auth/renew)
  - [ ] Schedule
  - [ ] Homework / Resources
    - [ ] GradeScope
    - [ ] elearning
    - [ ] Piazza
    - [ ] ACM OJ
- Feature
  - [x] Auto renew token
  - [x] Auto refresh schedule
  - [ ] Auto deadline fetch / jump
  - [ ] Piazza Forum
  - [ ] CourseBench Integration

## Development

参考 HarmonyOS / 仓库配置

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export FLUTTER_OHOS_STORAGE_BASE_URL=https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export HOS_SDK_HOME="$HOME/dev/command-line-tools/sdk"
```

### Android

- Aliyun mirror
- JDK 17
- Android NDK 28
- Android SDK 35

### iOS

- macOS
- Xcode
- CocoaPods
- iOS Deployment Target 15.5

### HarmonyOS

- Flutter (OHOS patch) 3.27.5-ohos-1.0.5
- [Huawei Command Tools 6.1.1 Beta1](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)

## Release & Versioning

版本只有一个来源：`pubspec.yaml` 的 `version:` 行，格式 `X.Y.Z[-rc.N]+B`。

- `X.Y.Z` —— 用户看到的版本号（应用内设置页、商店、安装包的 versionName / `CFBundleShortVersionString`）。
- `+B` —— 构建号，全局单调递增、永不重置，落成 Android 的 versionCode 与 iOS 的 `CFBundleVersion`。
- `-rc.N` —— 候选序号，发布时由 tag 历史推导，不用手写。

两个发布渠道：

| 渠道                    | 什么触发                                     | 产物                                                                                                                                 |
| ----------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **候选版** `X.Y.Z-rc.N` | 在 `master` 上手动运行 `release.yml`         | GitHub 预发布 + Android 三个 APK（arm64/arm32 split + universal）、Linux `tar.gz`、Windows `zip`、OHOS 未签名 hap；iOS 进 TestFlight |
| **正式版** `X.Y.Z`      | 合并 `prepare-release.yml` 开出的 release PR | GitHub 正式发布（Latest）+ 同上全部产物；iOS 进 TestFlight                                                                           |

```bash
# 候选版：改 +B、写 CHANGELOG、推送、手动发布
$EDITOR pubspec.yaml CHANGELOG.md
git commit -am "chore(release): candidate" && git push
gh workflow run release.yml --ref master

# 正式版：CI 切出 release/X.Y.Z 并开 PR，review 后合并 —— 那次合并就是发布
gh workflow run prepare-release.yml --ref master -f version=1.0.0
```

发布说明写在 `CHANGELOG.md`，按**产品版本**分节（`## [1.0.0]`，同一条线的候选版和正式版共用一节）。没有说明的版本会被拒绝发布。

上传 Google Play / AppGallery / App Store Connect 仍是人工步骤，产物在 GitHub Release。完整的强制规则、发布编号规则与故障处理见 [`CLAUDE.md`](CLAUDE.md#releasing)。

## License

MIT

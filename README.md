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
  - [x] eGate login / keep alive
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
- iOS Deployment Target 14.0

### HarmonyOS

- Flutter (OHOS patch) 3.27.5-ohos-1.0.5
- [Huawei Command Tools 6.1.1 Beta1](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)

## License

MIT

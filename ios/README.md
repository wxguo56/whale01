# WhaleAgent 原生 iOS 工程

本目录是代号鲸鱼01的原生 iOS 入口。源码可以在 Windows 编辑，但苹果 SDK 编译、签名和真机安装必须在 macOS 完成。

## 当前状态

- 已提交最小原生工程：19 个 Swift 文件、`project.yml`、Info.plist、entitlements、实际 Scheme。
- 静态校验：19/19 文件通过 Swift 语法解析；15 个契约工具中 14 个设备工具全部有手机执行路由，`summarize_shared_content` 明确留在后端。
- 后端回归：`cd backend; npm test`，45/45 通过。
- 当前 Windows 执行机没有 Xcode、Swift、XcodeGen、签名证书或 iOS 工程产物，因此还没有真实的 `xcodebuild` 结果。
- GitHub Actions 尚未运行：本地提交已就绪，但远端仓库和 GitHub 认证还没配置。

## 第一次云端编译

1. 在 GitHub 创建一个私有仓库（例如 `whale01`），不要勾选初始化 README。
2. 在仓库根目录执行：

```bash
git remote add origin https://github.com/<账号>/<仓库>.git
git push -u origin main
```

3. 推送包含 `ios/**` 的提交会自动触发 `iOS Simulator Build`；也可以在 Actions 页面手动 `Run workflow`。
4. 构建结束后下载 artifact `ios-simulator-build-log`，查看完整 `ios/build.log`。

判定通过的标准是：macOS job 为绿色，且日志包含 `BUILD SUCCEEDED`。只看到工作流启动、或者只拿到源码 ZIP，都不算编译通过。

## 本轮收紧的真实执行边界

- App 只在 `/healthz` 明确返回 `executionMode=ios` 时才发送 `deferExecution=true`；mock 模式不会让手机误执行真实系统写入。
- 日历查询的 `calendarIds=[]` 视为“全部日历”，不会误返回空结果。
- 工作流新增 `xcodebuild -list` 与 `xcodebuild -showsdks`，工程生成失败时能直接定位。

## 本机（macOS）验证

```bash
brew install xcodegen
cd ios
xcodegen generate
xcodebuild \
  -project WhaleAgent.xcodeproj \
  -scheme WhaleAgent \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## GitHub Actions 验证

推送包含 `ios/**` 的提交，或在 Actions 页面手动运行 `iOS Simulator Build`。工作流在 `macos-15` 上安装 XcodeGen、生成工程并做不签名的模拟器编译。

## 真机签名前必须补齐

- Apple Developer Team 与正式 Bundle ID。
- `com.apple.developer.healthkit` 与 `com.apple.developer.weatherkit` 能力。
- 真机需要的签名证书和描述文件。
- App 可访问的后端地址；`127.0.0.1` 在手机上指向手机自身。

## 真实能力

- EventKit：提醒事项、日历读写。
- HealthKit：步数、活动能量、锻炼时间、步行距离。
- MapKit：地点搜索与地图导航交接。
- Contacts + MessageUI：联系人解析与短信/邮件草稿。
- MusicKit：用户音乐库搜索与播放控制。
- WeatherKit：天气查询（需要 WeatherKit entitlement）。
- 分享内容摘要仍由后端模型处理，不伪装成手机系统写入。

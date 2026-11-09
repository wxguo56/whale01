# WhaleAgent 原生 iOS 工程

本目录是代号鲸鱼01的原生 iOS 入口。源码可以在 Windows 编辑，苹果 SDK 编译在 macOS 完成；正式归档签名可在 macOS 完成，未签名真机 IPA 可由 AltServer／SideStore 用本人 Apple 账号重签，最终安装在 iPhone 上完成。

## 当前状态

- 已提交最小原生工程：19 个 Swift 文件、`project.yml`、Info.plist、entitlements、实际 Scheme。
- 静态校验：19/19 文件通过 Swift 语法解析；15 个契约工具中 14 个设备工具全部有手机执行路由，`summarize_shared_content` 明确留在后端。
- 后端回归：`cd backend; npm test`，45/45 通过。
- GitHub Actions 已实际运行并通过：run `42579515669`，commit `d30b702`，Xcode 16.4 / iOS 18.5 SDK，日志 `** BUILD SUCCEEDED **`。
- 签名、TestFlight、iPhone 安装与真实系统写入仍未执行。

## 云端编译（已完成）

首次运行记录：<https://github.com/wxguo56/whale01/actions/runs/42579515669>。复现步骤：

1. 私有仓库已创建：`wxguo56/whale01`。
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

## 免费签名真机安装（AltStore / SideStore）

没有付费开发者账号时，使用 `WhaleAgentSideload` scheme：

- Bundle ID：`com.whale01.whaleagent.alt`
- Entitlements：`WhaleAgent-Sideload.entitlements`（空，不申请受限能力）
- 编译条件：`FREE_SIGNING`，天气与运动摘要会返回 `unavailable_in_free_build`
- IPA 由 `.github/workflows/ios-sideload-ipa.yml` 在 macOS runner 上构建并上传 artifact
- 完整安装与验收步骤见 `15_AltStore与SideStore真机安装.md`

免费签名有效期 7 天，最多同时安装 3 个 App，不支持 HealthKit、WeatherKit、App Groups 与推送。

## 真实能力

- EventKit：提醒事项、日历读写。
- HealthKit：步数、活动能量、锻炼时间、步行距离。
- MapKit：地点搜索与地图导航交接。
- Contacts + MessageUI：联系人解析与短信/邮件草稿。
- MusicKit：用户音乐库搜索与播放控制。
- WeatherKit：天气查询（需要 WeatherKit entitlement）。
- 分享内容摘要仍由后端模型处理，不伪装成手机系统写入。

## 0.2.0 原生业务界面

- 四个 Tab：首页 / 对话 / 音乐 / 设置；诊断信息集中在“开发设置与诊断”。
- 首页与音乐页只读真实 EventKit / MusicKit 数据，无权限或无数据时如实说明。
- 对话页保留真实后端链路，新增原生确认 Sheet、断线重试与新建会话。
- 版本 `0.2.0`，Build 号由 CI 的 `github.run_number` 递增；本次构建为 Build 3。

## 真机辅助工具

- `tools/phone_hid.py`：直连 `UniversalHIDServiceService` 的 USB HID 驱动，支持 `wake`、`tap`、`swipe`、`text`、`key`、`paste`、`shot`。iOS 26 上 `touch_session` 会报 “Remote control requires iOS 27.0 or later”，因此不再使用它；锁屏状态下系统会丢弃 HID 触控，必须人工解锁。
- `tools/serve-ipa.mjs`：`node tools/serve-ipa.mjs release 8089`，在 `0.0.0.0:8089` 分发 IPA，供 AltStore 深链 `altstore://install?url=...` 拉取。
# WhaleAgent 原生 iOS 工程

本目录是代号鲸鱼01的原生 iOS 入口。源码可以在 Windows 编辑，苹果 SDK 编译在 macOS 完成；正式归档签名可在 macOS 完成，未签名真机 IPA 可由 AltServer／SideStore 用本人 Apple 账号重签，最终安装在 iPhone 上完成。

## 当前交互（0.7.0）

系统主栏为助手、待办、发现，设置从右上角打开。首页集中显示待确认操作、今天安排、可编辑常用操作和简洁天气；文字/语音草稿按会话保留，语音停止后可先检查再发送。主栏只挂载当前页面，草稿与播放状态独立保存。

本轮实施与原生/UI 验收见 [实施与验收](../review/ui-habits-2026-11-13/实施与验收.md)。推送快速校验、UI 手动触发的操作方式见下文。

## 初始工程记录（历史）

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

3. 推送涉及 iOS、后端或 iOS 工作流的提交会自动触发 `Push Quick Validation`；也可以在 Actions 页面手动 `Run workflow`。
4. 构建结束后下载 artifact `ios-quick-compile-log`，查看完整 `ios/compile.log`。

快速编译通过的标准是：macOS job 为绿色，且两个 scheme 日志都包含 `TEST BUILD SUCCEEDED`。这里仅编译测试目标；实际测试是否通过，需要查看手动测试结果。

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

推送与 PR 自动运行 `Push Quick Validation`：Ubuntu 执行受控的后端回归，macOS 编译 App、原生单元测试和 UI 测试目标，不启动模拟器。新提交会取消同一分支仍在运行的旧快速校验。

快速校验与手动完整测试使用不同的并发分组，推送不会中断已经手动启动的完整测试。两种测试各自只保留同一分支最新一次运行。

完整测试在 GitHub → Actions → `iOS Manual Interaction Tests` → `Run workflow` 中手动触发，选择待验分支。它启动 iPhone 模拟器，执行原生单元测试以及导航、草稿跨页/重启的 UI 测试；测试失败仍导出日志、xcresult 和截图。编译通过不能代替这些实际测试。

在新工作流尚未合入默认分支时，也可以手动运行已有的 `Push Quick Validation`，选择 `scope=interaction`。该入口调用同一完整测试流程；默认 `scope=quick` 只做快速校验，push/PR 不会进入完整测试。

`iOS UI Snapshot` 保留手动截图入口，`scope=interaction` 覆盖助手、待办、发现、设置、深色和大字号。`iOS Sideload IPA` 改为仅手动运行，候选完整测试通过后再打包，原有身份核对和加密上传保持有效。

## 真机签名前必须补齐

- Apple Developer Team 与正式 Bundle ID。
- `com.apple.developer.healthkit` 与 `com.apple.developer.weatherkit` 能力。
- 真机需要的签名证书和描述文件。
- App 可访问的后端地址；`127.0.0.1` 在手机上指向手机自身。

## 免费签名真机安装（AltStore / SideStore）

没有付费开发者账号时，使用 `WhaleAgentSideload` scheme：

- Bundle ID：`com.whale01.whaleagent.alt`
- Entitlements：`WhaleAgent-Sideload.entitlements`（空，不申请受限能力）
- 编译条件：`FREE_SIGNING`；天气走 Open-Meteo 公共 HTTPS 接口，不受签名限制；运动摘要（HealthKit）返回 `unavailable_in_free_build`
- IPA 由 `.github/workflows/ios-sideload-ipa.yml` 在 macOS runner 上构建并上传 artifact
- 完整安装与验收步骤见 `15_AltStore与SideStore真机安装.md`

免费签名有效期 7 天，最多同时安装 3 个 App，不支持 HealthKit、App Groups 与推送。天气不再依赖 WeatherKit，改用无需 entitlement 的公共接口。

## 真实能力

- EventKit：提醒事项、日历读写。
- HealthKit：步数、活动能量、锻炼时间、步行距离。
- MapKit：地点搜索与地图导航交接。
- Contacts + MessageUI：联系人解析与短信/邮件草稿。
- MusicKit：用户音乐库搜索与播放控制。
- Open-Meteo：逐日天气查询（公共 HTTPS 接口，免 Key，免费签名可用；只支持未来 16 天）。
- 分享内容摘要仍由后端模型处理，不伪装成手机系统写入。

## 0.2.0 原生业务界面

- 四个 Tab：首页 / 对话 / 音乐 / 设置；诊断信息集中在“开发设置与诊断”。
- 首页与音乐页只读真实 EventKit / MusicKit 数据，无权限或无数据时如实说明。
- 对话页保留真实后端链路，新增原生确认 Sheet、断线重试与新建会话。
- 版本 `0.2.1`，Build 号由 CI 的 `github.run_number` 递增；当前构建为 Build 5。
- 对话输入栏内置系统语音输入（Speech + AVAudioEngine），键盘可通过“完成”、收起按钮、点击空白或发送后收起。

## 真机辅助工具

- `tools/phone_hid.py`：直连 `UniversalHIDServiceService` 的 USB HID 驱动，支持 `wake`、`tap`、`swipe`、`text`、`key`、`paste`、`shot`。iOS 26 上 `touch_session` 会报 “Remote control requires iOS 27.0 or later”，因此不再使用它；锁屏状态下系统会丢弃 HID 触控，必须人工解锁。
- `tools/serve-ipa.mjs`：`node tools/serve-ipa.mjs release 8089`，在 `0.0.0.0:8089` 分发 IPA，供 AltStore 深链 `altstore://install?url=...` 拉取。

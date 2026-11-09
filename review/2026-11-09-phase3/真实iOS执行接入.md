# 真实 iOS 执行接入记录

日期：2026-11-09｜阶段：Phase 3（原生工程与设备执行）｜状态：源码已落地，未编译、未签名、未真机

## 1. 结论

- 15 个工具中，14 个手机系统能力已写成真实 Swift 执行器；`summarize_shared_content` 仍在后端模型侧，不伪装成手机系统写入。
- 已建立 XcodeGen 工程、权限声明和 GitHub Actions 的 macOS 模拟器编译流水线。
- 当前 Windows 执行机没有 Xcode、Swift、iOS SDK、签名证书；仓库也没有 GitHub remote 或可用认证，所以本轮没有实际触发 macOS 编译。
- 因此当前不能声称“已写入真实 iOS 系统”。准确状态是：真实系统写入代码已写完，等待 macOS 编译与真机授权。

## 2. 本轮交付

| 文件／目录 | 作用 |
|---|---|
| `ios/project.yml` | XcodeGen 工程定义，iOS 17、Bundle ID `com.whale01.agent`、系统框架依赖 |
| `ios/WhaleAgent/Info.plist` | 提醒、日历、健康、定位、通讯录、音乐权限说明与开发期 ATS |
| `ios/WhaleAgent/WhaleAgent.entitlements` | HealthKit 与 WeatherKit 能力声明 |
| `ios/WhaleAgent/App/` | SwiftUI 入口、聊天输入、确认卡、权限状态与执行状态机 |
| `ios/WhaleAgent/Networking/` | `/healthz`、`/v1/turns`、`/tool-results` 客户端 |
| `ios/WhaleAgent/Execution/` | 权限中心、工具路由、去重账本与 6 个真实框架执行器 |
| `.github/workflows/ios-simulator-build.yml` | macOS 15 runner 上生成工程并做不签名模拟器编译 |
| `backend/src/capabilities.mjs` | 设备工具清单与逐工具执行位置 |
| `backend/src/config.mjs` | `EXECUTION_MODE=ios/device`，统一输出 `ios` |
| `backend/src/agent.mjs` | 设备模式强制 `deferExecution=true`；手机工具挂起，模型侧摘要先在后端执行 |

Swift 源码共 19 个文件、约 2159 行。

## 3. 真实能力映射

| 工具 | iOS 真实能力 | 状态 |
|---|---|---|
| `create_reminder` | EventKit `EKReminder` + 到期闹钟 | 代码已写，未编译／未真机 |
| `list_calendar_events` | EventKit `EKEvent` 读取 | 代码已写，未编译／未真机 |
| `create_calendar_event` | EventKit `EKEvent` 写入 | 代码已写，未编译／未真机 |
| `get_weather` | WeatherKit 日预报 + `CLGeocoder` | 代码已写，需 WeatherKit entitlement |
| `get_activity_summary` | HealthKit 步数、活动能量、锻炼时间、距离 | 代码已写，未真机 |
| `search_places` | MapKit `MKLocalSearch` | 代码已写，未编译／未真机 |
| `open_navigation` | `MKMapItem.openInMaps` | 代码已写，未编译／未真机 |
| `prepare_message` | Contacts 解析 + `MFMessageComposeViewController` / `MFMailComposeViewController` | 代码已写，短信需真机 |
| `search_music_library` | MusicKit `MusicLibraryRequest<Song>` | 代码已写，未真机 |
| `play_music` | `ApplicationMusicPlayer` 队列与播放 | 代码已写，未真机 |
| `pause_music` | `ApplicationMusicPlayer.pause` | 代码已写，未真机 |
| `resume_music` | `ApplicationMusicPlayer.play` | 代码已写，未真机 |
| `skip_music_track` | `skipToNextEntry` / `skipToPreviousEntry` | 代码已写，未真机 |
| `get_playback_state` | MusicKit 播放器真实状态 | 代码已写，未真机 |
| `summarize_shared_content` | 后端模型侧，不是手机系统能力 | 仍为现有后端链路，未接真实正文抓取 |

## 4. 设备执行数据流

1. App 调 `POST /v1/turns`，固定带 `deferExecution: true` 和当前权限快照。
2. 后端返回 `status: awaiting_tool_results`，`pending[]` 只包含手机工具。
3. App 的 `PermissionCenter` 按工具申请系统权限；`NativeToolRouter` 调真实框架执行。
4. App 把每个 `toolCallId` 的 `success`／`failed`／`needs_authorization`／`cancelled` 回传 `POST /v1/turns/:turnId/tool-results`。
5. 后端写操作日志、记录实体、继续模型循环并生成自然语言回复。

去重由两端共同保证：后端继续使用 `operationId`；App 侧新增 `OperationLedger`，成功结果按 `operationId` 持久化，重试时返回 `deduplicated: true`，避免重复写提醒或日历。

## 5. 权限与签名

`Info.plist` 已声明：

- `NSRemindersFullAccessUsageDescription`
- `NSCalendarsFullAccessUsageDescription`
- `NSHealthShareUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `NSContactsUsageDescription`
- `NSAppleMusicUsageDescription`

`WhaleAgent.entitlements` 已声明 `com.apple.developer.healthkit` 与 `com.apple.developer.weatherkit`。真机签名前必须在 Apple Developer 团队中启用对应能力，并使用匹配的 Bundle ID、证书和描述文件。

开发期 `NSAllowsArbitraryLoads` 仅为连接局域网 HTTP 后端；正式版本应改为 HTTPS 并移除该开关。

## 6. 本轮已经验证

- 后端测试：`cd backend; npm test`，45/45 通过。
- `ios/project.yml` 与 GitHub Actions YAML 可被 YAML 解析。
- `Info.plist` 与 entitlements 可被 plist 解析。
- 19 个 Swift 文件通过 tree-sitter-swift 语法解析，0 个语法错误。
- 工具名与契约对齐：手机路由覆盖 14 个设备工具，`summarize_shared_content` 明确留在后端。

## 7. 本轮没有验证

- 没有在 macOS／Xcode 下执行 `xcodegen generate` 和 `xcodebuild`，因此没有类型检查、链接和真实 SDK 编译结果。
- 没有签名、archive、TestFlight 或 Ad Hoc 安装。
- 没有在 iPhone 上触发 EventKit、HealthKit、MapKit、MessageUI、MusicKit、WeatherKit 的真实系统写入。
- 没有 GitHub Actions 运行记录：当前仓库没有 remote，也没有可用 GitHub 认证。

## 8. 下一关

1. 提供可推送的 GitHub 仓库地址，或明确授权创建私有仓库。
2. 推送 `ios/**` 与 `.github/workflows/ios-simulator-build.yml`，手动运行 `iOS Simulator Build`。
3. 把 `ios/build.log` 贴回；按真实 Xcode 报错修编译问题，直到 macOS runner 绿灯。
4. 配 Apple Developer Team、正式 Bundle ID、HealthKit／WeatherKit 能力和签名。
5. TestFlight 或 Ad Hoc 安装到 iPhone 16 Pro。
6. 第一项真机闭环只做 EventKit 提醒：授权、创建、到点通知、结果回传、重复请求不重复写入。
7. 再按日历、健康、定位、短信、音乐逐项验收。

## 9. 已知风险

- WeatherKit 依赖 Apple Developer entitlement 和可用性，失败时会明确报错，不会伪造天气。
- MusicKit 的库请求和播放器 API 可能随 SDK 版本有差异，必须由 macOS CI 实际编译确认。
- MessageUI 在模拟器上通常不可用，短信草稿必须在真机验收。
- HealthKit 不披露读权限是否被拒绝；无数据时会区分“无记录／可能未授权”，不推断为 0。
- MapKit 地点引用只在当前 App 进程内有效；跨进程或重启后需要重新搜索。
- `summarize_shared_content` 仍是后端现有链路，真实正文抓取尚未接入。

## 10. 证据入口

- 原生工程：`ios/`
- 构建说明：`ios/README.md`
- 流水线：`.github/workflows/ios-simulator-build.yml`
- 后端测试：`backend/test/`
- 构建路线：`14_Windows构建与真机安装路线.md`

## 11. 0.2.0 原生业务界面与真机验收状态

### 11.1 已完成（代码与云编译）

| 项目 | 结果 |
| --- | --- |
| 提交 | `bc890ee` feat(ios): replace validation shell with native business UI |
| 版本 | `MARKETING_VERSION=0.2.0`，`CURRENT_PROJECT_VERSION=github.run_number` → Build 3 |
| 模拟器构建 | GitHub Actions run `42593063615`，`BUILD SUCCEEDED` |
| 免费签名 IPA | GitHub Actions run `42593063834`，`ARCHIVE SUCCEEDED` |
| 产物 | `release/WhaleAgent-Sideload.ipa`，334,790 bytes |
| SHA256 | `f25e054db83b7bd01686ca090196be18ea43a7ce0a02e3ea6bfb03a4137977f8` |
| Bundle ID | `com.whale01.whaleagent.alt` |
| 后端测试 | 47/47 通过 |
| Swift 语法 | 25 个文件 tree-sitter 解析 0 错误 |

界面改动：

1. 首页：品牌 Hero、快捷入口、真实日历日程、权限摘要、最近执行记录；没有数据时显示空状态，不造假。
2. 对话：业务聊天、置信确认卡、原生确认 Sheet、断线重试、新建会话；顶部不再挂诊断信息。
3. 音乐：MusicKit 音乐库、搜索、播放/暂停/上一首/下一首、权限引导。
4. 设置：权限状态绑定、授权入口、关于；诊断信息集中到“开发设置与诊断”。

### 11.2 真机安装步骤（iPhone 16 Pro / iOS 26.5.2）

设备信息：`iPhone17,1`，iOS `26.5.2 (23F84)`，UDID `00008140-001429613442801C`。

1. 在 iPhone 上手动解锁并保持亮屏（iOS 26 锁屏时会丢弃 USB HID 触控，无法远程解锁）。
2. 电脑启动局域网 IPA 服务：`node tools/serve-ipa.mjs release 8089`。
3. 手机与电脑同一 Wi-Fi，确认电脑地址（当前 `10.219.86.103`）。
4. 手机 Safari 打开：`altstore://install?url=http://10.219.86.103:8089/WhaleAgent-Sideload.ipa`，确认交给 AltStore。
5. 等待 AltStore 重签安装完成，系统设置 → 通用 → 关于 → WhaleAgent 确认版本 `0.2.0 (3)`。

辅助工具：`tools/phone_hid.py`（wake / tap / swipe / text / paste / shot），用于截图与界面操作；该工具在锁屏时无效。

### 11.3 待验收清单（0.2.0）

- [ ] 安装成功，系统“关于”显示 `0.2.0 (3)`。
- [ ] 首页：真实日历读取正确；无授权时显示引导而非假数据。
- [ ] 对话：真实模型回复、确认 Sheet、确认后执行、拒绝后不执行。
- [ ] 提醒：系统“提醒事项”出现记录，到点通知到达。
- [ ] 幂等：相同请求重复提交只写入一条。
- [ ] 日历：查询与创建事件，时区/全天事件正确。
- [ ] 地点：搜索与地图交接。
- [ ] 短信：MessageUI 草稿与取消回调。
- [ ] 音乐：库读取、搜索、播放/暂停/切歌。
- [ ] 免费版边界：天气/运动返回 `unavailable_in_free_build`。
- [ ] 权限拒绝：界面如实提示，不伪造成功。
- [ ] 设置页“开发设置与诊断”可展开，主流程不出现诊断噪声。

### 11.4 证据边界

- 现有真机证据（`取快递` 提醒写入、`operationId=op_turn_73b39cd7...`、`recordId=3A4A797A-...`）来自 0.1.0 构建，只能证明 EventKit 链路曾经打通。
- 0.2.0 目前只有代码、云编译与未签名 IPA，尚未在手机上安装，因此不能写成“0.2.0 真机验收通过”。
## 12. 0.2.1 对话输入交互修复

真机（0.2.0 Build 3）反馈：

- 对话页没有语音输入入口，只能借用系统键盘听写。
- 键盘听写结束后，键盘无法收起，遮挡输入区域。

修复：

| 项目 | 实现 |
| --- | --- |
| 语音输入 | 输入栏左侧麦克风按钮，`SFSpeechRecognizer(zh-CN)` + `AVAudioEngine` 实时转写，结果写入输入框 |
| 识别状态 | 录音时顶部显示红点与实时文本，可“停止” |
| 失败处理 | 权限拒绝 / 识别服务不可用 / 麦克风启动失败分别提示，不编造文本 |
| 收起键盘 | 键盘“完成”键、输入栏收起按钮、点击对话空白、发送后自动收起 |
| 滚动行为 | `scrollDismissesKeyboard(.immediately)` |

权限声明新增：

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

构建证据：提交 `648b21d`，run `42607098187`（模拟器）与 `42607098202`（IPA）均 success，`ARCHIVE SUCCEEDED`；产物 `0.2.1 (5)`，SHA256 `c64fa6bd…bd3a9`。

尚未验证：真机上的权限弹窗、中文转写准确度与四种收起键盘路径——需要安装 `0.2.1 (5)` 后逐项确认。
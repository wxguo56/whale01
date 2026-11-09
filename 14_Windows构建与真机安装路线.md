# 代号鲸鱼01：Windows 构建与真机安装路线

日期：2026-11-09｜状态：原生工程、模拟器编译与未签名真机 IPA 已完成；重签、安装与真机验证待执行

## 1. 结论

Windows 可以作为代码编辑、仓库管理和构建触发端；原生 iOS 的苹果 SDK 编译在 macOS 上进行。正式 Xcode 归档签名可在 macOS 完成；已构建的真机 IPA 也可通过 Windows／iPhone 上的侧载工具，以本人 Apple 账号重新签名。没有自有 Mac 时，可使用 GitHub Actions 的 macOS runner、支持原生 iOS 的云构建服务或远程真实 Mac。

当前测试路线：Windows 编辑 → GitHub Actions 构建 `WhaleAgentSideload` 真机 IPA → AltServer／AltStore／SideStore 重签与安装，详见 15_AltStore与SideStore真机安装.md。正式 TestFlight 分发仍按下文的开发者团队与签名流程另行配置。

此路线不把 HTML ZIP 转成原生 App。`ios/` 工程与两条工作流已推送，模拟器和未签名 iPhoneOS IPA 均已构建成功。当前下一步是重签并安装到 iPhone，再验证真实系统操作。旧 UI 方案已废弃，不按其还原。

## 2. 哪一步在哪里完成

| 工作 | 执行位置 | 说明 |
|---|---|---|
| Swift／SwiftUI 源码、接口契约、项目配置 | Windows | 可以编辑，不代表本机具备 iOS SDK |
| 生成 Xcode 工程 | 云端 macOS | 无现有工程时可采用 XcodeGen，由 project.yml 生成 |
| 编译、测试、archive 与签名 | 云端 macOS／远程 Mac | 使用实际可用的 Xcode 和 SDK |
| 安装与系统授权 | iPhone 16 Pro | 推荐 TestFlight；真实能力在手机验证 |
| DeepSeek 服务 | 现有后端 | 模型密钥留在后端，不打入 iPhone 安装包 |

## 3. 第一阶段：先证明原生代码可编译

1. 取得已有原生工程；有原工程则复用，不另建重复项目。
2. 如果确实没有，执行者在 Windows 写最小 SwiftUI 工程源码及 XcodeGen project.yml。
3. 最小页面只提供文字输入、发送、授权／确认和结果展示，作为功能测试界面，不开始新 UI 设计。
4. 编写 GitHub Actions 的手动构建配置，使用 macOS runner，在 runner 上生成工程并选择实际 Xcode／SDK。
5. 先做不签名的 iOS Simulator 编译，修复编译问题。

完成标准：真实原生源码在真实苹果 SDK 环境编译通过，构建记录可复现。不签名的模拟器产物不能装进 iPhone，也不能作为真机功能成功。

不能在没有实际工程路径与 Scheme 时提交一份仅带占位符的工作流，声称构建已完成。工程创建与流水线配置分开验证。

## 4. 第二阶段：签名与 TestFlight

需要项目负责人提供或授权使用：

- 一个可访问的 GitHub 仓库及相应 Actions 配置权限；代码上传／推送须明确授权。
- 有效的 Apple Developer Program 个人／组织团队，用于 TestFlight 分发。该计划通常需年费，以实际地区与官方价格为准；云构建资源也按平台配额／收费规则使用。
- 正式 Bundle ID、开发团队及 App Store Connect 应用记录。
- 对应签名证书／私钥、描述文件或项目采用的自动签名机制。
- 适当权限的 App Store Connect API 凭据，用于上传构建。

签名秘密放在构建平台的 Secrets 或专用秘密管理中，不提交到 Git、前端包或对话。使用已有公司团队时让账号负责人授权，不共享个人 Apple ID 密码。

云端流程：

```text
原生项目与配置
      ↓
macOS runner：生成工程、编译／测试
      ↓
Xcode archive：生成 iPhoneOS 构建
      ↓
匹配 Bundle ID 与团队的签名／export
      ↓
上传 App Store Connect，等待构建处理
      ↓
配置 TestFlight 测试访问
```

本阶段使用 iPhoneOS 的可分发构建，不使用第一阶段的模拟器 .app。签名不能修复缺失的 EventKit、音乐或语音代码。

## 5. 第三阶段：手机安装与验收

1. 在 iPhone App Store 安装苹果 TestFlight。
2. 账号负责人将测试者加入相应测试组；内部与外部测试按 App Store Connect 实际要求配置。
3. 接受邀请，在 TestFlight 安装该构建。
4. 从文字输入开始，验证真实 EventKit 提醒保存与结果回传。
5. 再验证日历、音乐、定位、健康与讯飞语音，逐项记录真实权限与结果。

TestFlight 是有期限的测试分发，正式上架／长期分发另行决定。没有开发者团队时可以先完成源码和不签名的云端编译，不能宣称已经具备 TestFlight 安装条件。

## 6. 手机与后端连接

手机的 127.0.0.1 是手机自身，不是 Windows 电脑。原生 App 必须配置手机实际可达的后端地址，开发期按既有网络与访问要求处理，正式版本使用合适的 HTTPS 服务。

真实执行必须使用手机执行器并回传结果；不能让后端继续用 Mock 生成“已创建”。原生能力表、执行位置与 Mock／真实模式分别配置，保留确认和幂等。

## 7. 其他分发方式

远程 Mac 也能构建已签名的 Ad Hoc .ipa，安装仅面向已登记的设备，并受证书／描述文件条件限制。此路线需要另定安装与签名流程，不等于在 Windows 双击任意 .ipa。

Windows 的 Apple Devices 不提供 Xcode／iOS SDK。GitHub 的源码 ZIP、HTML 发布 ZIP 和模拟器产物都不是可直接安装的 iPhone App。

若需要 Windows 上观察和调试 iOS 模拟器，可使用远程 Mac 的界面；GitHub Actions 是自动构建环境，不等于一个长期可交互的远程开发桌面。

## 8. 给执行者的下一批工作

| 顺序 | 工作 | 状态 | 交付门槛 |
|---|---|---|---|
| CI-IOS-01 | 取得或创建最小原生工程 | 已完成（源码） | `ios/` 已有 19 个 Swift 文件、`project.yml`、Info.plist、entitlements 与实际 Scheme |
| CI-IOS-02 | macOS 云编译配置 | 待执行 | 工作流已写；需 GitHub repo／认证后实际编译通过 |
| CI-IOS-03 | 签名与上传配置 | 待外部条件 | Secrets／团队条件就绪；真实签名归档及上传记录 |
| CI-IOS-04 | TestFlight 安装 | 待外部条件 | 在 iPhone 16 Pro 安装成功，明确构建版本 |
| CI-IOS-05 | 第一项真实系统闭环 | 待外部条件 | EventKit 实际记录、真实回传、权限／重复请求验证 |

用户尚未授权具体仓库推送、付费开通或签名凭据配置时，先完成可审查源码与工作流草案，不擅自创建远端仓库、提交／推送或触发付费构建。

## 9. 官方参考

官方／项目参考入口：

- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)：macOS 构建环境。
- [Apple TestFlight](https://developer.apple.com/testflight/)：测试分发与安装。
- [Apple Developer Program](https://developer.apple.com/programs/)：团队与分发条件。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：以配置生成 Xcode 工程。

这些是实施依据，不代表本项目已经执行任何云构建、上传或真机安装。

## 10. 2026-11-09 本轮进展

- 已建立 `ios/` 原生工程：SwiftUI 最小界面、权限中心、设备工具路由、EventKit／HealthKit／MapKit／Contacts＋MessageUI／MusicKit／WeatherKit 执行器。
- 已写 `.github/workflows/ios-simulator-build.yml`：macOS 15 runner、XcodeGen 生成工程、`xcodebuild` 不签名模拟器编译、失败时上传 `build.log`。
- 后端新增 `EXECUTION_MODE=ios/device`；设备模式强制 `deferExecution=true`，14 个手机工具下发到 App，`summarize_shared_content` 仍由后端处理。
- 后端测试 45/45 通过；19 个 Swift 文件通过 tree-sitter 语法解析；YAML、Info.plist、entitlements 均可解析。
- 尚未执行：macOS 编译、签名、TestFlight、真机系统写入、GitHub Actions。验收细节见 `review/2026-11-09-phase3/真实iOS执行接入.md`。

## 11. 2026-11-09 第二轮：工程已就绪，唯一阻塞是 GitHub 认证

已完成并提交（提交 `fb78c29`）：

- 最小原生工程与 CI 工作流已进入本地 `main` 分支；`ios/` 共 19 个 Swift 文件。
- 静态校验：19/19 Swift 文件语法解析 0 错误；15 个契约工具中 14 个设备工具全部有手机执行路由，`summarize_shared_content` 留在后端。
- 后端回归：`cd backend; npm test`，45/45 通过。
- 修正 `SWIFT_VERSION`：由无效的语言版本 `5.9` 改为 Xcode 接受的语言模式 `5.0`，避免 `xcodebuild` 直接拒绝。
- 修正 mock 执行边界：App 只有确认 `/healthz` 返回 `executionMode=ios` 时才发送 `deferExecution=true`；mock 模式不会再误触发手机真实写入。
- 修正日历查询：`calendarIds=[]` 按“全部日历”处理。
- CI 增强：生成工程后先跑 `xcodebuild -list` 与 `-showsdks`，构建同时关闭 `CODE_SIGNING_ALLOWED/REQUIRED` 并清空签名身份。

尚未完成（没有证据，不声称完成）：

- 没有推送远端：当前仓库没有 remote。
- 没有创建 GitHub 私有仓库：设备授权码 15 分钟内未确认，已过期。
- 没有触发 GitHub Actions，也没有任何真实的 macOS `xcodebuild` 日志。
- 没有签名、TestFlight 或 iPhone 安装。

下一步只差 GitHub 认证和仓库。二选一：

A. 已安装 GitHub CLI：

```bash
gh auth login --hostname github.com --git-protocol https --web
gh repo create whale01 --private --source . --remote origin --push
gh workflow run "iOS Simulator Build" --repo <账号>/whale01
gh run watch --repo <账号>/whale01
```

B. 没有 GitHub CLI（本机现状）：

```bash
git credential-manager github login --device
# 浏览器打开 https://github.com/login/device 输入终端显示的代码
# 在 GitHub 网页创建私有仓库 whale01（不要初始化 README）
git remote add origin https://github.com/<账号>/whale01.git
git push -u origin main
# 然后在 Actions 页面运行 iOS Simulator Build
```

GCM 的 GitHub 授权范围已确认包含 `repo` 与 `workflow`，可以推送 `.github/workflows`。

判定标准：Actions 的 macOS job 绿色，且 `ios/build.log` 出现 `BUILD SUCCEEDED`。在这之前，原生工程只能算“静态校验通过”，不能算“编译通过”。

## 12. 2026-11-09 第三轮：GitHub macOS 编译已通过

- 私有仓库：<https://github.com/wxguo56/whale01>
- 通过提交：`d30b702`（`fix(ios): use static EKEventStore authorizationStatus`）
- 运行记录：<https://github.com/wxguo56/whale01/actions/runs/42579515669>
- 环境：macOS 15 runner，Xcode 16.4（16F6），iOS 18.5 SDK
- 结果：job `success`，日志包含 `** BUILD SUCCEEDED **`，artifact `ios-simulator-build-log` 已生成。
- 首个失败已定位并修复：`EKEventStore.authorizationStatus(for:)` 是静态方法，4 处实例调用改为类型调用。

这证明最小原生工程、XcodeGen 配置、Scheme、Info.plist、entitlements 和 19 个 Swift 源文件能在真实苹果 SDK 下完成类型检查、编译与链接。

仍未执行：Apple Developer 签名、TestFlight／Ad Hoc 安装、iPhone 16 Pro 真机运行、EventKit 等系统能力的真实写入。下一步进入第二阶段签名，不把模拟器编译结果当成真机验收。

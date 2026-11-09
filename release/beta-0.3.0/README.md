# 鲸鱼 Beta 0.3.0 交付说明

更新时间：2026-11-09｜工程：`ios/WhaleAgent.xcodeproj`（XcodeGen 生成）

## 1. 本版本范围

- M3：分享扩展、短信/邮件草稿、讯飞语音适配层、角色状态动效、一个 App Intent。
- M4：契约与原生单元测试、真机回归记录、首轮响应耗时指标、Beta 交付文档。
- 真机验收清单与结论见 `测试报告.md`、`已知问题.md`。

## 2. 构建

```bash
cd ios
xcodegen generate
xcodebuild -project WhaleAgent.xcodeproj -scheme WhaleAgent \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
xcodebuild -project WhaleAgent.xcodeproj -scheme WhaleAgentSideload \
  -sdk iphoneos -configuration Release archive -archivePath build/WhaleAgent.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

GitHub Actions：
- `ios-simulator-build.yml`：模拟器编译 + 原生单元测试。
- `ios-sideload-ipa.yml`：无签名 IPA，供 AltStore / SideStore 重签安装。

本版本构建记录（2026-11-09）：

| 项 | 值 |
|---|---|
| 提交 | `b4ce3a2` |
| 模拟器构建 + 单元测试 | run `42620159382`，`TEST SUCCEEDED`，8/8 |
| 免费签名 IPA | run `42620159339`，`ARCHIVE SUCCEEDED` |
| 产物 | `WhaleAgent-Sideload.ipa`，449,270 字节 |
| SHA256 | `53B7399D97C380BC382468643692FF87AB264760E86866E68A1A36EBAAE9EA27` |
| 版本 | `0.3.0 (9)`，Bundle ID `com.whale01.whaleagent.alt` |
| 扩展 | `Payload/WhaleAgent.app/PlugIns/WhaleAgentShare.appex` |

## 3. 配置模板

后端 `backend/.env`：

```dotenv
DEEPSEEK_API_KEY=sk-***
DEEPSEEK_MODEL=deepseek-chat
EXECUTION_MODE=ios          # 真机验收时必须为 ios
PORT=8787
```

讯飞（不写入仓库；通过 Info.plist 注入或 Xcode Build Setting）：

```text
XFYUN_APP_ID=...
XFYUN_API_KEY=...
XFYUN_API_SECRET=...
```

未配置时 App 明确显示“讯飞语音未配置（使用系统听写）”，不会伪装成讯飞结果。

## 4. 安装（免费签名）

1. GitHub Actions 下载 `WhaleAgent-Sideload.ipa`。
2. AltStore / SideStore 重签安装（Team `4SS886JF5H`）。
3. 首次启动授权提醒、日历、定位、通讯录、麦克风、语音识别。
4. 后端地址使用电脑局域网 IP，手机与电脑同一网络。

## 5. TestFlight 准备

- 需要 Apple Developer Program Team、App ID、描述文件与 App Store Connect 记录。
- 分享扩展需为两个 Bundle ID 同时启用 App Group（主 App 与非免费签名构建）。
- 免费签名构建不启用 App Group，分享内容通过 `whaleagent://share` URL 交接。
- 发布前执行 `测试报告.md` 的 P0 用例并附真实设备记录。

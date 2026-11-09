# AltStore / SideStore 真机安装路线

适用场景：暂时没有付费 Apple Developer 账号，但要先把 App 装进 iPhone 做真机验收。

## 结论

可行，但必须使用单独的“免费签名”构建：

- Bundle ID：`com.whale01.whaleagent.alt`
- Scheme：`WhaleAgentSideload`
- Entitlements：`WhaleAgent-Sideload.entitlements`（空，不申请受限能力）
- 编译条件：`FREE_SIGNING`
- CI 产物：未签名 `WhaleAgent-Sideload.ipa`，由 AltServer / SideStore 用免费 Apple ID 重签

免费 Apple ID 的限制：

- 证书与描述文件 7 天过期，需要续签。
- 同一 Apple ID 最多同时安装 3 个自签 App。
- 每周最多注册 10 个 App ID。
- 不支持 HealthKit、WeatherKit、App Groups、推送通知等受限能力。

因此免费版会禁用“天气”和“运动摘要”，返回明确的 `unavailable_in_free_build`，不会崩溃，也不会伪装成成功。提醒、日历、地点、导航、联系人、短信草稿、音乐仍保留。

## 已完成的工程改动

- `ios/project.yml` 新增 `WhaleAgentSideload` target 与 scheme。
- 新增空 entitlements 文件，避免安装时因缺少 HealthKit / WeatherKit 能力被拒。
- `NativeToolRouter` 在 `FREE_SIGNING` 下拦截天气与运动摘要。
- `PermissionCenter` 在免费版把运动数据标记为“免费签名不可用”。
- 新增工作流 `.github/workflows/ios-sideload-ipa.yml`，在 `macos-15` 上构建未签名设备 IPA 并上传 artifact。

## 第一步：拿到 IPA

1. 推送包含 `ios/**` 的提交，或在 GitHub Actions 手动运行 `iOS Sideload IPA`。
2. 等待 job 绿色，确认日志包含 `BUILD SUCCEEDED` 和 `lipo -info` 输出 `arm64`。
3. 下载 artifact `WhaleAgent-Sideload-ipa`，解压得到 `WhaleAgent-Sideload.ipa`。

## 第二步：Windows 准备

1. 安装 Apple 官网版 iTunes 和 iCloud（不要用 Microsoft Store 版本）。
2. 从 <https://altstore.io> 安装 AltServer，登录 Windows 后托盘出现 AltServer 图标。
3. iPhone 打开“设置 → 隐私与安全性 → 开发者模式”，重启并确认开启。
4. 电脑与 iPhone 连接同一 Wi-Fi；Windows 防火墙放行 AltServer。
5. 后端使用局域网地址（当前默认 `http://10.219.86.103:8787`），并放行 8787 / 8790 端口。

## 第三步 A：用 AltStore 安装

1. AltServer 托盘菜单 → `Install AltStore` → 选择 iPhone → 输入 Apple ID 与专用密码。
2. iPhone 上信任开发者证书：设置 → 通用 → VPN 与设备管理。
3. 打开 AltStore → `My Apps` → 左上角 `+` → 选择 `WhaleAgent-Sideload.ipa`。
4. 安装完成后首次启动，按提示授予提醒、日历、定位、通讯录、音乐权限。
5. 7 天到期前，保持 AltServer 在同一 Wi-Fi 且电脑开机，AltStore 会自动或手动刷新。

## 第三步 B：用 SideStore 安装

SideStore 适合不想长期开着电脑的场景，但首次安装仍需要电脑辅助。

1. 先用 AltServer 安装 SideStore，或按 SideStore 官方文档用 `iloader` 安装。
2. 在 Windows 生成 pairing file，并导入 iPhone 上的 SideStore。
3. 安装并开启 StosVPN，导入 pairing file，保持 VPN 连接。
4. SideStore 内登录 Apple ID，安装 `WhaleAgent-Sideload.ipa`。
5. 之后可在设备上自动续签，仍受 7 天与 3 个 App 限制。

## 第四步：免费版真机验收顺序

1. App 能安装、启动，设置页能保存后端地址并通过连接测试。
2. 创建提醒 → 打开系统“提醒事项”确认真实写入 → 等到点确认通知。
3. 相同请求重复提交，确认真实系统里只有一条记录。
4. 查询日历、创建日历事件，确认时区与全天事件正确。
5. 地点搜索与地图导航交接。
6. 联系人解析与短信草稿，确认发送/取消回调。
7. 音乐搜索、播放、暂停、继续、切歌。
8. 请求天气或运动摘要，确认返回“免费签名不可用”，不崩溃、不编造数据。
9. 断网、切后台再回来，记录当前失败表现（该能力尚未实现）。

## 与 TestFlight 的关系

AltStore / SideStore 只用于当前真机验收，不等于正式交付：

- 不能替代 TestFlight。
- 不能使用 HealthKit / WeatherKit。
- 7 天续签不适合外部测试用户。
- 正式 Beta 仍需付费 Apple Developer 账号、证书、描述文件和 App Store Connect。

免费路线跑通后，付费账号到位时直接切换到 `WhaleAgent` scheme 和正式 Bundle ID，代码不需要重写。

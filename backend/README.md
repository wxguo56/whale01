# 代号鲸鱼01 服务端

用途：在 Windows 上验证真实 DeepSeek 自然语言理解、工具决策、会话状态与设备执行编排。它不是 iOS 工程，也不替代 EventKit、HealthKit、MusicKit 或真机验收。

当前边界必须分开表述：

- **模型链路：真实 DeepSeek**。网页输入经后端到达 `deepseek-chat`。
- **工具执行：默认真实设备模式**。服务端只做工具编排，系统能力由手机执行；只有显式设置 `EXECUTION_MODE=mock` 时才使用 `MockDeviceExecutor` 做测试演示。

## 运行

```powershell
cd F:\VS_t\代号鲸鱼01\backend
npm run demo
npm test
```

零第三方依赖，Node.js 20+。首次运行会在 `backend/data/` 写入演示与操作日志，该目录已被 Git 忽略。

## DeepSeek 配置

把本地配置放在 `backend/.env`，该文件已被 `.gitignore` 忽略，不要提交、不要写入前端或文档。

```dotenv
MODEL_MODE=deepseek
EXECUTION_MODE=ios          # 真机使用必须为 ios；mock 仅用于本地测试
DEEPSEEK_API_KEY=<在本地安全填写>
DEEPSEEK_MODEL=deepseek-chat
HOST=0.0.0.0
PORT=8787
```

启动时会自动读取 `backend/.env`。也支持用系统环境变量覆盖。`GET /healthz` 只返回是否已配置，不返回密钥。

## 访问码与身份归属

在 `backend/.env` 配置 `WHALE_AUTH_TOKENS`（英文逗号分隔）后，所有 `/v1/*` 请求都必须带 `Authorization: Bearer <token>`，`/healthz` 保持公开。每个 Token 对应一个独立 owner；会话、任务快照、确认和工具结果都会校验 owner，另一个 Token 不能读取、确认或提交不属于它的任务。

```dotenv
WHALE_AUTH_TOKENS=phone-token,test-token
```

App 端在「设置 → 后端访问码」填写对应 Token。Token 轮换后旧会话会返回 403，App 会自动开启新会话。

## 启动 HTTP 服务

```powershell
cd F:\VS_t\代号鲸鱼01\backend
node src/server.mjs
```

健康检查：

```powershell
Invoke-WebRequest http://127.0.0.1:8787/healthz -UseBasicParsing
```

正常应包含：

```json
{
  "status": "ok",
  "modelMode": "deepseek",
  "executionMode": "ios",
  "adapterConfigured": true,
  "tools": 15,
  "contractVersion": "1.0"
}
```

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | 运行模式、模型配置状态、契约版本、工具数量与调用上限 |
| POST | `/v1/turns` | 开始一轮任务；`Accept: text/event-stream` 时按 SSE 返回 |
| POST | `/v1/turns/:id/confirm` | 对 `operationId` 确认或取消；确认才执行写工具 |
| POST | `/v1/turns/:id/tool-results` | 为真机执行预留的结果回传入口 |
| GET | `/v1/turns/:id` | 读取当前任务快照 |
| GET | `/v1/conversations/:id` | 读取会话消息、任务与候选上下文 |
| DELETE | `/v1/conversations/:id` | 重置会话 |

请求示例：

```json
{
  "text": "明天下午三点提醒我取快递",
  "now": "2026-11-09T10:00:00+08:00",
  "timezone": "Asia/Shanghai",
  "conversationId": "conv_demo_0001",
  "autoConfirm": false,
  "permissions": {
    "reminder": "granted",
    "calendarRead": "granted",
    "calendarWrite": "granted",
    "music": "granted",
    "location": "granted"
  }
}
```

## 已实现

- 真实 DeepSeek 非流式工具调用；长期密钥只从后端 `.env` 读取。
- 15 个工具契约：提醒、日历查询／创建、天气、健康摘要、地点、导航、分享内容总结、短信草稿、6 个音乐工具。
- 能力表区分 `available`、`needs_authorization`、`not_implemented`，只有可用工具会暴露给模型。
- 会话级消息历史、活动任务、候选曲目、播放状态、天气与日程结果。
- 待补任务、待确认任务、修改后旧确认失效、取消未执行任务、口头确认不替代任务卡确认。
- 说话缺时刻或缺少上午／下午时的服务端硬拦截；模型不能自行补造 09:00 或 15:00。
- 用户明确命令动作但模型只回文字时，Agent 会要求模型重新调用工具，避免“只说不做”。
- `operationId` 去重、`started` 状态返回 `execution_unknown`、模型调用与工具批次上限。
- Mock 设备结果全部带 `simulated: true`；音乐结果额外带 `audioOutput: false`。

## 基准与测试

```powershell
cd F:\VS_t\代号鲸鱼01\backend
node --test
node scripts/eval-conversation.mjs
```

当前结果：

- 单元／集成测试：40 项通过。
- 真实 DeepSeek 自然对话基准：30 组，确定性检查 30/30。
- 本轮新增回归：转话题前取消待确认任务；“换一首”不得重复调用同一工具；同一轮重复的成功动作由后端确定性去重。
- 报告：`../quality/reports/conversation-eval.latest.md` 与 `.json`。

确定性检查只覆盖工具轨迹、参数和任务状态；`must`／`mustNot` 仍需人工复核。不能把 30/30 表述为所有真实系统能力已通过。

## 已知限制

- DeepSeek 上游仍为非流式请求；SSE 已能按事件下发，但上游流式工具参数组装未完成。
- Mock 设备不是 EventKit／MusicKit／HealthKit，不能作为真机证据。
- 音乐只有演示曲库与模拟播放状态，没有真实音源，也不读取 iPhone 音乐库。
- 天气、健康、地点、日历均为固定 Mock 数据。
- 未实现讯飞 ASR/TTS 代理，麦克风仍为网页模拟。
- 没有 iOS 工程、macOS、Xcode、签名与真机环境，原生验收被阻断。

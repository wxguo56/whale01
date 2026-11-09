# 代号鲸鱼01 服务端骨架

用途：在 Windows 上先冻结契约、验证 Agent 循环与写操作幂等。它不是 iOS 工程，也不替代真机 EventKit 验证。

## 运行

```powershell
cd F:\VS_t\代号鲸鱼01\backend
npm run demo
npm test
```

零第三方依赖，Node.js 20+。首次运行会在 `backend/data/` 写入演示数据，该目录已被忽略。

## 启动 HTTP 服务

```powershell
$env:MODEL_MODE = "mock"
npm start
```

接入真实 DeepSeek：

```powershell
$env:MODEL_MODE = "deepseek"
$env:DEEPSEEK_API_KEY = "<在安全环境中设置>"
$env:DEEPSEEK_MODEL = "deepseek-chat"
npm start
```

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | 运行模式、契约版本、调用上限 |
| POST | `/v1/turns` | 开始一轮任务；`Accept: text/event-stream` 时按 SSE 流式返回 |
| POST | `/v1/turns/:id/confirm` | 对 `operationId` 确认或取消 |
| POST | `/v1/turns/:id/tool-results` | 真机执行后回传工具结果（配合 `deferExecution`） |
| GET | `/v1/turns/:id` | 读取当前任务快照 |

请求示例：

```json
{
  "text": "明天下午三点提醒我取快递",
  "now": "2026-11-09T10:00:00+08:00",
  "timezone": "Asia/Shanghai",
  "autoConfirm": false
}
```

## 已实现

- 工具白名单、JSON Schema 参数校验、未知工具不执行。
- DeepSeekAdapter 与 Mock 模型适配器，长期密钥只从后端环境读取。
- 服务端生成稳定 `operationId`；本地操作日志去重，`started` 状态返回 `execution_unknown`。
- 确认事件、取消、模型调用 5 次与工具批次 3 次上限。
- SSE 事件流与 JSON 两种返回方式。
- Mock 设备执行器落盘提醒，作为无 Mac 时的端到端演练。

## 已知限制

- 上游 DeepSeek 暂用非流式请求；契约已支持逐事件下发，流式工具参数组装仍属 W01-009 待办。
- Mock 设备不是 EventKit，不能作为真机证据。
- 无语义模型；Mock 只解析提醒场景，相对日期解析覆盖今天/明天/后天与大后天。
- 未实现讯飞 ASR/TTS 代理，相关子任务仍为待外部条件。

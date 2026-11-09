# 契约 v1.0（冻结候选）

本目录是 W01-003「工具与事件契约」的交付物。契约版本为 `1.0`，任何破坏性修改必须升主版本并同时更新样例与解码测试。

| 文件 | 用途 |
|---|---|
| `v1/tools.v1.json` | 工具目录：名称、所属 Skill、授权与确认策略、输入 JSON Schema |
| `v1/tool-definition.schema.json` | 工具定义本身的 Schema，用于校验目录文件 |
| `v1/events.v1.json` | 服务端到客户端的任务事件信封与类型 |
| `v1/examples/` | 创建提醒的工具请求、工具结果与事件流样例 |

## 解码规则

- 未知字段：忽略，不因新增可选字段导致解码失败。
- 未知事件 `type`：记录并跳过，不改变当前任务状态。
- 未知工具名：不执行，返回 `unsupported`，并作为工具结果回传给模型。
- `contractVersion` 主版本不一致：拒绝该消息，要求客户端升级或降级协商。
- 所有时间使用带偏移的 ISO 8601（例如 `2026-11-10T15:00:00+08:00`），同时携带 IANA 时区名。
- `operationId` 由服务端可信编排层生成；重试必须复用同一个值。`toolCallId` 是模型供应商的调用标识，两者不混用。

## ToolResult 状态

`success`、`failed`、`needs_input`、`needs_authorization`、`needs_confirmation`、`opened_external_app`、`execution_unknown`、`cancelled`、`unsupported`。

只有 `success`、`opened_external_app` 可以作为完成依据；`needs_*` 表示任务暂停等待用户或系统条件。

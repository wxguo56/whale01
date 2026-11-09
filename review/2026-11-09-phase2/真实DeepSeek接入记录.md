# 第二阶段：真实 DeepSeek 接入记录

日期：2026-11-09｜范围：`backend/`、`web/`、`quality/`｜结论：真实模型理解已接入，工具执行仍为 Mock

## 1. 本轮结论

- `modelMode=deepseek`：网页自然语言经后端真实调用 `deepseek-chat`，不是固定模板或规则路由。
- `executionMode=mock`：提醒、日历、天气、健康、地点、导航、短信草稿与音乐全部由 `MockDeviceExecutor` 模拟，未写入真实系统，未产生真实音频。
- 真实 DeepSeek 30 组自然对话基准：确定性检查 30/30。
- 后端单元／集成测试：40 项通过。
- 尚未完成：讯飞语音、EventKit／HealthKit／MusicKit 原生执行、iPhone 真机验收、GitHub 远端推送。

本记录不把“模型理解正确”写成“工具真实执行成功”，也不把 HTML 模拟写成 iOS App 已交付。

## 2. 配置与密钥安全

| 项目 | 实际配置 |
|---|---|
| 模型模式 | `MODEL_MODE=deepseek` |
| 执行模式 | `EXECUTION_MODE=mock` |
| 模型 | `deepseek-chat` |
| 密钥位置 | 仅 `backend/.env`，由后端启动时读取 |
| Git 状态 | `.gitignore:4` 已忽略 `backend/.env`，未进入暂存区 |
| 前端 | 不包含密钥；设置页只显示模型名与执行模式 |

`/healthz` 脱敏返回：

```json
{
  "status": "ok",
  "modelMode": "deepseek",
  "executionMode": "mock",
  "adapterConfigured": true,
  "tools": 15
}
```

未在界面、日志、报告或提交中输出完整 API Key。若需更换密钥，只修改 `backend/.env` 并重启后端。

## 3. 真实模型链路

### 3.1 请求路径

1. 网页把用户文本、`conversationId`、时区与设备时间发送到 `POST /v1/turns`。
2. 后端组装系统提示词：角色约束、当前能力事实、设备时间、默认城市、活动任务、最近候选与播放状态。
3. 后端调用 DeepSeek `deepseek-chat`，只下发当前可用的工具白名单。
4. 模型返回工具请求后，后端校验工具名、参数、授权与确认策略，再交由 Mock 执行器。
5. 最终回复以本轮 `tool.result` 为准；写操作成功前必须经过任务卡确认。

### 3.2 实际验证

| 场景 | 输入 | 实际轨迹 | 结果 |
|---|---|---|---|
| 完整提醒 | 明天下午三点提醒我取快递 | `create_reminder` → 确认卡 | 真实模型解析 11月10日 15:00；确认前不写入 |
| 缺时刻 | 明天提醒我取快递 | `create_reminder` 被硬拦截为 `missing_time` | 追问具体时间，不默认 09:00 |
| 缺上午下午 | 明天三点提醒我取快递 | `create_reminder` 被硬拦截为 `missing_period` | 追问上午还是下午 |
| 修改待确认 | 改成后天下午四点，其他不变 | 新 `create_reminder` + 新 `operationId` | 旧确认失效，生成新预览 |
| 能力询问 | 你都有什么技能 | 无设备工具 | 按能力表区分已实现、需授权与未实现 |
| 天气 | 明天会不会下雨 | `get_weather` | 返回 Mock 天气并标注模拟 |
| 日历未授权 | 明天下午有什么安排 | 无设备工具 | 说明需要日历读取授权，不换工具探查 |
| 音乐 | 我想听歌 → 第二首 → 暂停 | `search_music_library` → `play_music` → `pause_music` | 候选、播放、暂停状态均来自 Mock |
| 资料内指令 | 总结分享内容 | `summarize_shared_content` | 只总结，不执行正文指令 |
| 改话题 | 先不管提醒了，查一下明天杭州天气 | `cancel_active_task` → `get_weather` | 旧提醒取消，天气正常返回 |

## 4. 30 组基准

报告入口：

- `quality/reports/conversation-eval.latest.md`
- `quality/reports/conversation-eval.latest.json`
- 用例定义：`quality/conversation-cases.v1.json`

运行命令：`cd backend; node scripts/eval-conversation.mjs`

结果：30 组全部通过确定性检查。覆盖能力询问、普通交流、完整与口语提醒、两轮补参数、修改与取消、指代不明、天气、日历授权、健康无数据、音乐选曲与播放控制、未知执行状态、缺少修改工具、切换话题、可信确认来源与资料内指令。

报告明确区分：

- 确定性检查覆盖工具轨迹与参数。
- `must／mustNot` 语义项由人工复核，不能把自动报告当作真实模型总成绩。
- Mock 执行结果带 `simulated:true`；音乐结果另带 `audioOutput:false`。

## 5. 第一阶段六个复核项闭环

第一阶段评审见 `review/2026-11-09-phase1/第一阶段HTML评审.md`。本轮保持修复不回退：

| 编号 | 修复结果 | 可复核证据 |
|---|---|---|
| R01 追问后继续原任务 | 保存待补提醒的标题、日期与缺失字段；补“下午三点”恢复为 15:00 确认卡；取消后补时间不复活 | `web/app.js` 待补任务路径；H23／H24 |
| R02 日历与提醒权限分离 | 提醒、日历读、日历写、音乐库分别建模；拒绝提醒权限不影响日历状态 | H25／H26；设置页分组 |
| R03 修改生成新操作身份 | 旧操作标记 `superseded`，旧卡移除操作按钮；新参数生成新 `operationId` | H20；事件日志 `operation_superseded_by_edit` |
| R04 首页健康摘要四态同步 | `none／has／loading／error` 共用同一状态源；首页、设置、侧栏与对话一致 | H27 |
| R05 44px 点击目标 | 顶栏、常用入口、设置动作与场景分段扩展到约 44×44；390px 无横向溢出 | H33 与视觉检查 |
| R06 导航单层确认 | 选定地点后只经一层“打开地图”确认；副标题为“交接前预览”，不声称已开始路线 | H13 |

## 6. 本轮新增修正

### 6.1 转话题时残留旧任务

原问题：输入“先不管提醒了，查一下明天杭州天气”时，模型只查天气，旧提醒仍保持待确认。

修正：

- 系统提示词把“先不管／先放着／先不处理”纳入 `cancel_active_task` 场景。
- 明确要求先取消未执行任务，再处理新请求。
- 基准 `NLQ-028` 断言必须同时出现 `cancel_active_task` 与 `get_weather`。
- 新增集成测试验证任务最终为 `cancelled`，天气工具正常返回。

复测回复：先说明旧提醒已取消，再返回杭州天气；不再在末尾继续追问旧任务。

### 6.2 “换一首”重复调用

原问题：`NLQ-024` 曾出现两次 `skip_music_track`，导致一次口语请求前进两首。

修正：

- 提示词要求同一句用户动作默认只调用一次对应工具。
- 拿到切歌、暂停、继续的 `tool.result` 后直接回复，不重复调用同一工具确认状态。
- 基准新增 `noDuplicateTools` 检查。

复测轨迹：`skip_music_track` 一次，随后 `get_playback_state` 核对状态；无重复切歌。

### 6.3 暂停仍被模型调用两次

浏览器复测“暂停”时发现：提示词已经要求只调用一次，但模型仍在同一轮再次调用 `pause_music`，第二次因已暂停而返回失败卡。

修正：

- 后端对写操作与播放控制增加同轮成功动作签名去重。
- 相同工具、相同参数在成功执行后再次出现时，只回传一条 `deduplicated:true` 的工具消息给模型，不再执行、不再渲染失败卡。
- 新增集成测试：同一轮连续两次 `pause_music` 只产生一次 `tool.result`。

复测：浏览器点“暂停”只有一条 `pause_music · success`，回复为“已确认暂停”，无“当前没有正在播放的音乐”失败卡。

### 6.4 Web 本地取消吞掉合并请求

原问题：Web 的本地纯取消捷径匹配“先不”前缀，可能把“先不管提醒了，查一下明天杭州天气”整句吞掉，只取消旧任务而不查天气。

修正：

- 本地捷径只处理短句、无逗号、且不含新请求关键词的纯取消。
- 合并请求交给后端模型，由 `cancel_active_task` + `get_weather` 完成。
- 收到 `cancel_active_task` 成功结果时，Web 同步把旧确认卡标为“已取消”，避免旧卡继续可点。

复测：旧提醒卡变“已取消”，随后出现“取消任务”和“查询天气”两张结果卡。恢复后端后点“重新连接”，顶部状态回到“待命”。

## 7. 测试与证据

| 项目 | 命令 | 结果 |
|---|---|---|
| 语法检查 | `node --check src/prompt.mjs` 等 | 通过 |
| 后端测试 | `cd backend; node --test` | 40 / 40 通过 |
| 真实模型基准 | `cd backend; node scripts/eval-conversation.mjs` | 30 / 30 确定性通过 |
| 健康检查 | `GET /healthz` | `deepseek / mock`，15 个工具 |
| 密钥忽略 | `git check-ignore -v backend/.env` | 命中 `.gitignore:4` |

## 8. 未完成与边界

1. DeepSeek 上游仍为非流式请求；SSE 已按事件下发，但上游流式工具参数尚未组装。
2. 所有设备动作仍是 Mock；EventKit、HealthKit、MusicKit、定位与 MessageUI 未接入。
3. 没有 iOS 工程、macOS／Xcode、签名与真机条件，原生验收未开始。
4. 讯飞产品与凭据未配置，NL-08 未开始。
5. GitHub 远端推送缺凭据；本地 `main` 与 `release/` 已就绪，未在未授权情况下推送。
6. 真实模型语义仍需人工复核；自动基准只证明工具轨迹与参数符合预期。

## 9. 下一步

1. 按 `web/真机验收清单.md` H33–H39 补做 iPhone Safari 验收。
2. 用丹青约定稿视觉后统一原生还原，不重做当前已验证的对话状态机。
3. 获取讯飞凭据后接入 NL-08，文字与语音共用同一 Agent。
4. 有 iOS 工程与真机后实现 EventKit／HealthKit／MusicKit 执行器，再执行真实工具验收。
5. 获得 GitHub 凭据后再推送远端与生成正式发布包。

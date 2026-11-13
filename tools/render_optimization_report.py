from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'review/optimization-2026-11-13'
data = json.loads((folder / '实施状态.json').read_text(encoding='utf-8-sig'))
lines = [
    '# 代号鲸鱼01 · 优化实施报告', '',
    f'本轮从 `{data["baseline"]}` 开始实施。候选源码 `{data["candidate"]}`，App 版本 **{data["version"]}（{data["build"]}）**。', '',
    '重点落到执行可靠性、数据新鲜度、音频和发布身份。既有股票图表裁切、中文资讯、知乎热榜、每日一句与频道入口继续保留。', '',
    '| 验证 | 结果 |', '|---|---|'
]
for key, label in [('backend','后端回归'),('nativeFinalCandidate','最终候选原生回归'),('ipa','安装包核验'),('ui','界面核验'),('phone','真机')]:
    lines.append(f'| {label} | {data["validation"][key]} |')
lines += ['', '## 用户可以直接体验的变化', '',
    '- 对话中的否定、解释、假设和引用有独立保护；实时回答需要本轮工具证据。',
    '- 待办语音等待识别最终结果；模糊时间保留草稿；删除先核对对象。',
    '- 日历创建/改期先看冲突与改动；确认后内容变化会停止保存。',
    '- 断网或部分来源失败会说明缓存/过期；下拉刷新传到服务端；未知发布时间/行情延迟如实显示。',
    '- 搜索和自选的旧响应被隔离；录音、播报、本地音乐与伙伴音效共用音频协调。',
    '- 极光游灵素材与交互框架保留；按你的最新要求，首页暂不显示，位置与用途确认后再启用。',
    '- 个人 DeepSeek 密钥可保存到本机钥匙串；设置页能查看源码标识、打包时间和模型用量。',
    '', '## 28 项审查问题对应实施', '',
    '“已实施”表示代码已落地，相关回归按上表记录。标注待真机或部分实施的项目不能视为完整验收通过。', '',
    '| 编号 | 状态 | 本轮变化 | 仍需完成 |', '|---|---|---|---|'
]
for item in data['findings']:
    lines.append('| ' + ' | '.join(item[k].replace('|','／').replace('\n',' ') for k in ['id','status','change','remaining']) + ' |')
lines += ['', '## 验证证据', '',
    f'- [iOS 编译与 55 项原生回归]({data["ci"]["native"]})',
    f'- [设备 IPA 归档与身份校验]({data["ci"]["ipa"]})',
    f'- [iPhone 16 Pro 首页截图]({data["ci"]["ui"]})',
    '', f'IPA SHA256：`{data["ipaSHA256"]}`。大小：`{data["ipaBytes"]:,}` 字节。',
    '', '## 安装与核验', '',
    '安装包放在工程 `release/optimization-0.6.4/` 下。安装前对照旁边的 manifest 和 SHA256；安装后到设置页核对源码 SHA。使用 AltStore/SideStore 进行个人签名后安装，成功打包不等于已经安装到手机。', '',
    '本轮没有真实 DeepSeek 收费评测，也没有新建第三方服务账户。讯飞正式链路、网易云授权播放、HealthKit 正式签名、完整任务依赖图与独立鳍尾骨骼仍保留为明确的后续工作。这个个人侧载构建兼容内置服务配置；公开分发检查会拒绝带长期凭据的包。', '',
    '真机步骤见同目录 `真机验收清单.md`；伙伴资产来源与音效边界见 `伙伴素材与实现边界.md`。', ''
]
(folder / '执行报告.md').write_text('\n'.join(lines), encoding='utf-8')
print(str(folder / '执行报告.md'))

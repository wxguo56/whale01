# 鲸鱼助手：三套 UI 与动效 HTML 演示

> **已废弃并停用（2026-11-09）**：下方说明仅为原始记录，不再按其生成或打开旧 UI。当前 index.html 显示停用提示；原独立文件已归档到 design/deprecated-ui-2026-11-09/standalone-demo.html。以 13_UI方案废弃决定.md 为准。

这是会话中「汐屿／星潮／回声」概念方案的独立 HTML 导出，不替换现有首页和业务模拟。

## 打开

现有 web/serve.mjs 运行时访问：

http://127.0.0.1:8088/design-v2/index.html

也可直接打开本目录 index.html。服务未启动时，按 web/README.md 启动已有演示服务。

index.html 已嵌入图标与交互依赖，是约 960KB 的单文件版；可以单独复制给执行者，不依赖外部 CDN。vendor/ 是导出维护缓存，不需要随文件复制。

手机与电脑在同一网络时，使用电脑当前局域网地址，路径保持 /design-v2/index.html；手机里的 127.0.0.1 指手机自身，不能访问这台电脑。不要为了预览关闭防火墙或暴露到公网。

## 可以体验

- 三套方案切换：汐屿、星潮、回声。
- 首页、对话、音乐、我的与确认弹层。
- 角色／光核／唱片触碰、倾听和理解动效。
- 模拟选曲、播放／暂停、迷你播放器和页面历史。
- 大字、减少动效、浅色／深色系统外观。

主设计参考为 iPhone 16 Pro 的 402×874pt；此 HTML 是完整内容预览，不代表原生安全区、键盘或真机适配已经完成。

## 范围

对话、数据、权限与音乐均为 UI 示例；没有调用 DeepSeek 或讯飞，没有真实音源，也不读写 iPhone 数据。

## 更新来源

可编辑源位于当前设计会话的 whale01-three-designs.html。通过 visualize 技能的 render.py 导出完整 HTML 后更新本目录，保留仅用于本地状态的 widgetState／setWidgetState 兼容层，不依赖 Codex 内部动作。

重新 render.py 后，运行 design/systems-v2/pack-offline-demo.cjs 将固定版本资源嵌入导出文件；export-manifest.json 记录版本及来源。使用 design/systems-v2/export-demo-check.cjs 检查 HTTP 入口，使用 --file 检查直接打开。

本轮已验证 HTTP 地址与直接打开文件两种方式；三套方案切换、触碰反馈、确认、音乐模拟、安静模式均通过，未请求外部资源。记录在 design/systems-v2/export-demo-validation.json 与 export-file-validation.json。

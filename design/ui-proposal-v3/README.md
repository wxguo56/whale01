# 新版 UI 设计交付

设计状态：待评审，旧 UI 方案继续停用。

- 设计说明：项目根目录21_新版UI与交互设计方案.md。
- 在线本地预览：http://127.0.0.1:8088/ui-proposal-v3/index.html。
- 独立离线预览：preview.html，单文件内含样式、脚本和矢量素材。
- 可编辑原型：web/ui-proposal-v3/下的index.html、styles.css、app.js。
- 原生参数参考：tokens.json。
- 浏览器验证范围：verification.json，不能替代iPhone真机验收。

更新可编辑原型后，运行 `node design/ui-proposal-v3/build-preview.mjs` 重新生成离线预览。所有执行和数据均为模拟，未连接模型、语音、地图或手机系统。

主布局为402×874pt；预览比例只用于设计展示，不要求原生整体缩放。原生工程使用动态安全区、系统键盘和动态字体；从组件还原，不从手机外壳截图还原。

# 公网部署

App 的正常网络形态是：手机通过公网 HTTPS 访问后端，后端再访问 DeepSeek。  
当前开发期的 `trycloudflare.com` 地址由本机隧道提供，电脑关机或隧道重启后会失效；长期使用请把后端部署到云主机。

## Render

1. 在 Render 新建 Blueprint，选择仓库 `wxguo56/whale01`，它会读取根目录的 `render.yaml`。
2. 在环境变量中填写 `DEEPSEEK_API_KEY` 和 `WHALE_AUTH_TOKENS`，不要提交到 Git。
3. 部署完成后访问 `https://<service>.onrender.com/healthz`，应返回 `status: ok`。
4. 把 `ios/WhaleAgent/Networking/BackendConfig.swift` 的 `defaultBaseURL` 改成该 HTTPS 地址，重新构建 IPA。

免费实例会自动休眠，首次请求可能等待几十秒；需要 7×24 稳定在线时使用付费实例或自有服务器。

## 自有服务器

```bash
docker build -t whale01-backend ./backend
docker run -d --restart unless-stopped \
  -p 8787:8787 \
  --env-file ./backend/.env \
  --name whale01-backend \
  whale01-backend
```

前面放 Nginx/Caddy 终止 HTTPS，并把域名指向该服务。不要直接把 8787 明文暴露到公网。

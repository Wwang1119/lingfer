# 语渡 Lingfer · DeepSeek 代理

[index.js](index.js) 是腾讯 CloudBase HTTP 云函数：接收客户端请求，检查 `X-App-Secret`，再转发到 DeepSeek 的 `/chat/completions` 接口。

## 服务端配置

| 环境变量 | 用途 |
| --- | --- |
| `DEEPSEEK_API_KEY` | DeepSeek API 密钥，仅在服务端配置 |
| `APP_SECRET` | 与客户端共享的访问口令，必须与客户端值一致 |

函数入口为 `index.main_handler`，代码使用 Node.js 内置 `https` 模块，不依赖第三方 npm 包。按 CloudBase 当前控制台支持的 Node.js 运行时部署 `index.js` 并启用 HTTP 访问，使用实际生成的 HTTPS 地址；仓库未包含一键部署配置。

客户端用编译参数 `DEEPSEEK_PROXY_URL` 和 `APP_SECRET` 接入，见[开发说明](../../docs/DEVELOPMENT.md)。

## 请求约定

客户端通常发送 POST，请求包含 `Content-Type: application/json`、`X-App-Secret` 与聊天请求 JSON。当前客户端使用 `deepseek-chat`。函数透传上游响应，OPTIONS 返回 204。

代码中的典型失败响应：

- 500：服务端没有 `DEEPSEEK_API_KEY`。
- 401：缺少共享口令或与服务端不一致。
- 400：请求体不是可解析的 JSON 对象。
- 502：请求上游失败或超时。
- 其他状态可能由 DeepSeek 上游返回。

`APP_SECRET` 会被编译进客户端，适合作为开发阶段的访问门槛，不能替代用户认证、服务端限流及配额管理。正式发布前需单独设计访问控制。

## 检查与验证

语法检查无需模型调用：

```bash
node --check cloudbase/deepseek_proxy/index.js
```

此命令从仓库根目录执行。部署后先验证缺少/错误口令的拒绝响应，再使用自己的开发配置验证一次翻译。真实请求会调用付费模型，运行前核对账号和用量。仓库当前没有该云函数的自动测试，也未在本轮文档整理中调用上游服务。

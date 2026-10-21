# 可选联网 AI

LedgerBox 0.2.2 新增“联网 AI”，0.3.0 继续保留；它**默认关闭**。它不是把 5,643 参数金钱分类器或 15,380 参数财务意图模型改造成大模型，而是让用户自己接一个 OpenAI 兼容的远程接口。

## 能力边界

```text
本地解析 / 金钱小模型：始终离线
联网 AI：用户主动点“发送”才请求远程接口
```

联网 AI 只负责回答记账、分类、预算、消费习惯问题：

- 不会自动读取账本。
- 不会自动上传账本。
- 不会自动写账。
- 不会因为开启联网就替换本地解析器。

远程模型是否“知道实时信息”取决于服务端；本 App 没有实现网页浏览、新闻抓取或行情接口。不要把它宣传成“能实时查全网”。

## 配置

设置 → AI → 联网 AI：

| 字段 | 说明 |
|---|---|
| 允许联网 | 总开关，默认关闭 |
| 接口地址 | HTTPS，OpenAI 兼容 base URL，例如 `https://api.deepseek.com/v1` |
| 模型名称 | 例如 `deepseek-chat`、`gpt-4o-mini` |
| API Key | 只存本机钥匙串，可留空给无鉴权的自建服务 |

App 会把 base URL 自动补成：

```text
{base}/chat/completions
```

如果已经填了完整的 `/chat/completions`，不会再重复拼接。

## 兼容性

请求体是标准 OpenAI Chat Completions：

```json
{
  "model": "deepseek-chat",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "temperature": 0.2,
  "stream": false,
  "max_tokens": 900
}
```

因此可接：

- DeepSeek
- OpenAI
- 兼容 OpenAI 协议的自建网关
- 其他提供 `/chat/completions` 的 HTTPS 服务

不包含任何厂商 SDK，也不包含任何 API Key。

## 安全

- Keychain：`kSecClassGenericPassword`，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。
- API Key 不写 UserDefaults、不写日志、不进仓库。
- 只允许 `https://`，避免明文传输。
- 超时 45 秒；最多带最近 16 条消息。
- 第三方接口会收到你输入的文本；敏感内容请先删除。
- 联网回答只作建议，不自动写账。

## 未验证

- 没有真实 API Key，未做真实账号请求测试。
- 没有真机网络切换、弱网、代理、证书固定测试。
- 不同厂商的返回格式可能有差异；当前只解析 `choices[0].message.content` 字符串。
- 如果接口返回内容审核、限流或余额不足，App 会显示 HTTP 状态和错误消息。

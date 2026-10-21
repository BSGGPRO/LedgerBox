# Windows 环境下的构建与签名边界

本文说明为什么 Windows 不能直接构建 LedgerBox，以及如何在**不接触证书**的前提下，用 macOS 或 GitHub Actions 产出未签名 IPA，最后由你自己完成签名。

> GitHub Actions 已成功完成未签名 archive（run `39568513229`），但本仓库没有做真机安装或签名验证。不要把“archive 成功”说成“已签名”“可安装”。

---

## 1. 为什么 Windows 不行

LedgerBox 使用：

- SwiftUI（iOS SDK）
- Core Data（iOS SDK）
- Apple Charts（iOS SDK）
- Xcode 工程与 iOS 模拟器/真机 SDK

这些依赖 **Xcode + macOS**。Windows 上：

- 没有 Xcode
- 没有 iOS SDK
- 没有 SwiftUI 的 iOS 运行时
- 不能运行 `xcodebuild`
- WSL 也不能构建 iOS App

Windows 可以做：

- 编辑 Swift 源码
- 编辑文档
- 做静态语法/结构检查
- 通过 GitHub Actions 触发 macOS runner
- 接收未签名 IPA 工件

Windows 不能做：

- 本地编译 iOS App
- 本地运行 iOS 模拟器
- 本地生成可安装 IPA
- 本地完成 Apple 签名闭环

---

## 2. 三条可行路径

### 路径 A：GitHub Actions macOS runner（推荐给无 Mac 的用户）

流程：

```text
Windows 编辑/提交
  → GitHub Actions 触发 macOS runner
  → xcodebuild archive CODE_SIGNING_ALLOWED=NO
  → 把 .app 放进 Payload 压缩成未签名 IPA
  → 上传 artifact
  → Windows 下载 artifact
  → 用你自己的证书/工具自签
```

优点：

- 不需要本地 Mac
- 不需要把证书上传到 GitHub
- 产物是未签名 IPA，签名边界清晰

缺点：

- 依赖 GitHub Actions 的 macOS 额度
- 首次构建可能需要几十分钟
- AppIcon 与 Asset Catalog 已随 archive 编译，但未做真机视觉检查
- 未签名 IPA 不能直接安装

### 路径 B：远程 Mac

通过 SSH 或远程桌面使用 Mac：

```bash
xcodebuild \
  -project LedgerBox.xcodeproj \
  -scheme LedgerBox \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/LedgerBox.xcarchive \
  archive \
  CODE_SIGNING_ALLOWED=NO
```

然后在 Mac 上打包未签名 IPA，传回 Windows。

### 路径 C：借用 Mac

在本地 Xcode 打开工程，选择模拟器或真机运行。真机签名使用你自己的 Team。

---

## 3. GitHub Actions 工作流

仓库已加入：

```text
.github/workflows/ios-unsigned.yml
```

它做四件事：

1. Checkout 仓库。
2. 在 `macos-15` runner 上执行 `xcodebuild archive`，并设置 `CODE_SIGNING_ALLOWED=NO`。
3. 把 `.app` 放进 `Payload`，压缩成 `LedgerBox-unsigned.ipa`。
4. 通过 `actions/upload-artifact@v4` 上传工件。

关键边界：

- 工作流不注入证书、描述文件、Team ID 或 App Store Connect 密钥。
- `CODE_SIGNING_ALLOWED=NO` 只表示不签名，不代表已通过 App Store 校验。
- `macos-15` 的可用镜像与 Xcode 版本会变化；如果 runner 没有 iOS 17 SDK，需要调整 runner 或安装指定 Xcode。
- 该工作流已实际运行成功（run `39568513229`）；仍不能据此宣称“已签名”或“可安装”。
- 具体 YAML 以仓库文件为准，本文不复制易过期的完整内容。

---

## 4. 未签名 IPA 的边界

未签名 IPA：

- 可以生成
- 可以下载
- 可以解压检查
- **不能直接安装到普通 iPhone**
- 不能上传 App Store
- 不能通过 TestFlight

要安装到设备，必须使用你自己的：

- Apple Developer 账号
- 证书（`.p12`）
- 描述文件（`.mobileprovision`）
- 对应 Bundle ID
- 自签工具或 Xcode

本项目**不提供**：

- 证书生成
- 证书导出
- Team ID
- 描述文件
- 签名脚本
- 签名后的 IPA
- 绕过 Apple 签名的方案

---

## 5. 自签边界（高层说明）

你可以使用自己信任的工具完成自签，但本项目不提供证书处理步骤，也不接收你的证书。

原则：

1. 只使用你自己的 Apple Developer 账号与证书。
2. 不要从陌生网站下载 `.p12` 或描述文件。
3. 不要把 `.p12`、密码、描述文件上传到 GitHub、网盘或聊天工具。
4. 不要把签名后的 IPA 当作开源产物提交。
5. 自签后能否安装，取决于证书类型、设备 UDID、描述文件有效期与 Bundle ID 匹配。
6. 免费账号签名通常有 7 天限制；付费账号也受证书/描述文件有效期约束。

如果使用第三方签名工具：

- 先确认工具来源可信。
- 不要授予不必要的权限。
- 不要把 Apple ID 密码交给工具。
- 优先使用 Apple Configurator、Xcode 或你信任的成熟工具。

---

## 6. Bundle ID 与签名

当前工程：

```text
主 App：      com.example.ledgerbox
Widget：      com.example.ledgerbox.widget
```

`com.example.*` 只是占位。真机签名/上架前必须改成你自己的唯一 Bundle ID：

- 与描述文件一致
- 与 App Store Connect 记录一致
- 不要与别人的 App 冲突
- Widget 的 Bundle ID 必须是主 App 的子级，并出现在描述文件/App ID 配置中

未签名构建可以保留 `com.example.ledgerbox`；签名前请修改。

### 6.1 默认不嵌入 Widget

0.2.0 当前 IPA 内**没有**：

```text
Payload/LedgerBox.app/PlugIns/LedgerBoxWidget.appex
```

工程仍保留 Widget target 源码，但已从 App 的 Embed 阶段移除，所以 `lcsign` 只需要处理主 App，和你之前能正常安装的单 target 流程一致。

如果以后在 Xcode 里重新加入 Embed 阶段，IPA 会重新出现 `PlugIns/LedgerBoxWidget.appex`。那时必须：

1. 先签 `PlugIns/LedgerBoxWidget.appex`。
2. 再签 `Payload/LedgerBox.app`。
3. 确认两个 Bundle ID、描述文件和 App Group 配置匹配。

只签主 App 会安装失败，典型表现是图标出现但点不开。

---

## 7. 证书与仓库安全

不要提交：

```text
*.p12
*.pfx
*.mobileprovision
*.provisionprofile
*.cer
*.pem
*.key
*.p8
Team ID
App Store Connect API Key
Apple ID 密码
```

`.gitignore` 已包含这些模式，但**忽略规则不是安全边界**。提交前仍要人工检查：

```bash
git status
git diff --cached
```

如果误提交了证书：

1. 立即吊销证书。
2. 重新生成。
3. 从 Git 历史中清除。
4. 检查 CI 日志与 artifact 是否泄露。

---

## 8. 常见问题

### 8.1 `xcodebuild: error: SDK "iphoneos" cannot be located`

- runner 没有安装 iOS SDK
- 选择带 Xcode 的 macOS runner
- 检查 `xcodebuild -version` 与 `xcodebuild -showsdks`

### 8.2 `No signing certificate "iOS Development" found`

- 模拟器构建不需要签名
- 归档时加 `CODE_SIGNING_ALLOWED=NO`
- 真机运行需要你自己的证书

### 8.3 `No profiles for 'com.example.ledgerbox' were found`

- 未签名归档不应要求描述文件
- 如果仍要求，检查是否误开了 Automatic signing 的真机 destination
- 使用 `-destination 'generic/platform=iOS'` + `CODE_SIGNING_ALLOWED=NO`

### 8.4 Archive 成功但 IPA 无法安装

未签名 IPA 本来就不能直接安装。  
需要自签，且 Bundle ID、证书、描述文件、设备 UDID 必须匹配。

### 8.5 App 启动闪退

可能原因：

- Core Data 模型未加入 target
- 旧 store 与模型不兼容
- `@EnvironmentObject ThemeManager` 未注入
- `PersistenceController` 加载失败
- 未签名的二进制被系统拒绝

先在 Xcode 模拟器运行，看控制台错误。

### 8.6 AppIcon / Asset Catalog 报错

仓库已有 `Assets.xcassets` 与 1024×1024 AppIcon 占位，但尚未在 Xcode 中验证。若 Archive 报图标缺失：

- 确认 `Assets.xcassets` 在 target 的 Resources build phase。
- 确认 target 设置包含 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。
- 检查 `Contents.json` 是否合法。
- 检查 PNG 是否为 1024×1024、RGB、无 alpha。
- 上架前仍需做图标视觉审查与截图。

---

## 9. 验收边界

在 Windows 上，你最多可以确认：

- 源码文件存在
- 文档存在
- Swift 语法树可解析
- pbxproj/XML/plist 可解析
- 没有 BOM
- 没有证书/Team ID

你不能在 Windows 上确认：

- Swift 类型检查通过
- SwiftUI 宏展开通过
- Core Data 模型可加载
- App 可启动
- 真机可安装
- App Store 可提交

这些必须在 macOS/Xcode 或 macOS runner 上验证。

---

## 10. 相关文档

- [`BUILD_STEPS.md`](BUILD_STEPS.md)
- [`ACCEPTANCE.md`](ACCEPTANCE.md)
- [`COMPONENTS.md`](COMPONENTS.md)
- [`FINANCE_RULES.md`](FINANCE_RULES.md)
- [`../README.md`](../README.md)

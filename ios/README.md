# 四十八格 · iOS

原生 SwiftUI 版（iOS 26+，Liquid Glass），和网页版共用同一个 Artifact 数据库。

## 装到 iPhone
1. 用 Xcode 打开 `FortyEight.xcodeproj`。
2. 选中 FortyEight target → Signing & Capabilities → Team 选你的 Apple ID（免费账号也行，每 7 天要重新签一次）。如果提示 Bundle ID 被占用，把 `com.chenzishu.fortyeight` 改成别的。
3. 连上 iPhone，选它作为运行目标，⌘R。第一次要在 iPhone 的「设置 → 通用 → VPN 与设备管理」里信任开发者。

## 同步原理
Artifact 数据库没有公开 API，只有 claude.ai 的网页运行时能读写。所以 App 内藏一个 WKWebView：
- 打开 `ArtifactBridge.defaultURL`（你的 Artifact），往 artifact 的 iframe 注入 `relayJS`；
- 脚本调用 `window.claude.use("db")`，把 `days` 和 `memory/profile` 的快照转给原生代码，原生的写入也通过它执行；
- `PlanStore` 维护本地缓存（`Application Support/FortyEight/cache.json`）和写入队列，离线时也能用，连上后补传。

第一次打开要在 App 里登录 claude.ai（用邮箱验证码；嵌入式网页里 Google 登录会被拦截）。依赖 claude.ai 网页现有结构，官方改版后可能需要调整 `relayJS`。

「写计划」和「让 Claude 复盘」会打开内置网页版，因为调用 Claude 需要网页里的授权弹窗。

## 本地测试同步桥
不登录也能测：`Harness/` 里是一个跨域 iframe + 假数据库（内存里，刷新即重置）的测试页。先在 8848 端口起一个静态服务器：
```bash
python3 -m http.server 8848 --bind 127.0.0.1 -d Harness
```
再把 App 的 artifact 地址指过去：
```bash
xcrun simctl spawn booted defaults write com.chenzishu.fortyeight artifactURL http://127.0.0.1:8848/harness.html
```
恢复正式地址：
```bash
xcrun simctl spawn booted defaults delete com.chenzishu.fortyeight artifactURL
```

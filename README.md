# VideoTogether-Mirror

异地同看视频的移动端 App，基于 [VideoTogether](https://github.com/VideoTogether/VideoTogether) 公共同步协议实现。一套代码同时支持 Flutter Android 客户端与 PWA 网页版。

## 功能

- **房间同步**：房主创建房间，成员加入，播放进度/暂停/倍速自动同步
- **视频来源**：在线视频网址（Bilibili、腾讯视频等）或本地视频文件
- **文字聊天**：房间内即时文字消息
- **自动跟随**：成员端自动跳转房主当前视频 URL
- **跨平台**：
  - Flutter Android App（`lib/`）
  - PWA 网页版（`web/`），可添加到 iPhone 主屏
  - 安装用 User Script（`web/vt-lite.user.js`），部署到 Cloudflare Pages

## 下载

- Android APK：[site/public/downloads/app-release.apk](site/public/downloads/app-release.apk)
- PWA 网页版：见 `web/` 目录，可自行部署到任意静态托管

## 技术架构

```
┌─────────────┐    evaluateJavascript     ┌──────────────────┐
│  Flutter UI │ ─────────────────────────► │  assets/vt-lite  │
│ (Dart, lib/)│ ◄───────────────────────── │  .js (同步脚本)   │
└─────────────┘    flushEvents 轮询事件     └────────┬─────────┘
                                                     │ WebSocket
                                                     ▼
                                    ┌────────────────────────────┐
                                    │ VT 公共服务器               │
                                    │ wss://vt.panghair.com:5000 │
                                    └────────────────────────────┘
```

- **`assets/vt-lite.js`**：VideoTogether 协议精简版实现，房主 2 秒上报 / 成员心跳 / 自动重连 / 事件队列
- **`lib/vt/`**：Dart 侧 VT 协议封装，通过 WebView 与 VtLite JS 通信
- **`lib/state/room_store.dart`**：房间状态机，ChangeNotifier + 事件流合并
- **`lib/ui/watch_page.dart`**：观影页，WebView + 房间顶栏 + 聊天浮层

## 开发

```bash
# 安装依赖
flutter pub get

# 调试运行
flutter run

# 构建 release APK
flutter build apk --release

# 运行测试
flutter test
```

## 协议来源

本项目的 WebSocket 同步协议逆向自 VideoTogether 开源仓库
[VideoTogether/VideoTogether](https://github.com/VideoTogether/VideoTogether)，
协议调研文档见 [docs/notes/vt-api.md](docs/notes/vt-api.md)。

本项目与 VideoTogether 原项目无从属关系，仅复用其公共同步服务器与协议规范。

## License

[CC BY-NC 4.0](LICENSE) — 禁止商业使用。

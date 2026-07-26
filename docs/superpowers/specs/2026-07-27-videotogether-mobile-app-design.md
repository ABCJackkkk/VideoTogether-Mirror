# 异地同看视频 App 设计文档

- **项目名称**：avideotogether
- **设计日期**：2026-07-27
- **状态**：待用户复核
- **作者**：用户与 TRAE 协作

---

## 1. 项目概述

做一款 Flutter 移动 App，让不同地区的朋友能一起看网页视频。用户粘贴一个视频网址，创建房间或加入朋友房间，App 内的 WebView 打开网页并注入 VideoTogether（VT）开源客户端 JS，由 VT 完成 `<video>` 元素控制与跨端同步。文字聊天复用 VT 服务器；语音连麦不在 MVP 范围。

**核心思路**：最大化复用 VideoTogether 现有生态（开源 JS + 公共服务器），自己只写 Flutter 外壳与 UI，不搭服务器、不写同步协议。

## 2. 需求

### 2.1 功能需求

| 编号 | 需求 | MVP |
|---|---|---|
| F1 | 粘贴视频网址，进入观影页 | ✅ |
| F2 | 创建房间（拿到房间号） | ✅ |
| F3 | 输入房间号加入朋友房间 | ✅ |
| F4 | 视频同步：播放/暂停/跳转/倍速 自动同步房间内所有人 | ✅ |
| F5 | 文字群聊（房间内发消息、收消息） | ✅ |
| F6 | 顶栏：房间号、成员数、复制邀请 | ✅ |
| F7 | 离开房间 | ✅ |
| F8 | 语音连麦 | ❌ 后续 |
| F9 | 本地视频文件同步播放 | ❌ 后续 |
| F10 | 房间密码、踢人、房主权限 | ❌ 后续 |
| F11 | 用户账号系统 | ❌ 后续 |
| F12 | 历史记录、收藏 | ❌ 后续 |

### 2.2 非功能需求

- **平台**：Android + iOS（Flutter 一套代码）
- **成本**：零服务器搭建成本（复用 VT 公共服务器）
- **维护**：不维护任何后端服务
- **目标用户规模**：单个房间 2-10 人，私人房间，无公开房间列表
- **视频源**：任意含 HTML5 `<video>` 元素的网页通用适配（不强承诺每站都能用）

## 3. 整体架构

```
┌─────────────────────────────────────────────────┐
│  Flutter App (avideotogether)                    │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │  UI 层（Flutter widgets）                │   │
│  │  · 首页：粘贴视频网址 / 输入房间号加入    │   │
│  │  · 观影页：WebView 铺满 + 悬浮聊天面板    │   │
│  │  · 顶栏：房间号、成员数、复制邀请按钮     │   │
│  └──────────────────────────────────────────┘   │
│                      │                           │
│  ┌──────────────────────────────────────────┐   │
│  │  WebView 控制层                           │   │
│  │  · flutter_inappwebview 包               │   │
│  │  · 加载用户输入的视频网址                 │   │
│  │  · 网页加载完且 <video> 出现后注入 VT JS  │   │
│  │  · Dart ↔ JS 双向桥                      │   │
│  └──────────────────────────────────────────┘   │
│                      │                           │
│  ┌──────────────────────────────────────────┐   │
│  │  VT 集成层（Dart）                       │   │
│  │  · 房间管理：创建/加入/离开              │   │
│  │  · 通过 JS 桥调用 VT 的 room API         │   │
│  │  · 监听 VT 事件 → 刷新 Flutter UI        │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                      │
                      ▼  WebSocket（VT JS 自动建立）
        wss://api2.videotogether.com
        VideoTogether 公共服务器（复用，零搭建）
```

### 3.1 分层职责

- **UI 层**：纯 Flutter widgets，负责所有界面渲染与用户交互
- **WebView 控制层**：封装 `flutter_inappwebview`，负责网页加载、JS 注入、Dart↔JS 桥
- **VT 集成层**：把 VT 的 JS API 包装成 Dart 接口，向上对 UI 层提供 `createRoom/joinRoom/leaveRoom/sendMessage` 等方法，向下通过 JS 桥调用 VT

### 3.2 关键依赖

```yaml
# pubspec.yaml
dependencies:
  flutter_inappwebview: ^6.0.0   # 比 webview_flutter 更强，支持 JS 注入和双向桥
  # 不需要 firebase、不需要 websocket 库、不需要 webrtc
```

不引入 Firebase / WebSocket / WebRTC 任何后端依赖。

## 4. 核心组件

### 4.1 组件清单

| 组件 | 作用 | 代码来源 |
|---|---|---|
| UI 层 | 首页、观影页、聊天浮层、顶栏 | 自写（纯 Flutter） |
| WebView 控制层 | 加载网址、注入 JS、Dart↔JS 桥 | 自写（调 flutter_inappwebview） |
| VT 客户端 JS | 找 `<video>` 元素、连 VT 服务器、同步状态 | **复用 VT 开源代码**（MIT） |
| VT 集成层 | Dart 调 JS 创建/加入房间、监听事件 | 自写（包装 JS 调用） |
| 聊天浮层 | 半透明悬浮在 WebView 上，发/收消息 | 自写（纯 Flutter） |

### 4.2 Dart ↔ JS 通信机制

```
Dart 调 JS（创建房间）:
  webViewController.evaluateJavascript(
    source: 'window.VideoTogether.createRoom("xxx")'
  )

JS 回调 Dart（成员变化、收到消息）:
  webViewController.addJavaScriptHandler(
    handlerName: 'onVTEvent',
    callback: (args) { /* 更新 Flutter UI */ }
  )
  // 注入的 JS 里:
  // window.flutter_inappwebview.callHandler('onVTEvent', {...})
```

### 4.3 客户端 JS 方案：自写 VtLite（精简同步脚本）

**调研结论**（详见 `docs/notes/vt-api.md`）：VT 的客户端 JS 是带浮动 UI 的完整扩展（3735 行），设计上不为外部调用，强耦合 DOM，没有公开事件订阅机制。直接注入会往 WebView 塞 UI 垃圾且无法干净地收事件。

**采用方案：自写 VtLite 精简脚本**（~200 行），直连 VT 后端 WebSocket 协议。协议已从 VT 源码完整逆向：

- WebSocket 地址：`wss://vt.panghair.com:5000/ws?language=zh-cn`（国内回退 `wss://dogyun.2gether.video/ws`）
- 消息格式：每行一个 JSON，按 `\n` 分割
- 客户端→服务端 method：`/room/join`、`/room/update`（房主上报）、`/room/update_member`、`send_txtmsg`
- 服务端→客户端 method：`/room/update`（广播房间状态）、`send_txtmsg`（收到消息）等
- 时间同步：启动时 `GET /timestamp` 拿服务端时间，计算 offset，用于播放进度外推

**VtLite 暴露的 JS API**（挂在 `window.VtLite`）：
- `VtLite.on(event, callback)` — 订阅事件（`room_update` / `text_message` / `ws_open` / `ws_close`）
- `VtLite.createRoom(name, pwd, videoEl)` — 房主创建房间并启动 2 秒上报循环
- `VtLite.joinRoom(name, pwd, videoEl)` — 成员加入并监听同步
- `VtLite.leaveRoom()` — 离开
- `VtLite.sendText(msg)` — 发文字消息

脚本放入 `assets/vt-lite.js`，观影页检测到 `<video>` 元素后读取并注入（注入时机见 6.2）。注入后通过 `window.flutter_inappwebview.callHandler('vtEvent', ...)` 把事件转发给 Dart。

**优势**：不依赖 VT 客户端代码、无 UI 垃圾、事件订阅干净、代码自己掌控、协议层复用 VT 服务器（零自建后端）。完整骨架见 `docs/notes/vt-api.md` §5.3。

## 5. 数据流

### 5.1 视频同步：一次"暂停"的完整链路

```
用户 A 点 Flutter 里的暂停按钮
   │
   ▼ 1
Dart 调 JS: webViewController.evaluateJavascript(
   source: 'window.VideoTogether.pause()'
)
   │
   ▼ 2
VT JS 找到 <video> 元素，执行 video.pause()
   │
   ▼ 3
VT JS 通过 WebSocket 发给 VT 服务器:
   {action: "pause", time: 120.5, room: "abc123", user: "A"}
   │
   ▼ 4
VT 服务器广播给房间内 B、C
   │
   ▼ 5
B、C 的 VT JS 收到消息 → video.pause() + video.currentTime = 120.5
   │
   ▼ 6
B、C 的 VT JS 回调 Dart:
   window.flutter_inappwebview.callHandler('onVTEvent', {type: 'paused', by: 'A'})
   │
   ▼ 7
B、C 的 Flutter UI 更新：顶栏显示"A 暂停了播放"
```

第 2-5 步 VT 全替你做了，App 只写第 1 步（Dart 调 JS）和第 6-7 步（JS 回调 Dart 刷 UI）。

### 5.2 同步事件清单

| 用户操作 | 远端效果 | 谁处理 |
|---|---|---|
| 播放 | 远端 video.play() | VT JS |
| 暂停 | 远端 video.pause() | VT JS |
| 拉进度条到 5:30 | 远端 video.currentTime = 330 | VT JS |
| 倍速 1.5x | 远端 video.playbackRate = 1.5（站点支持时） | VT JS |
| 网页自己加载/缓冲 | 远端等待，自动追上 | VT JS |
| 进度漂移超 2 秒 | VT 自动校正对齐 | VT JS |

### 5.3 文字聊天数据流

```
A 输入文字 → Dart 调 JS: window.VideoTogether.sendMessage("hi")
   → VT 服务器广播 → B、C 的 JS 收到 → 回调 Dart → Flutter 聊天列表 append
```

### 5.4 三条核心数据流总结

| 动作 | App 写的部分 | VT 替做的部分 |
|---|---|---|
| 暂停/播放/跳转 | Dart 调 1 个 JS 函数 | 找 video 元素 + WebSocket 同步 + 远端执行 |
| 文字聊天 | Dart 调 1 个 JS 函数 + UI 渲染 | WebSocket 广播 + 远端接收 |
| 成员进出 | 监听 JS 回调 + UI 渲染 | 房间管理 + 事件广播 |

## 6. 关键技术点（已知坑与对策）

### 6.1 移动端网页反爬

很多视频站移动版会强制跳 App、检测 WebView UA。对策：

- 伪装桌面 UA，加载桌面版网页（反爬更少，`<video>` 元素更标准）
- 拦截 deep link 跳转（`bilibili://`、`taobao://` 等 scheme 直接 CANCEL）

```dart
InAppWebViewSetting(
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
             '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  shouldOverrideUrlLoading: (controller, action) async {
    final url = action.request.url.toString();
    // 拦截 App 唤起 scheme（bilibili://、taobao:// 等）
    if (!url.startsWith('http')) return NavigationActionPolicy.CANCEL;
    return NavigationActionPolicy.ALLOW;
  },
)
```

### 6.2 VT JS 注入时机

`<video>` 元素可能比 `onLoadStop` 晚出现（懒加载）。对策：onLoadStop 后轮询直到 video 元素出现，再注入 VT JS。最多等 10 秒（20 次 × 500ms），超时提示"未检测到视频"。

```dart
Future<void> _waitForVideoAndInject() async {
  for (var i = 0; i < 20; i++) {
    final has = await webViewController.evaluateJavascript(
      source: '!!document.querySelector("video")'
    );
    if (has == true) {
      await webViewController.evaluateJavascript(source: vtClientJs);
      return;
    }
    await Future.delayed(Duration(milliseconds: 500));
  }
  // 超时提示
}
```

### 6.3 iframe 嵌套

部分视频站用 iframe 套播放器。VT JS 需要能注入到 iframe 内。`flutter_inappwebview` 支持 `shouldInterceptRequest` 拦截 iframe 请求，但同源策略可能限制。**作为已知风险记录**，需在具体站点上实测。

### 6.4 DRM 站点

腾讯视频、爱奇艺、Netflix 等带硬 DRM 的站点，`<video>` 元素内容无法被外部 JS 控制，VT 同步可能失效。**已知限制，不强承诺**。

## 7. 错误处理

按"故障影响范围"分三档处理：

| 故障 | 影响 | 处理 |
|---|---|---|
| 网页加载失败 / 超时 | 看不了视频 | 全屏错误页 + 重试按钮，最多 3 次自动重试 |
| VT 服务器连不上 | 不能同步，但本地能看 | 顶栏黄条提示"同步服务暂不可用"，视频仍可单人播放 |
| 网页里没 `<video>` 元素 | 无法同步 | Toast："未检测到可同步的视频，请确认网页已开始播放" |
| 房间号错误 / 已满 | 加入失败 | VT 返回错误码 → 对应提示（房间不存在/已满/密码错） |
| Dart↔JS 桥断开 | UI 不刷新 | 检测到 WebView 重建 → 重新注入 VT JS + 重新加入房间 |
| WebView 崩溃 | 黑屏 | 捕获异常 → 自动重建 WebView → 恢复到崩溃前的网址和房间 |
| 网络抖动导致同步漂移 | 进度差几秒 | VT 自带漂移修正，无需额外处理；超 2 秒漂移时 Flutter 顶栏提示 |

**核心原则**：本地播放能力与同步能力解耦——同步挂了不影响自己看，只是别人不同步而已。

## 8. 测试策略

| 层 | 方法 | 重点 |
|---|---|---|
| Dart↔JS 桥 | 单元测试 | 消息序列化/反序列化、超时处理 |
| VT 集成层 | 单元测试 | mock JS 桥，验证 Dart 调用序列正确 |
| UI 层 | widget 测试 | 房间创建/加入流程、聊天浮层交互 |
| 同步功能 | 集成测试 | **两台模拟器**开同一房间，A 暂停 → 断言 B 也暂停 |
| 站点适配 | 手动测试矩阵 | 见下表 |

### 8.1 站点适配测试矩阵（MVP 必测）

| 站点 | 测什么 | 预期结果 |
|---|---|---|
| B站 (bilibili.com) | 桌面版网页播放 | ✅ 应该能同步 |
| YouTube | 桌面版网页播放 | ✅ 应该能同步 |
| 腾讯视频 | 桌面版网页播放 | ⚠️ 可能有 DRM，需实测 |
| 优酷 | 桌面版网页播放 | ⚠️ 可能有 iframe 嵌套 |
| 本地任意 mp4 网页 | 简单 `<video>` 标签 | ✅ 必须能同步（基准用例）|

## 9. MVP 范围

### 9.1 MVP 包含

- 首页：粘贴视频网址、创建/加入房间
- 观影页：WebView 全屏播放 + 顶栏（房间号/成员/邀请）+ 聊天浮层
- 视频同步：播放/暂停/跳转/倍速 自动同步
- 文字聊天：群内文字消息
- 双端：Android + iOS

### 9.2 MVP 不包含

- 语音/视频通话
- 本地视频文件播放
- 房间密码、踢人、房主权限
- 历史记录、收藏
- 用户账号系统

## 10. 已知风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| VT 公共服务器关停或封禁 | 同步功能失效 | 本地观看不受影响；后续可切到 Firebase 免费层，改动集中在 VT 集成层 |
| 腾讯/爱奇艺等带 DRM 站点无法同步 | 部分站点不可用 | 已知限制，文档明示；推荐 B站/YouTube |
| iframe 嵌套播放器需逐站适配 | 部分站点需特殊处理 | MVP 先保证 B站/YouTube，其他站点滚动适配 |
| VT 客户端 JS 版本升级协议变化 | 同步失效 | 自打包 JS，锁定版本；手动跟进 VT 升级 |
| 移动端 WebView 与桌面浏览器差异 | 部分网页渲染异常 | 伪装桌面 UA 缓解；用户可手动切换 |

## 11. 后续演进路径（不在 MVP）

1. **语音连麦**：WebRTC P2P，信令走 VT 服务器或 Firebase
2. **切到自建后端**：VT 服务器若不可用，切 Firebase Realtime Database 免费层
3. **本地视频文件**：Flutter 本地播放器 + 自建同步协议
4. **房间权限**：房主、踢人、密码
5. **公开房间**：房间列表、搜索（需后端支持）

---

## 附录 A：决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| 软件形态 | Flutter 移动 App | 用户熟悉 Flutter，跨双端 |
| 视频源 | 任意网页通用适配 | 覆盖面广，符合用户预期 |
| 同步方案 | 复用 VT 公共服务器 + 开源 JS | 零搭建、零维护、个人工具可接受 |
| 后端 | 无自建后端 | 用户预算与维护成本为零 |
| 沟通方式 | 仅文字（MVP） | 简化首版，语音后续加 |
| 房间规模 | 私人房间 2-10 人 | 服务器压力可控，架构简单 |
| JS 获取 | 自打包进 assets | 不依赖 VT CDN，版本可控 |

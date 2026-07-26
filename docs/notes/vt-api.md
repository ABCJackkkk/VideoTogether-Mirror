# VideoTogether 客户端 JS API 调研报告

> 目的：评估在 Flutter App 的 WebView 中注入 VideoTogether（VT）开源客户端 JS、复用其视频同步能力的可行性，并搞清楚 VT 实际暴露了哪些 JS 函数和事件，供后续 Dart 侧调用参考。
>
> 调研基于仓库 `https://github.com/VideoTogether/VideoTogether` 的 `main` 分支（clone 时间 2026-07-27）。

---

## 0. TL;DR（先看结论）

**VT 的客户端 JS 不是为"被外部调用"而设计的。** 它是一个完整的浏览器扩展/userscript，自带一套浮动 UI 面板，所有逻辑都围绕这套 UI 展开。它确实把两个实例挂到了 `window` 上（`window.videoTogetherExtension` 和 `window.videoTogetherFlyPannel`），但：

- 只暴露了 `CreateRoom / JoinRoom / exitRoom` 三个可直接调用的方法，且都依赖浮动面板的 DOM。
- **没有暴露发送文字消息的方法**（`WS.sendTextMessage` 是闭包内的私有对象，不在 `window` 上）。
- **没有任何公开的事件订阅机制**（没有 `onStateChange`、没有 `CustomEvent`）。状态变化通过 `window.postMessage` 在 iframe / top frame 之间传递，但消息协议是内部使用的，没有文档化。
- 整套代码强耦合浮动面板 DOM（`#videoTogetherRoomNameInput` 等），连官方的自动化测试（`test/extension/sync.js`）都是用 puppeteer 操作 shadowRoot 里的 input/button，而不是调 JS 函数。
- 注入后会向页面塞一个浮动 UI（`#VideoTogetherWrapper` + Shadow DOM），在 WebView 里很难隐藏。

**建议方案：不要直接复用 VT 的客户端 JS。** 推荐 **自己写一个精简版同步脚本**，参考 VT 的协议直连 `wss://vt.panghair.com:5000/ws`（或国内回退 `wss://dogyun.2gether.video/ws`），协议见下文第 7 节。这样代码可控、事件可订阅、不依赖任何 DOM。如果时间紧，可先 fork VT 源码做最小改造（暴露 4 个方法 + 1 个事件总线），但长期看自写更省事。

---

## 1. 仓库结构与客户端入口

clone 后的关键目录：

```
.vt-tmp/
├─ source/
│  ├─ extension/
│  │  ├─ vt.js             ← 【核心】客户端主逻辑（3735 行，所有 API 都在这里）
│  │  ├─ extension.js       ← 加载器：负责把 vt.js 注入页面、桥接 GM_* API
│  │  ├─ website_load.js    ← website 模式加载器
│  │  ├─ config/
│  │  │  ├─ release_host    ← 生产 API 主机：https://vt.panghair.com:5000/
│  │  │  └─ debug_host      ← 调试主机：http://127.0.0.1:5001/
│  │  └─ html/pannel.html   ← 浮动面板 HTML（被 vt.js innerHTML 注入）
│  ├─ chrome/               ← Chrome 扩展打包目录
│  ├─ firefox/              ← Firefox 扩展打包目录
│  ├─ safari/               ← Safari 扩展打包目录（含原生 ObjC 工程）
│  └─ go-server/            ← 后端 Go 服务（HTTP + WebSocket）
├─ release/                 ← 编译产物（用户直接安装的 .user.js）
└─ docs/
   ├─ HttpApiSpec.md        ← HTTP API 规范
   └─ zh-cn/development.md  ← 开发文档（很简略）
```

**客户端入口文件**：`source/extension/vt.js`。它是一个 IIFE，被 `extension.js` 通过 `<script src=...>` 注入到页面。注入流程见 `extension.js:511-526`。

**关键源码文件与行号**（下文引用都基于这两个文件）：
- `source/extension/vt.js`
- `source/go-server/service.go` / `source/go-server/ws.go`

---

## 2. 十个问题的明确答案

### Q1. 全局对象名

VT 把自己挂在 **两个** `window` 属性上（`vt.js:3718-3731`）：

```js
window.videoTogetherFlyPannel  // VideoTogetherFlyPannel 类的实例（浮动 UI 面板）
window.videoTogetherExtension  // VideoTogetherExtension 类的实例（主逻辑）
```

> ⚠️ 注意：**不是** `window.VideoTogether`。`window.VideoTogether*` 系列属性（`VideoTogetherStorage` / `VideoTogetherLoading` / `VideoTogetherEasyShare` 等）都是配置/状态变量，不是 API 对象。

类定义位置：
- `class VideoTogetherFlyPannel`：`vt.js:1235`
- `class VideoTogetherExtension`：`vt.js:1851`

实例化时机：vt.js 加载后立即 `new`，无需手动 init（见 Q9）。

### Q2. 创建房间

**函数签名**（`vt.js:3558`）：

```js
async CreateRoom(name: string, password: string): Promise<void>
```

- 调用方式：`window.videoTogetherExtension.CreateRoom("roomName", "password")`
- 行为：
  1. 生成临时用户 id（`tempUser`）。
  2. 调用 `UpdateRoom` 向服务端 `PUT /room/update` 提交初始状态（`paused=true, currentTime=0, duration=0`），见 `vt.js:3566`。
  3. 把本地角色设为 `Master`（房主）。
  4. 切换浮动面板到"在房间中"状态。
- **不返回房间对象**，无返回值（`Promise<void>`）。房间状态通过下文 Q7 的事件机制异步获取。
- 房间名空字符串会弹错误提示（`popupError`），不抛异常。
- 同时会通过 WebSocket 上报（`WS.updateRoom`，`vt.js:3588`），如果 WS 已连上则不再发 HTTP。

### Q3. 加入房间

**函数签名**（`vt.js:2979`）：

```js
async JoinRoom(name: string, password: string): Promise<void>
```

- 调用方式：`window.videoTogetherExtension.JoinRoom("roomName", "password")`
- 行为：
  1. 生成新的 `tempUser`。
  2. 把本地角色设为 `Member`（成员）。
  3. 切换浮动面板到"在房间中"状态。
  4. 真正的"获取房间状态"在 `ScheduledTask` 定时器里完成（每 2 秒一次），定时器会调 `GetRoom` → `WS.joinRoom`（`vt.js:3627`）。
- 同样无返回值。成员加入后，VT 会自动监听房间状态变化并同步本地 video 元素（见 Q6）。

### Q4. 离开房间

**函数签名**（`vt.js:2995`）：

```js
exitRoom(): void   // 注意：首字母小写，不是 ExitRoom
```

- 调用方式：`window.videoTogetherExtension.exitRoom()`
- 行为：断开 WS、停止语音、清空房间名/密码/角色、把面板切回大厅、清空 sessionStorage 状态。
- **没有对应的"离开房间"按钮事件处理**，UI 上的离开按钮直接调这个方法。

### Q5. 发送文字消息

**❌ 没有公开方法。**

文字消息的发送链路：
1. UI 输入框回车或点发送按钮 → `vt.js:1286`：`sendMessageToTop(MessageType.SendTxtMsg, { currentSendingMsgId, value })`
2. top frame 收到后 → `vt.js:2772`：`WS.sendTextMessage(data.currentSendingMsgId, data.value)`
3. `WS` 对象（`vt.js:551`）的 `sendTextMessage`（`vt.js:688`）发 WS：

```js
{ "method": "send_txtmsg", "data": { "msg": msg, "id": id, "voiceId": "..." } }
```

**`WS` 是 `vt.js` IIFE 内部的 `const`，没有挂到 `window`。** 所以外部无法直接调 `WS.sendTextMessage`。

**变通方案**（不推荐，但可行）：手动构造 `MessageType.SendTxtMsg = 30` 的 postMessage 投递给 top frame：

```js
window.top.postMessage({
  source: "VideoTogether",
  type: 30,  // MessageType.SendTxtMsg
  data: { currentSendingMsgId: crypto.randomUUID(), value: "hello" }
}, "*");
```

这会触发 `vt.js:2771` 的分支，最终调用 `WS.sendTextMessage`。但 `MessageType` 是闭包内的私有常量，`30` 这个魔数是从源码里读出来的，未来版本可能变。

### Q6. 播放控制（播放/暂停/跳转）

**❌ 没有公开的播放控制 API。VT 的设计是"自动监听 video 元素"。**

#### 房主（Master）侧

VT 不监听 video 元素的 `play/pause/seek` 事件，而是用一个 **2 秒周期** 的 `setInterval` 定时器（`vt.js:1913`）轮询 video 状态：

- 定时器调 `ScheduledTask()`（`vt.js:3038`）。
- 在 `RoleEnum.Master` 分支（`vt.js:3125-3151`）：
  - 找到当前 video DOM（`GetVideoDom`）。
  - 调 `SyncMasterVideo`（`vt.js:3292`）读取 `videoDom.currentTime / paused / playbackRate / duration`。
  - 通过 `UpdateRoom` 把这些值上报到服务端（HTTP `PUT /room/update` 或 WS `/room/update`）。

也就是说：**房主只要操作页面里的 `<video>` 元素，VT 每 2 秒自动把状态同步到服务端。** 不需要任何手动调用。

#### 成员（Member）侧

- `ScheduledTask` 在 `RoleEnum.Member` 分支（`vt.js:3153-3207`）调 `GetRoom` 拉取房间状态。
- 然后调 `SyncMemberVideo`（`vt.js:3457`）：
  - 比较本地 video 的 `currentTime` 与服务端 `room.currentTime`（按 `lastUpdateServerTime` 外推），差值 > 1 秒就 seek。
  - 比较 `paused` 状态，需要播就 `videoDom.play()`，需要停就 `videoDom.pause()`。
  - 同步 `playbackRate`。

#### 自定义播放器适配

VT 内置了对一些站点自定义播放器的适配（通过 `VideoWrapper` 类，`vt.js:1826`），把站点的 `player.seek()` / `player.setPlaybackRate()` 等包装成标准 video 接口。适配的站点包括 BaiduPan、`__PLAYER__` 全局对象等（`vt.js:2149-2240`）。

> 对我们的场景：**如果在 WebView 里就是一个标准 `<video>` 元素，VT 能自动同步，无需任何 API 调用。** 但房主的 video 必须能被 `GetVideoDom` 找到（见 Q10）。

### Q7. 事件回调机制

**❌ 没有公开的事件回调、没有 `onStateChange`、没有 `CustomEvent`、没有 EventEmitter。**

VT 内部的事件传递机制是 `window.postMessage`，**只在 iframe / top frame 之间传递**，不是给外部消费者的。格式（`vt.js:425-447`）：

```js
{
  source: "VideoTogether",
  type: number,    // MessageType 枚举值
  data: any
}
```

`MessageType` 枚举（`vt.js:1756-1822`）里和"外部关心的状态变化"相关的项：

| type | 名称 | 含义 | data 形状 |
|------|------|------|-----------|
| 17 | `ExtensionInitSuccess` | VT 初始化完成 | `{}` |
| 22 | `RoomDataNotification` | 房间状态变化（含成员数） | Room 对象（见下） |
| 23 | `UpdateMemberStatus` | 成员加载状态变化 | `{ isLoadding: bool }` |
| 31 | `GotTxtMsg` | 收到文字消息 | `{ id: string, msg: string }` |
| 5  | `UpdateStatusText` | 状态文本（同步成功/失败提示） | `{ text: string, color: string }` |
| 6  | `JumpToNewPage` | 成员需要跳转到新 URL | `{ url: string }` |
| 9  | `ChangeVideoVolume` | 视频音量变化 | `{ volume: number }` |

**Room 对象结构**（来自 `go-server/service.go:321-344` + `vt.js:533-548`）：

```ts
interface Room {
  name: string;
  currentTime: number;          // 视频当前播放时间（秒）
  duration: number;             // 视频总时长（秒）
  lastUpdateClientTime: number; // 房主上次上报的客户端时间戳
  lastUpdateServerTime: number; // 服务端收到上报的服务端时间戳
  playbackRate: number;         // 播放倍速
  paused: boolean;              // 是否暂停
  url: string;                  // 房主页面 URL
  public: boolean;
  protected: boolean;           // 是否需要密码
  videoTitle: string;
  timestamp: number;            // 服务端当前时间戳
  backgroundUrl: string;        // 房间背景图
  m3u8Url: string;              // EasyShare 模式的 m3u8 地址
  uuid: string;                 // 房间 UUID（非房主侧生成）
  waitForLoadding: boolean;     // 是否有成员在加载
  beginLoaddingTimestamp: number;
  memberCount: number;          // **成员数（含房主）**
}
```

#### 监听事件的变通方案（不推荐，但可行）

理论上可以在 Dart 侧往 `window` 注入一个 `message` 事件监听器，过滤 `source === "VideoTogether"` 的消息：

```js
// 注入到 WebView 的桥接代码
window.addEventListener("message", (e) => {
  if (e.data && e.data.source === "VideoTogether") {
    // 转发给 Dart
    window.flutter_inappwebview.callHandler("vtEvent", JSON.stringify(e.data));
  }
});
```

**但这是内部协议，没有稳定性保证**：`MessageType` 的数字值是闭包私有常量，未来版本可能改。而且 `RoomDataNotification` 只在 top frame 上广播（`sendMessageToTop`），如果 VT 跑在 iframe 里，事件不会到达 iframe 自己的 window。

### Q8. WebSocket 服务器地址

**不是 `wss://api2.videotogether.com`。** 源码里没有任何对 `api2.videotogether.com` 的引用。

实际地址（`vt.js:582`）：

```js
new WebSocket(`wss://${extension.video_together_host.replace("https://", "")}/ws?language=${language}`)
```

其中 `video_together_host` 来自 `source/extension/config/release_host`：

| 配置 | 主机 | 用途 |
|------|------|------|
| `release_host` | `https://vt.panghair.com:5000/` | 默认（全球） |
| `debug_host` | `http://127.0.0.1:5001/` | 本地调试 |

对应的 WS URL：
- **全球**：`wss://vt.panghair.com:5000/ws?language=zh-cn`
- **国内回退**：`wss://dogyun.2gether.video/ws?language=zh-cn`（`apiHostChina`，base64 解码自 `release/cdn-config.json`，`vt.js:53-56`）

> `extension.js` 顶部 `@connect` 白名单里列了 `api.2gether.video`，但那是历史遗留的 userscript 权限声明，代码里没实际用。

**HTTP API 主机**同上（`https://vt.panghair.com:5000/`），端点见 `docs/HttpApiSpec.md`：
- `GET /timestamp`
- `GET /statistics`
- `GET /room/get?name=&password=`
- `PUT /room/update?name=&password=&playbackRate=&currentTime=&paused=&url=&lastUpdateClientTime=&duration=&tempUser=&protected=&videoTitle=`

### Q9. 初始化方式

**自动启动，无需手动 init。**

vt.js 是一个 IIFE（`vt.js:12`），加载后立即执行：
1. 定义所有类和常量。
2. 在末尾（`vt.js:3718-3731`）实例化 `VideoTogetherFlyPannel` 和 `VideoTogetherExtension`，挂到 `window`。
3. 实例化时（`constructor`，`vt.js:1853`）启动 2 秒周期的 `setInterval` 定时器（`vt.js:1913`）。
4. 立即发 `MessageType.ExtensionInitSuccess`（type=17）消息（`vt.js:3730`）。

**唯一需要的前置条件**：`window.VideoTogetherStorage` 要存在（由 `extension.js` 通过 `MessageType.SyncStorageValue` (type=16) 注入，`extension.js:498-502`）。如果直接注入 vt.js 而不先跑 extension.js，部分功能（如 `VideoTogetherTabStorageEnabled`）会降级或报错，但核心房间同步能用。

> 对我们的场景：直接在 WebView 里注入 vt.js 后，**还要模拟 extension.js 注入 `window.VideoTogetherStorage`**（至少一个空对象），否则 `getVideoTogetherStorage` 等函数会异常。最简单做法是先注入：
> ```js
> window.VideoTogetherStorage = window.VideoTogetherStorage || {
>   UserscriptType: "website",
>   LoaddingVersion: Date.now(),
>   VideoTogetherTabStorageEnabled: false,
>   PasswordProtectedRoom: false,
>   EasyShare: false,
>   DisableRedirectJoin: true,  // 关键：禁止 VT 自动跳转页面
>   WaitForLoadding: true,
>   PublicUserId: crypto.randomUUID()
> };
> ```

### Q10. 房间号格式

- **类型**：字符串（`name string`，`go-server/service.go:157, 323`）。
- **长度限制**：服务端代码里**没有**长度校验（`CreateRoom` / `QueryRoom` 都没检查 `len(name)`）。
- **唯一约束**：以 `download_` 前缀开头会被服务端统计为下载房间（`service.go:158`），不影响功能。
- **客户端约束**：`vt.js:2980` 和 `vt.js:3559` 只检查空字符串，其他都允许。
- **官方用法**：官方测试（`test/extension/sync.js:49`）用 `"AutoTest"` 这种纯字母字符串。EasyShare 链接里直接拼到 URL query 里（`vt.js:2041`），所以建议避免 URL 特殊字符。

> 实践建议：用 6-12 位字母数字字符串即可，无需固定长度。

---

## 3. 关键函数签名速查表

| 方法 | 签名 | 位置 | 是否可外部调用 |
|------|------|------|----------------|
| `CreateRoom` | `async CreateRoom(name: string, password: string): Promise<void>` | `vt.js:3558` | ✅ 可，但依赖面板 DOM |
| `JoinRoom` | `async JoinRoom(name: string, password: string): Promise<void>` | `vt.js:2979` | ✅ 可，但依赖面板 DOM |
| `exitRoom` | `exitRoom(): void` | `vt.js:2995` | ✅ 可 |
| `UpdateRoom` | `async UpdateRoom(name, password, url, playbackRate, currentTime, paused, duration, localTimestamp, m3u8Url?): Promise<Room>` | `vt.js:3580` | ✅ 可（内部用） |
| `GetRoom` | `async GetRoom(name, password): Promise<Room>` | `vt.js:3626` | ✅ 可（内部用） |
| `SyncMasterVideo` | `async SyncMasterVideo(data, videoDom): Promise<void>` | `vt.js:3292` | 内部用 |
| `SyncMemberVideo` | `async SyncMemberVideo(data, videoDom): Promise<void>` | `vt.js:3457` | 内部用 |
| `ScheduledTask` | `async ScheduledTask(scheduled?: boolean): Promise<void>` | `vt.js:3038` | 内部用（2 秒自动调） |
| `WS.sendTextMessage` | `async sendTextMessage(id: string, msg: string): Promise<void>` | `vt.js:688` | ❌ 闭包私有，不在 window |
| `WS.joinRoom` | `async joinRoom(name, password): Promise<void>` | `vt.js:711` | ❌ 闭包私有 |
| `WS.connect` | `async connect(): Promise<void>` | `vt.js:565` | ❌ 闭包私有 |

`VideoTogetherExtension` 实例上还有这些**只读属性**可读：
- `window.videoTogetherExtension.role` — `1=Null, 2=Master, 3=Member`（`RoleEnum`，`vt.js:1854`）
- `window.videoTogetherExtension.roomName` — 当前房间名（string）
- `window.videoTogetherExtension.password` — 当前房间密码（string）
- `window.videoTogetherExtension.isMain` — 是否在 top frame（`window.self === window.top`）
- `window.videoTogetherExtension.tempUser` — 当前会话临时用户 id
- `window.videoTogetherExtension.ctxMemberCount` — 最近一次收到的成员数
- `window.videoTogetherExtension.ctxWsIsOpen` — WS 是否已连上

---

## 4. 事件订阅示例（变通方案，不推荐生产用）

如果非要复用 VT 客户端 JS，可以在 WebView 里注入一段桥接脚本，监听 `window` 的 `message` 事件，转发给 Dart：

```js
// === 注入到 WebView，在 vt.js 之后注入 ===
(function () {
  const VT_EVENT_TYPES = {
    17: "vt_init",           // ExtensionInitSuccess
    22: "vt_room_update",    // RoomDataNotification (含 memberCount)
    23: "vt_member_status",  // UpdateMemberStatus
    31: "vt_text_message",   // GotTxtMsg
    5:  "vt_status_text",    // UpdateStatusText
    6:  "vt_jump_page",      // JumpToNewPage
  };

  window.addEventListener("message", (e) => {
    if (!e.data || e.data.source !== "VideoTogether") return;
    const name = VT_EVENT_TYPES[e.data.type];
    if (!name) return;
    // 转发给 Dart（以 flutter_inappwebview 为例）
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler("vtEvent", {
        name: name,
        type: e.data.type,
        data: e.data.data
      });
    }
  });

  // 主动创建/加入房间的封装
  window.vtBridge = {
    createRoom: (name, password) => window.videoTogetherExtension.CreateRoom(name, password),
    joinRoom: (name, password) => window.videoTogetherExtension.JoinRoom(name, password),
    leaveRoom: () => window.videoTogetherExtension.exitRoom(),
    // 发文字消息：只能通过模拟 postMessage
    sendText: (msg) => {
      const id = crypto.randomUUID();
      window.top.postMessage({
        source: "VideoTogether",
        type: 30, // MessageType.SendTxtMsg
        data: { currentSendingMsgId: id, value: msg }
      }, "*");
      return id;
    },
    getState: () => ({
      role: window.videoTogetherExtension?.role,
      roomName: window.videoTogetherExtension?.roomName,
      memberCount: window.videoTogetherExtension?.ctxMemberCount,
      wsOpen: window.videoTogetherExtension?.ctxWsIsOpen
    })
  };
})();
```

Dart 侧（`flutter_inappwebview` 示例）：

```dart
webview.addJavaScriptHandler(
  handlerName: 'vtEvent',
  callback: (args) {
    final event = args[0] as Map;
    switch (event['name']) {
      case 'vt_room_update':
        final room = event['data'];
        print('成员数: ${room['memberCount']}');
        break;
      case 'vt_text_message':
        print('收到消息: ${event['data']['msg']}');
        break;
      case 'vt_init':
        print('VT 已就绪');
        break;
    }
  },
);
```

**这套方案的风险**：
1. `MessageType` 数字是私有常量，VT 升级后可能改（虽然历史上很少改）。
2. 浮动面板 UI 会出现在 WebView 里，需要额外 CSS 隐藏（`#VideoTogetherWrapper { display: none !important; }`），但隐藏后用户没法操作"创建/加入"按钮，必须全靠 `vtBridge` 调用。
3. VT 会尝试劫持页面里所有 `<a>` 链接的 target（`vt.js:3097`，`OpenAllLinksInSelf`），可能导致 WebView 内部导航异常 —— 务必把 `VideoTogetherStorage.OpenAllLinksInSelf` 设为 `false`。
4. VT 会把房间状态写到 `sessionStorage`，WebView 关闭后状态丢失（这是预期行为）。

---

## 5. 推荐方案：自写精简版同步脚本

鉴于上述限制，**强烈建议自己写一个 ~200 行的精简版同步脚本**，直连 VT 的后端协议。协议已经从源码里完全逆向出来，关键点如下：

### 5.1 协议要点

**WebSocket 连接**：
- URL：`wss://vt.panghair.com:5000/ws?language=zh-cn`（国内回退 `wss://dogyun.2gether.video/ws`）
- 协议：每条消息是一行 JSON（`vt.js:584` 按 `\n` 分割）。
- 心跳：客户端每 2 秒主动上报一次（参考 `ScheduledTask` 的 2 秒周期）。

**客户端 → 服务端**消息（`method` 字段）：

| method | data 字段 | 用途 |
|--------|-----------|------|
| `/room/join` | `{name, password}` | 加入房间（房主和成员都调） |
| `/room/update` | `{tempUser, password, name, playbackRate, currentTime, paused, url, lastUpdateClientTime, duration, protected, videoTitle, sendLocalTimestamp, m3u8Url}` | 房主上报视频状态 |
| `/room/update_member` | `{password, roomName, sendLocalTimestamp, userId, isLoadding, currentUrl}` | 成员上报加载状态 |
| `send_txtmsg` | `{msg, id, voiceId}` | 发文字消息 |
| `m3u8_req` / `m3u8_resp` | — | EasyShare 模式 m3u8 内容共享，精简版可不实现 |
| `url_req` / `url_resp` | — | 真实 URL 解析，精简版可不实现 |

**服务端 → 客户端**消息（`data['method']` 字段，`vt.js:602-642`）：

| method | 含义 |
|--------|------|
| `/room/join` | 加入房间成功（`_joinedName` 被设置） |
| `/room/update` | 房间状态更新（房主上报后广播给所有成员） |
| `/room/update_member` | 成员状态更新 |
| `send_txtmsg` | 收到文字消息（`data.audioUrl` 可能含 TTS 音频 URL） |
| `replay_timestamp` | 时间同步响应 |
| `url_req` / `url_resp` / `m3u8_req` / `m3u8_resp` | 同上，精简版可忽略 |

**HTTP 回退**（WS 断开时用，`vt.js:3595-3614`）：
- `GET /room/get?name=&password=` → 返回 Room 对象
- `PUT /room/update?...` → 返回 Room 对象
- `GET /timestamp` → 时间同步

### 5.2 时间同步

VT 用 `lastUpdateServerTime` 做播放进度外推（`vt.js:3487` 的 `CalculateRealCurrent`）。精简版需要：
1. 启动时调 `GET /timestamp` 拿服务端时间，计算 `timeOffset = serverTimestamp - localTimestamp`。
2. 之后所有 `room.currentTime` 都按 `realCurrent = room.currentTime + (now + timeOffset - room.lastUpdateServerTime) * room.playbackRate` 外推。

### 5.3 精简版 JS 骨架（供 Dart 调用）

```js
// vt-lite.js — 精简版同步脚本，不依赖任何 DOM
window.VtLite = (function () {
  const API_HOST = "https://vt.panghair.com:5000";
  const WS_URL = "wss://vt.panghair.com:5000/ws?language=zh-cn";
  const tempUser = "vt_" + Date.now() + "_" + crypto.randomUUID();
  let ws = null, timeOffset = 0;
  let roomName = "", password = "", role = 0; // 0=null, 1=master, 2=member
  const listeners = {};

  function on(event, cb) { (listeners[event] ||= []).push(cb); }
  function emit(event, data) { (listeners[event] || []).forEach(cb => cb(data)); }

  async function syncTime() {
    const r = await fetch(`${API_HOST}/timestamp`).then(r => r.json());
    timeOffset = r.timestamp - Date.now() / 1000;
  }

  function connectWs() {
    ws = new WebSocket(WS_URL);
    ws.onmessage = (e) => {
      e.data.split("\n").forEach(line => {
        const msg = JSON.parse(line);
        if (msg.method === "/room/update" || msg.method === "/room/update_member" || msg.method === "/room/join") {
          emit("room_update", msg.data);
        } else if (msg.method === "send_txtmsg") {
          emit("text_message", msg.data);
        }
      });
    };
    ws.onopen = () => emit("ws_open", {});
    ws.onclose = () => { ws = null; emit("ws_close", {}); };
  }

  function send(obj) { ws && ws.readyState === 1 && ws.send(JSON.stringify(obj)); }

  async function createRoom(name, pwd, videoEl) {
    roomName = name; password = pwd; role = 1;
    await syncTime();
    if (!ws) connectWs();
    // 主循环：每 2 秒上报 video 状态
    setInterval(() => {
      if (role !== 1 || !videoEl) return;
      send({ method: "/room/update", data: {
        tempUser, password, name: roomName,
        playbackRate: videoEl.playbackRate,
        currentTime: videoEl.currentTime,
        paused: videoEl.paused,
        url: location.href,
        lastUpdateClientTime: Date.now() / 1000 + timeOffset,
        duration: videoEl.duration,
        protected: false, videoTitle: document.title,
        sendLocalTimestamp: Date.now() / 1000, m3u8Url: ""
      }});
    }, 2000);
  }

  async function joinRoom(name, pwd, videoEl) {
    roomName = name; password = pwd; role = 2;
    await syncTime();
    if (!ws) connectWs();
    send({ method: "/room/join", data: { name, password } });
    // 成员侧：收到 room_update 后同步本地 video
    on("room_update", (room) => {
      if (role !== 2 || !videoEl) return;
      const realCurrent = room.currentTime +
        (Date.now() / 1000 + timeOffset - room.lastUpdateServerTime) * room.playbackRate;
      if (Math.abs(videoEl.currentTime - realCurrent) > 1) videoEl.currentTime = realCurrent;
      if (videoEl.paused !== room.paused) room.paused ? videoEl.pause() : videoEl.play();
      videoEl.playbackRate = room.playbackRate;
    });
  }

  function leaveRoom() {
    if (ws) { try { ws.close(); } catch {} }
    ws = null; roomName = ""; password = ""; role = 0;
  }

  function sendText(msg) {
    send({ method: "send_txtmsg", data: {
      msg, id: crypto.randomUUID(), voiceId: ""
    }});
  }

  return { on, createRoom, joinRoom, leaveRoom, sendText,
           getRole: () => role, getRoomName: () => roomName };
})();
```

Dart 侧通过 `evaluateJavascript` 调用 `VtLite.createRoom(...)` 等，通过 `addJavaScriptHandler` 接收 `on("room_update", ...)` 转发的事件。

---

## 6. 如果非要 fork VT 改造

如果一定要复用 VT 完整客户端（比如想用它的 m3u8 EasyShare、语音通话、下载等功能），最小改造清单：

1. **暴露 `WS` 对象**：在 `vt.js:3729` 后加 `window.videoTogetherWS = WS;`
2. **暴露 `MessageType` 常量**：加 `window.VideoTogetherMessageType = MessageType;`
3. **添加事件总线**：在 `VideoTogetherExtension` 类里加 `on(event, cb)` 方法和 `emit(event, data)` 方法，在 `processReceivedMessage` 的关键 case（`RoomDataNotification` / `GotTxtMsg` / `UpdateMemberStatus`）里 `emit`。
4. **隐藏 UI**：在 `VideoTogetherFlyPannel` 构造函数里加一个 `this.hidden = true` 分支，跳过 DOM 创建。
5. **禁用链接劫持**：把 `OpenAllLinksInSelf` 默认值改 `false`（`vt.js:3097`）。
6. **禁用页面跳转**：`JoinRoom` 成员分支里 `JumpToNewPage` 逻辑（`vt.js:3184-3193`）需要改成不跳转，由 Dart 侧控制 WebView 导航。

---

## 7. 引用源码索引

所有行号基于 `clone --depth 1` 的 `main` 分支快照（2026-07-27）。

| 主题 | 文件 | 行号 |
|------|------|------|
| 全局对象挂载 | `source/extension/vt.js` | 3718-3731 |
| `VideoTogetherExtension` 类定义 | `source/extension/vt.js` | 1851 |
| `VideoTogetherFlyPannel` 类定义 | `source/extension/vt.js` | 1235 |
| `CreateRoom` | `source/extension/vt.js` | 3558 |
| `JoinRoom` | `source/extension/vt.js` | 2979 |
| `exitRoom` | `source/extension/vt.js` | 2995 |
| `UpdateRoom`（HTTP+WS） | `source/extension/vt.js` | 3580 |
| `GetRoom` | `source/extension/vt.js` | 3626 |
| `SyncMasterVideo`（房主轮询上报） | `source/extension/vt.js` | 3292 |
| `SyncMemberVideo`（成员同步本地 video） | `source/extension/vt.js` | 3457 |
| `ScheduledTask`（2 秒主循环） | `source/extension/vt.js` | 3038 |
| 2 秒 `setInterval` 启动 | `source/extension/vt.js` | 1913 |
| `WS` 对象定义 | `source/extension/vt.js` | 551 |
| `WS.connect` / WebSocket URL | `source/extension/vt.js` | 565, 582 |
| `WS.sendTextMessage` | `source/extension/vt.js` | 688 |
| `WS.onmessage`（服务端消息分发） | `source/extension/vt.js` | 593 |
| `MessageType` 枚举 | `source/extension/vt.js` | 1756-1822 |
| `sendMessageToTop` / `PostMessage` | `source/extension/vt.js` | 407, 425 |
| `processReceivedMessage` | `source/extension/vt.js` | 2463 |
| `RoomDataNotification` 处理 | `source/extension/vt.js` | 2670 |
| `GotTxtMsg` 处理 | `source/extension/vt.js` | 2775 |
| `Room` 类（客户端侧） | `source/extension/vt.js` | 533 |
| `Room` struct（服务端侧，完整字段） | `source/go-server/service.go` | 321-354 |
| `CreateRoom`（服务端） | `source/go-server/service.go` | 157 |
| `send_txtmsg` 服务端处理 | `source/go-server/ws.go` | 335, 365 |
| HTTP API 规范 | `docs/HttpApiSpec.md` | 全文 |
| release_host 配置 | `source/extension/config/release_host` | 1 |
| cdn-config（国内回退主机） | `release/cdn-config.json` | 全文 |
| 官方自动化测试（操作 DOM 而非 API） | `test/extension/sync.js` | 75-80 |

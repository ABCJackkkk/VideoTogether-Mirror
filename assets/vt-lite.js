// assets/vt-lite.js
//
// VtLite — VideoTogether 协议精简版同步脚本
//
// 用途：在 Flutter WebView 中注入此脚本，通过 VideoTogether 公共 WebSocket
//   服务器实现"异地同看视频"的播放同步（房主上报 / 成员跟随 / 文字消息）。
//
// 协议来源：逆向自 VideoTogether 开源仓库
//   (https://github.com/VideoTogether/VideoTogether)
//   - 主 WS：   wss://vt.panghair.com:5000/ws?language=zh-cn
//   - 回退 WS： wss://dogyun.2gether.video/ws?language=zh-cn
//   - 时间同步：GET https://vt.panghair.com:5000/timestamp
//   - 消息格式：每条 WebSocket 消息按 "\n" 分割，每行一个 JSON
//
// 暴露 API (window.VtLite)：
//   on(event, cb)                   订阅事件
//                                    事件名: room_update / text_message /
//                                            ws_open / ws_close / error
//   off(event, cb)                  取消订阅
//   createRoom(name, pwd, videoEl)  async 房主创建房间 + 启动 2s 上报循环
//   joinRoom(name, pwd, videoEl)    async 成员加入 + 自动同步本地 video
//   leaveRoom()                     离开房间（断 WS、停定时器）
//   sendText(msg)                   发送文字消息
//   getState()                      返回 { role, roomName, wsOpen, memberCount }
//                                   role: "null" / "master" / "member"
//   destroy()                       彻底清理（断 WS、清监听、停定时器）
//
// 设计约束：
//   - 不依赖任何外部库
//   - 不创建任何 UI
//   - 除传入的 videoEl 外不操作 DOM
//   - 不自动重连（由 Dart 侧决定）
//   - 所有回调 try/catch 包裹，单个监听器报错不影响其他
(function () {
  if (typeof window !== "undefined" && window.VtLite) return; // 防止重复注入

  var API_HOST = "https://vt.panghair.com:5000";
  var WS_URLS = [
    "wss://vt.panghair.com:5000/ws?language=zh-cn",
    "wss://dogyun.2gether.video/ws?language=zh-cn"
  ];

  // 角色枚举
  var ROLE = { NULL: "null", MASTER: "master", MEMBER: "member" };

  // ===== 内部状态 =====
  var ws = null;                // WebSocket 实例
  var wsReady = false;          // WS 是否已成功 onopen
  var timeOffset = 0;           // serverTimestamp - localTimestamp（秒）
  var roomName = "";
  var password = "";
  var role = ROLE.NULL;
  var memberCount = 0;
  var masterTimer = null;       // 房主上报循环 setInterval 句柄
  var videoElement = null;      // 当前绑定的 video 元素
  var intentionalClose = false; // 主动关闭标志（leaveRoom/destroy 时置 true）
  var destroyed = false;

  // 临时用户 id（服务端用于识别房主身份）
  var tempUser = "vt_" + Date.now() + "_" + uuid();

  // 事件监听器表：{ event: [cb, cb, ...] }
  var listeners = {};

  // ===== 工具函数 =====

  // 生成 UUID（优先用 crypto.randomUUID，老环境回退到 Math.random）
  function uuid() {
    try {
      if (typeof crypto !== "undefined" && crypto.randomUUID) {
        return crypto.randomUUID();
      }
    } catch (e) {}
    return "xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      var v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function on(event, cb) {
    if (typeof cb !== "function") return;
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(cb);
  }

  function off(event, cb) {
    if (!listeners[event]) return;
    listeners[event] = listeners[event].filter(function (fn) {
      return fn !== cb;
    });
  }

  // 触发事件：先调本地监听器，再转发给 Dart 侧
  function emit(event, data) {
    var cbs = listeners[event];
    if (cbs) {
      // 复制一份，避免回调中 off/destroy 导致迭代异常
      cbs.slice().forEach(function (cb) {
        try { cb(data); } catch (e) {}
      });
    }
    // 转发给 Flutter（flutter_inappwebview 桥接）
    if (typeof window !== "undefined" &&
        window.flutter_inappwebview &&
        window.flutter_inappwebview.callHandler) {
      try {
        window.flutter_inappwebview.callHandler("vtEvent", {
          event: event, data: data
        });
      } catch (e) {}
    }
  }

  // 发送一条 WS 消息（仅在 WS OPEN 时发送）
  function send(obj) {
    if (ws && ws.readyState === 1) { // WebSocket.OPEN === 1
      try { ws.send(JSON.stringify(obj)); } catch (e) {}
    }
  }

  // ===== 时间同步 =====
  // 启动时 GET /timestamp，计算 timeOffset = serverTime - localTime
  // 用于成员侧播放进度外推
  async function syncTime() {
    try {
      var resp = await fetch(API_HOST + "/timestamp");
      var r = await resp.json();
      if (r && typeof r.timestamp === "number") {
        timeOffset = r.timestamp - Date.now() / 1000;
      }
    } catch (e) {
      // 时间同步失败不致命，timeOffset 保持 0，进度外推会有偏差
      emit("error", { message: "sync_time_failed", error: String(e) });
    }
  }

  // ===== WebSocket 消息处理 =====
  function handleWsMessage(raw) {
    var lines = String(raw).split("\n");
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line) continue;
      var msg;
      try {
        msg = JSON.parse(line);
      } catch (e) {
        continue; // 单行解析失败跳过，不影响其他行
      }
      if (!msg || !msg.method) continue;
      var data = msg.data || {};
      if (msg.method === "/room/update" ||
          msg.method === "/room/update_member" ||
          msg.method === "/room/join") {
        if (typeof data.memberCount === "number") memberCount = data.memberCount;
        emit("room_update", data);
      } else if (msg.method === "send_txtmsg") {
        emit("text_message", data);
      }
      // replay_timestamp / url_req / url_resp / m3u8_* 精简版忽略
    }
  }

  // ===== WebSocket 连接（主地址失败自动回退） =====
  function connectWs(urlIndex) {
    if (destroyed) return;
    if (typeof urlIndex !== "number") urlIndex = 0;
    if (urlIndex >= WS_URLS.length) {
      emit("error", { message: "ws_all_urls_failed" });
      return;
    }
    try {
      ws = new WebSocket(WS_URLS[urlIndex]);
    } catch (e) {
      emit("error", { message: "ws_construct_failed", error: String(e) });
      return;
    }

    ws.onopen = function () {
      wsReady = true;
      emit("ws_open", {});
      // 重连场景：若已是成员，重新发 join 让服务端推送房间状态
      if (role === ROLE.MEMBER && roomName) {
        send({ method: "/room/join", data: { name: roomName, password: password } });
      }
    };

    ws.onmessage = function (e) {
      try {
        handleWsMessage(e.data);
      } catch (err) {
        emit("error", { message: "ws_message_handler_error", error: String(err) });
      }
    };

    ws.onerror = function () {
      // 连接建立前的错误由 onclose 触发回退；建立后的错误忽略（交给 onclose）
    };

    ws.onclose = function () {
      var wasReady = wsReady;
      var wasIntentional = intentionalClose;
      intentionalClose = false;
      ws = null;
      wsReady = false;
      // 主动关闭（leaveRoom/destroy）：不 emit，不回退
      if (wasIntentional) return;
      // 连接阶段失败且有回退 URL：尝试下一个
      if (!wasReady && urlIndex + 1 < WS_URLS.length) {
        connectWs(urlIndex + 1);
        return;
      }
      emit("ws_close", { wasOpen: wasReady });
    };
  }

  // ===== 房主上报循环（每 2 秒） =====
  function startMasterTimer() {
    stopMasterTimer();
    masterTimer = setInterval(function () {
      if (role !== ROLE.MASTER || !videoElement) return;
      var v = videoElement;
      var currentTime = 0, paused = true, playbackRate = 1, duration = 0;
      try {
        currentTime = v.currentTime || 0;
        paused = !!v.paused;
        playbackRate = v.playbackRate || 1;
        duration = v.duration || 0;
      } catch (e) {
        return;
      }
      send({
        method: "/room/update",
        data: {
          tempUser: tempUser,
          password: password,
          name: roomName,
          playbackRate: playbackRate,
          currentTime: currentTime,
          paused: paused,
          url: (typeof location !== "undefined" && location.href) || "",
          lastUpdateClientTime: Date.now() / 1000 + timeOffset,
          duration: duration,
          protected: !!password, // 设了密码则房间受保护
          videoTitle: (typeof document !== "undefined" && document.title) || "",
          sendLocalTimestamp: Date.now() / 1000,
          m3u8Url: ""
        }
      });
    }, 2000);
  }

  function stopMasterTimer() {
    if (masterTimer) {
      try { clearInterval(masterTimer); } catch (e) {}
      masterTimer = null;
    }
  }

  // ===== 成员同步逻辑（只注册一次，靠 role 守卫） =====
  // 收到 room_update 时：外推真实进度，差 > 1s 则 seek；同步 paused/playbackRate
  on("room_update", function (room) {
    if (role !== ROLE.MEMBER || !videoElement || !room) return;
    var v = videoElement;
    try {
      var realCurrent = room.currentTime +
        (Date.now() / 1000 + timeOffset -
          (room.lastUpdateServerTime || 0)) * (room.playbackRate || 1);
      if (typeof v.currentTime === "number" &&
          Math.abs(v.currentTime - realCurrent) > 1) {
        v.currentTime = realCurrent;
      }
      if (v.paused !== !!room.paused) {
        if (room.paused) {
          try { v.pause(); } catch (e) {}
        } else {
          try { v.play().catch(function () {}); } catch (e) {}
        }
      }
      if (typeof room.playbackRate === "number" &&
          v.playbackRate !== room.playbackRate) {
        try { v.playbackRate = room.playbackRate; } catch (e) {}
      }
    } catch (e) {
      emit("error", { message: "member_sync_error", error: String(e) });
    }
  });

  // ===== 公开 API =====

  async function createRoom(name, pwd, videoEl) {
    if (!name) throw new Error("room name required");
    stopMasterTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MASTER;
    videoElement = videoEl || null;
    memberCount = 1;
    await syncTime();
    if (!ws) connectWs(0);
    startMasterTimer();
  }

  async function joinRoom(name, pwd, videoEl) {
    if (!name) throw new Error("room name required");
    stopMasterTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MEMBER;
    videoElement = videoEl || null;
    memberCount = 0;
    await syncTime();
    if (!ws) connectWs(0);
    // 若 WS 已 open 立即发 join；否则 onopen 会补发
    send({ method: "/room/join", data: { name: roomName, password: password } });
  }

  function leaveRoom() {
    intentionalClose = true;
    stopMasterTimer();
    if (ws) { try { ws.close(); } catch (e) {} }
    ws = null;
    wsReady = false;
    roomName = "";
    password = "";
    role = ROLE.NULL;
    memberCount = 0;
  }

  function sendText(msg) {
    if (!ws || !wsReady) {
      emit("error", { message: "ws_not_open" });
      return;
    }
    send({
      method: "send_txtmsg",
      data: { msg: String(msg), id: uuid(), voiceId: "" }
    });
  }

  function getState() {
    return {
      role: role,
      roomName: roomName,
      wsOpen: !!wsReady,
      memberCount: memberCount
    };
  }

  function destroy() {
    destroyed = true;
    intentionalClose = true;
    stopMasterTimer();
    if (ws) { try { ws.close(); } catch (e) {} }
    ws = null;
    wsReady = false;
    roomName = "";
    password = "";
    role = ROLE.NULL;
    memberCount = 0;
    videoElement = null;
    Object.keys(listeners).forEach(function (k) { delete listeners[k]; });
  }

  if (typeof window !== "undefined") {
    window.VtLite = {
      on: on,
      off: off,
      createRoom: createRoom,
      joinRoom: joinRoom,
      leaveRoom: leaveRoom,
      sendText: sendText,
      getState: getState,
      destroy: destroy
    };
  }
})();

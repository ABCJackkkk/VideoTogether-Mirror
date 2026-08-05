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

  // ===== 主/子 frame 判断 =====
  // VT 原版靠油猴 @match *://*/* 在每个 iframe 注入脚本；
  // 这里用 initialUserScripts(forMainFrameOnly:false) 模拟，
  // 脚本会在所有 frame 执行，通过 postMessage 跨域通信。
  var isMainFrame = false;
  try { isMainFrame = (window.top === window); } catch (e) {}

  // ===== 子 frame 代理：找 video → 上报状态 → 接收控制 =====
  // 不运行完整 VtLite，只做 video 代理，跨域也能工作
  if (!isMainFrame) {
    var agentVideo = null;
    var agentPollTimer = setInterval(function () {
      var v = document.querySelector("video");
      if (v !== agentVideo) {
        agentVideo = v;
        if (agentVideo) {
          attachAgentEvents();
          postAgentState();
        }
      }
    }, 500);

    function attachAgentEvents() {
      if (!agentVideo) return;
      ["play", "pause", "seeked", "ratechange", "loadedmetadata", "timeupdate", "waiting", "playing"].forEach(function (ev) {
        try { agentVideo.addEventListener(ev, postAgentState); } catch (e) {}
      });
    }

    function postAgentState() {
      if (!agentVideo) return;
      try {
        window.parent.postMessage({
          source: "vt-lite-agent",
          type: "video_state",
          currentTime: agentVideo.currentTime || 0,
          paused: !!agentVideo.paused,
          duration: agentVideo.duration || 0,
          playbackRate: agentVideo.playbackRate || 1,
          videoWidth: agentVideo.videoWidth || 0,
          readyState: agentVideo.readyState || 0
        }, "*");
      } catch (e) {}
    }

    // 定期上报（即使没有事件触发）
    setInterval(postAgentState, 1000);

    // 向子 iframe 转发消息（嵌套 iframe 场景）
    function forwardToChildren(msg) {
      try {
        var fs = document.querySelectorAll("iframe");
        for (var i = 0; i < fs.length; i++) {
          try { fs[i].contentWindow.postMessage(msg, "*"); } catch (e) {}
        }
      } catch (e) {}
    }

    // 监听消息：主 frame 控制指令（执行+向下转发）/ 孙 frame 状态（向上转发）
    window.addEventListener("message", function (e) {
      if (!e.data || !e.data.source) return;
      try {
        if (e.data.source === "vt-lite-master") {
          forwardToChildren(e.data); // 先转发给孙 frame（嵌套场景）
          if (!agentVideo) return;
          var cmd = e.data;
          if (cmd.type === "control") {
            if (cmd.action === "seek" && typeof cmd.value === "number") {
              agentVideo.currentTime = cmd.value;
            } else if (cmd.action === "pause") {
              agentVideo.pause();
            } else if (cmd.action === "play") {
              agentVideo.play().catch(function () {});
            } else if (cmd.action === "rate" && typeof cmd.value === "number") {
              agentVideo.playbackRate = cmd.value;
            }
          } else if (cmd.type === "query_state") {
            postAgentState();
          }
        } else if (e.data.source === "vt-lite-agent") {
          // 孙 frame 上报的状态：转发给父 frame，直到主 frame
          try {
            window.parent.postMessage(e.data, "*");
          } catch (err2) {}
        }
      } catch (err) {}
    });

    // 标记已注入（防止主 frame 重复注入完整 VtLite）
    window.VtLite = { _isFrameAgent: true };
    return;
  }

  // ===== 以下为主 frame 逻辑（完整 VtLite） =====

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
  var memberTimer = null;       // 成员心跳循环 setInterval 句柄
  var videoPollTimer = null;    // video 元素轮询定时器
  var videoElement = null;      // 当前绑定的 video 元素（主 frame 直接引用或 null）
  var intentionalClose = false; // 主动关闭标志（leaveRoom/destroy 时置 true）
  var destroyed = false;

  // ===== iframe 代理状态 =====
  // 子 frame 通过 postMessage 上报的 video 状态，当 videoElement 为 null 时使用
  var lastVideoState = null;    // {currentTime, paused, duration, playbackRate, videoWidth, readyState}
  var hasRemoteVideo = false;   // 是否有子 frame 上报过 video

  // 主 frame 监听子 frame 上报的 video 状态
  window.addEventListener("message", function (e) {
    if (!e.data || e.data.source !== "vt-lite-agent") return;
    if (e.data.type === "video_state") {
      lastVideoState = e.data;
      if (!hasRemoteVideo) {
        hasRemoteVideo = true;
        // 子 frame 找到 video，停止主 frame 的轮询
        stopVideoPolling();
      }
      // 如果主 frame 也没直接找到 video，用远程标记
      if (!videoElement) {
        videoElement = REMOTE_VIDEO_MARKER;
      }
    }
  });

  // 向所有子 frame 广播控制指令（跨域 iframe 也能收到）
  function sendControl(action, value) {
    try {
      var frames = document.querySelectorAll("iframe");
      for (var i = 0; i < frames.length; i++) {
        try {
          frames[i].contentWindow.postMessage({
            source: "vt-lite-master",
            type: "control",
            action: action,
            value: value
          }, "*");
        } catch (e) {}
      }
    } catch (e) {}
  }

  // 远程 video 标记对象：videoElement === REMOTE_VIDEO_MARKER 表示用 postMessage 控制
  var REMOTE_VIDEO_MARKER = { _remote: true };

  // ===== 自动重连状态 =====
  // 连接断开（非主动）后，按指数退避重试：1s, 2s, 4s, 8s, 16s, 30s（封顶）
  var reconnectTimer = null;
  var reconnectAttempts = 0;
  var RECONNECT_DELAYS = [1000, 2000, 4000, 8000, 16000, 30000];

  // 临时用户 id（服务端用于识别房主身份）
  var tempUser = "vt_" + Date.now() + "_" + uuid();

  // 事件监听器表：{ event: [cb, cb, ...] }
  var listeners = {};

  // 成员 join 重试状态：房主可能还没初始化房间，收到 room_not_found 时
  // 不立即报错，而是在 memberTimer 里每 2 秒重试（对照 VT 原版 ScheduledTask）
  var joinRetryCount = 0;
  var MAX_JOIN_RETRIES = 15; // 15 次 × 2 秒 = 30 秒超时
  var joinSucceeded = false;

  // 聊天昵称（发送消息时写入 voiceId 字段，接收端据此显示发送者）
  var senderName = "";

  // 事件队列：供 Dart 侧 flushEvents() 轮询拉取
  // 不依赖 callHandler（在 initialData/某些页面中可能不可用）
  var eventQueue = [];

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

  // 触发事件：先调本地监听器，再存入队列供 Dart 侧轮询
  function emit(event, data) {
    var cbs = listeners[event];
    if (cbs) {
      // 复制一份，避免回调中 off/destroy 导致迭代异常
      cbs.slice().forEach(function (cb) {
        try { cb(data); } catch (e) {}
      });
    }
    // 存入队列，供 Dart 侧 flushEvents() 拉取；
    // 上限 200 条：防止 Dart 侧轮询中断时队列无限增长
    eventQueue.push({ event: event, data: data });
    if (eventQueue.length > 200) {
      eventQueue.splice(0, eventQueue.length - 200);
    }
  }

  // Dart 侧轮询调用：返回并清空事件队列
  function flushEvents() {
    if (eventQueue.length === 0) return "[]";
    var json = JSON.stringify(eventQueue);
    eventQueue = [];
    return json;
  }

  // 发送一条 WS 消息（仅在 WS OPEN 时发送）
  function send(obj) {
    if (ws && ws.readyState === 1) { // WebSocket.OPEN === 1
      try { ws.send(JSON.stringify(obj)); } catch (e) {}
    }
  }

  // 服务端消息外壳归一化：兼容 {method, data} 与 {data: {method, data}} 两种格式
  function normalizeServerMsg(msg) {
    if (msg && msg.data && typeof msg.data === "object" &&
        typeof msg.data.method === "string" && !msg.method) {
      return { method: msg.data.method, data: msg.data.data || {} };
    }
    return msg;
  }

  // ===== 时间同步 =====
  // 启动时 GET /timestamp，计算 timeOffset = serverTime - localTime
  // 用于成员侧播放进度外推。5 秒超时，避免网络异常时阻塞流程
  async function syncTime() {
    var ctrl = null, timer = null;
    try {
      if (typeof AbortController !== "undefined") {
        ctrl = new AbortController();
        timer = setTimeout(function () { ctrl.abort(); }, 5000);
      }
      var resp = await fetch(API_HOST + "/timestamp", ctrl ? { signal: ctrl.signal } : {});
      if (timer) clearTimeout(timer);
      var r = await resp.json();
      if (r && typeof r.timestamp === "number") {
        timeOffset = r.timestamp - Date.now() / 1000;
      }
    } catch (e) {
      // 时间同步失败不致命，timeOffset 保持 0，进度外推会有偏差
      emit("error", { message: "sync_time_failed", error: String(e) });
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  // ===== WebSocket 消息处理 =====
  // 错误分类：把服务端错误信息映射为事件类型。
  // 成员收到 room_not_found：房主可能还没初始化房间，
  // 对照 VT 原版 ScheduledTask 不立即报错，由 memberTimer 每 2 秒重试，
  // 只有重试次数用完才 emit error。
  function emitServerError(errMsg) {
    errMsg = String(errMsg);
    if (errMsg.indexOf("password") >= 0 || errMsg.indexOf("密码") >= 0) {
      emit("error", { message: "password_error", error: errMsg });
    } else if (errMsg.indexOf("not found") >= 0 ||
               errMsg.indexOf("不存在") >= 0 ||
               errMsg.indexOf("room not exist") >= 0) {
      if (role === ROLE.MEMBER && joinRetryCount < MAX_JOIN_RETRIES) {
        // 静默重试，不 emit error
      } else {
        emit("error", { message: "room_not_found", error: errMsg });
      }
    } else {
      emit("error", { message: "server_error", error: errMsg });
    }
  }

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
      if (!msg) continue;
      msg = normalizeServerMsg(msg);
      if (!msg.method) continue;
      var data = msg.data || {};

      // 错误响应：服务端 WsErrorResponse 格式 { method, errorMessage }，
      // errorMessage 在顶层（兼容 data.errorMessage 的旧格式）
      var errMsg = null;
      if (typeof msg.errorMessage === "string" && msg.errorMessage !== "") {
        errMsg = msg.errorMessage;
      } else if (typeof data.errorMessage === "string" && data.errorMessage !== "") {
        errMsg = data.errorMessage;
      }
      if (errMsg !== null) {
        emitServerError(errMsg);
        continue;
      }
      if (data.error || data.code === "error" || msg.method === "error") {
        emitServerError(String(data.error || data.message || "unknown_error"));
        continue;
      }

      // 关键：服务端广播/响应统一为 RoomResponse 格式
      // { timestamp, Room: {...} }（go-server ws.go），房间数据嵌套在 data.Room，
      // 不展开则成员永远读不到 currentTime/paused 等播放状态
      if (data.Room && typeof data.Room === "object" && !Array.isArray(data.Room)) {
        data = data.Room;
      }

      if (msg.method === "/room/update" ||
          msg.method === "/room/update_member" ||
          msg.method === "/room/join") {
        if (typeof data.memberCount === "number") memberCount = data.memberCount;
        // 收到任何房间状态广播都说明 join 成功了
        if (role === ROLE.MEMBER) joinSucceeded = true;
        if (msg.method === "/room/join") {
          // join 成功响应通常不携带播放状态；只广播成员数与房间名，
          // 避免缺字段默认值把成员视频暂停/seek 到 0
          var joinData = { name: data.name || roomName, memberCount: memberCount };
          if (typeof data.currentTime === "number") joinData.currentTime = data.currentTime;
          if (typeof data.duration === "number") joinData.duration = data.duration;
          if (typeof data.paused === "boolean") joinData.paused = data.paused;
          if (typeof data.playbackRate === "number") joinData.playbackRate = data.playbackRate;
          if (typeof data.url === "string") joinData.url = data.url;
          var ts = data.lastUpdateServerTime;
          if (typeof ts !== "number") ts = data.lastUpdateClientTime;
          if (typeof ts === "number") joinData.lastUpdateServerTime = ts;
          emit("room_update", joinData);
        } else {
          emit("room_update", data);
        }
        // 房主收到成员心跳时，立即触发一次上报，让成员尽快拿到最新状态
        if (role === ROLE.MASTER && msg.method === "/room/update_member") {
          if (videoElement) {
            var v = videoElement;
            try {
              send({
                method: "/room/update",
                data: {
                  tempUser: tempUser,
                  password: password,
                  name: roomName,
                  playbackRate: v.playbackRate || 1,
                  currentTime: v.currentTime || 0,
                  paused: !!v.paused,
                  url: (typeof location !== "undefined" && location.href) || "",
                  lastUpdateClientTime: Date.now() / 1000 + timeOffset,
                  duration: v.duration || 0,
                  protected: !!password,
                  videoTitle: (typeof document !== "undefined" && document.title) || "",
                  sendLocalTimestamp: Date.now() / 1000,
                  m3u8Url: ""
                }
              });
            } catch (e) {}
          }
        }
      } else if (msg.method === "send_txtmsg") {
        emit("text_message", data);
      }
      // replay_timestamp / url_req / url_resp / m3u8_* 精简版忽略
    }
  }

  // ===== WebSocket 连接（主地址失败自动回退，断开后自动重连） =====
  function connectWs(urlIndex) {
    if (destroyed) return;
    if (typeof urlIndex !== "number") urlIndex = 0;
    if (urlIndex >= WS_URLS.length) {
      emit("error", { message: "ws_all_urls_failed" });
      // 所有 URL 都失败：进入重连流程
      scheduleReconnect();
      return;
    }
    try {
      ws = new WebSocket(WS_URLS[urlIndex]);
    } catch (e) {
      emit("error", { message: "ws_construct_failed", error: String(e) });
      scheduleReconnect();
      return;
    }

    ws.onopen = function () {
      wsReady = true;
      reconnectAttempts = 0; // 连接成功，重置重连计数
      emit("ws_open", {});
      // 成员：重连后需要重新 join（joinSucceeded 保持 false 让 memberTimer 驱动重试）
      if (role === ROLE.MEMBER && roomName) {
        joinSucceeded = false; // 重连后重新 join
        send({ method: "/room/join", data: { name: roomName, password: password } });
        if (!memberTimer) startMemberTimer();
      }
      // 房主：WS 连通后立即发一次 update 初始化房间（对照 VT 原版 vt.js:3566），
      // 避免成员 joinRoom 时收到 room_not_found；同时启动 2s 上报循环
      if (role === ROLE.MASTER && roomName) {
        sendUpdateOnce();
        if (!masterTimer) startMasterTimer();
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
      // 主动关闭（leaveRoom/destroy）：不 emit，不重连
      if (wasIntentional) return;
      // 连接阶段失败且有回退 URL：立即尝试下一个
      if (!wasReady && urlIndex + 1 < WS_URLS.length) {
        connectWs(urlIndex + 1);
        return;
      }
      emit("ws_close", { wasOpen: wasReady });
      // 非主动断开：进入自动重连流程
      scheduleReconnect();
    };
  }

  // ===== 自动重连调度 =====
  function scheduleReconnect() {
    if (destroyed) return;
    if (role === ROLE.NULL) return; // 已离开房间，不重连
    if (reconnectTimer) return;     // 已有重连任务在等待
    var delay = RECONNECT_DELAYS[
      Math.min(reconnectAttempts, RECONNECT_DELAYS.length - 1)
    ];
    reconnectAttempts++;
    emit("reconnecting", { attempt: reconnectAttempts, delayMs: delay });
    reconnectTimer = setTimeout(function () {
      reconnectTimer = null;
      if (destroyed || role === ROLE.NULL) return;
      connectWs(0);
    }, delay);
  }

  function clearReconnectTimer() {
    if (reconnectTimer) {
      try { clearTimeout(reconnectTimer); } catch (e) {}
      reconnectTimer = null;
    }
  }

  // ===== 房主上报循环（每 2 秒） =====
  // 构造一次 /room/update 上报负载。video 缺失时用默认值。
  function buildUpdatePayload() {
    var currentTime = 0, paused = true, playbackRate = 1, duration = 0;
    if (videoElement && videoElement._remote) {
      // 远程 video（子 frame iframe）：从 postMessage 上报的状态读取
      if (lastVideoState) {
        currentTime = lastVideoState.currentTime || 0;
        paused = !!lastVideoState.paused;
        playbackRate = lastVideoState.playbackRate || 1;
        duration = lastVideoState.duration || 0;
      }
    } else if (videoElement) {
      // 主 frame 直接引用的 video 元素
      try {
        currentTime = videoElement.currentTime || 0;
        paused = !!videoElement.paused;
        playbackRate = videoElement.playbackRate || 1;
        duration = videoElement.duration || 0;
      } catch (e) {}
    }
    return {
      tempUser: tempUser,
      password: password,
      name: roomName,
      playbackRate: playbackRate,
      currentTime: currentTime,
      paused: paused,
      url: (typeof location !== "undefined" && location.href) || "",
      lastUpdateClientTime: Date.now() / 1000 + timeOffset,
      duration: duration,
      protected: !!password,
      videoTitle: (typeof document !== "undefined" && document.title) || "",
      sendLocalTimestamp: Date.now() / 1000,
      m3u8Url: ""
    };
  }

  // 立即发送一次 /room/update（房主初始化房间用，对照 VT 原版 vt.js:3566）
  function sendUpdateOnce() {
    send({ method: "/room/update", data: buildUpdatePayload() });
  }

  function startMasterTimer() {
    stopMasterTimer();
    masterTimer = setInterval(function () {
      if (role !== ROLE.MASTER) return;
      sendUpdateOnce();
    }, 2000);
  }

  function stopMasterTimer() {
    if (masterTimer) {
      try { clearInterval(masterTimer); } catch (e) {}
      masterTimer = null;
    }
  }

  // ===== 成员心跳循环（每 2 秒） =====
  // 对照 VT 原版 ScheduledTask：每 2 秒发 /room/update_member 保活，
  // 同时在 join 尚未成功时自动重试 /room/join（房主可能还没初始化房间）。
  function startMemberTimer() {
    stopMemberTimer();
    // 立即发一次 join（WS 已 open 时生效；未 open 时 onopen 会补发）
    if (ws && ws.readyState === 1) {
      send({ method: "/room/join", data: { name: roomName, password: password } });
    }
    memberTimer = setInterval(function () {
      if (role !== ROLE.MEMBER || !roomName) return;
      // join 尚未成功：重试 join（房主可能刚初始化房间）
      if (!joinSucceeded) {
        if (joinRetryCount >= MAX_JOIN_RETRIES) {
          emit("error", { message: "room_not_found", error: "重试超时，房间可能不存在" });
          stopMemberTimer();
          return;
        }
        joinRetryCount++;
        send({ method: "/room/join", data: { name: roomName, password: password } });
      }
      // 始终发送成员心跳，让服务器知道成员在线
      send({
        method: "/room/update_member",
        data: {
          password: password,
          roomName: roomName,
          sendLocalTimestamp: Date.now() / 1000,
          userId: tempUser,
          isLoadding: false,
          currentUrl: (typeof location !== "undefined" && location.href) || ""
        }
      });
    }, 2000);
  }

  function stopMemberTimer() {
    if (memberTimer) {
      try { clearInterval(memberTimer); } catch (e) {}
      memberTimer = null;
    }
  }

  // ===== video 元素轮询 =====
  // 递归查找 video 元素，遍历同源 iframe（跨域 iframe contentDocument 无法访问，
  // try-catch 跳过）。VT 原版靠油猴 @match *://*/* 在每个 iframe 注入，
  // 我们用递归同源查找模拟，覆盖绝大多数影视站播放器 iframe 场景。
  function findVideoDeep(doc) {
    doc = doc || document;
    try {
      var v = doc.querySelector("video");
      if (v) return v;
      var iframes = doc.querySelectorAll("iframe");
      for (var i = 0; i < iframes.length; i++) {
        try {
          var sub = iframes[i].contentDocument;
          if (sub) {
            v = findVideoDeep(sub);
            if (v) return v;
          }
        } catch (e) {} // 跨域 iframe，跳过
      }
    } catch (e) {}
    return null;
  }

  // 当 createRoom/joinRoom 时 video 尚未出现，启动轮询自动绑定
  function startVideoPolling() {
    stopVideoPolling();
    videoPollTimer = setInterval(function () {
      if (videoElement) {
        stopVideoPolling();
        return;
      }
      var el = findVideoDeep(document);
      if (el) {
        videoElement = el;
        stopVideoPolling();
      }
    }, 500);
  }

  function stopVideoPolling() {
    if (videoPollTimer) {
      try { clearInterval(videoPollTimer); } catch (e) {}
      videoPollTimer = null;
    }
  }

  // 手动设置 video 元素（供 Dart 侧调用）
  function setVideo(videoEl) {
    videoElement = videoEl || null;
    if (videoElement) stopVideoPolling();
  }

  // ===== 成员同步逻辑（只注册一次，靠 role 守卫） =====
  // 收到 room_update 时：外推真实进度，差 > 1s 则 seek；同步 paused/playbackRate
  // 守卫：仅当更新携带明确的播放字段时才动视频，避免 join 等不完整更新误伤
  on("room_update", function (room) {
    if (role !== ROLE.MEMBER || !videoElement || !room) return;
    var isRemote = !!videoElement._remote;
    var v = videoElement;
    try {
      // 外推真实进度：realCurrent = currentTime + (now - lastUpdateServerTime) * rate
      var hasValidTime = typeof room.currentTime === "number" &&
          typeof room.lastUpdateServerTime === "number" &&
          room.lastUpdateServerTime > 0;
      if (hasValidTime) {
        var realCurrent = room.currentTime;
        var lastServer = room.lastUpdateServerTime;
        var elapsed = Date.now() / 1000 + timeOffset - lastServer;
        if (elapsed >= 0 && elapsed < 3600) {
          realCurrent = room.currentTime + elapsed * (room.playbackRate || 1);
        }
        // 远程 video：通过 postMessage seek；本地 video：直接设 currentTime
        if (isRemote) {
          var localTime = lastVideoState ? lastVideoState.currentTime : 0;
          if (Math.abs(localTime - realCurrent) > 1) {
            sendControl("seek", realCurrent);
          }
        } else if (typeof v.currentTime === "number" &&
            Math.abs(v.currentTime - realCurrent) > 1) {
          v.currentTime = realCurrent;
        }
      }
      if (typeof room.paused === "boolean") {
        if (isRemote) {
          var localPaused = lastVideoState ? !!lastVideoState.paused : true;
          if (localPaused !== room.paused) {
            sendControl(room.paused ? "pause" : "play");
          }
        } else if (v.paused !== room.paused) {
          if (room.paused) {
            try { v.pause(); } catch (e) {}
          } else {
            try { v.play().catch(function () {}); } catch (e) {}
          }
        }
      }
      if (typeof room.playbackRate === "number") {
        if (isRemote) {
          var localRate = lastVideoState ? lastVideoState.playbackRate : 1;
          if (localRate !== room.playbackRate) {
            sendControl("rate", room.playbackRate);
          }
        } else if (v.playbackRate !== room.playbackRate) {
          try { v.playbackRate = room.playbackRate; } catch (e) {}
        }
      }
    } catch (e) {
      emit("error", { message: "member_sync_error", error: String(e) });
    }
  });

  // ===== 公开 API =====

  async function createRoom(name, pwd, videoEl, nickname) {
    if (!name) throw new Error("room name required");
    destroyed = false;
    stopMasterTimer();
    stopMemberTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MASTER;
    videoElement = videoEl || null;
    memberCount = 1;
    joinSucceeded = false;
    joinRetryCount = 0;
    if (nickname) senderName = String(nickname);
    // syncTime 与 connectWs 并行：减少房间初始化延迟
    // （syncTime 失败不阻塞，timeOffset 保持 0）
    var syncP = syncTime();
    if (!ws) connectWs(0);
    startMasterTimer();
    if (!videoElement) startVideoPolling();
    await syncP;
  }

  async function joinRoom(name, pwd, videoEl, nickname) {
    if (!name) throw new Error("room name required");
    destroyed = false;
    stopMasterTimer();
    stopMemberTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MEMBER;
    videoElement = videoEl || null;
    memberCount = 0;
    joinSucceeded = false;
    joinRetryCount = 0;
    if (nickname) senderName = String(nickname);
    // syncTime 与 connectWs 并行
    var syncP = syncTime();
    if (!ws) connectWs(0);
    // join 由 startMemberTimer 驱动：WS open 后立即发 join，
    // 之后每 2 秒重试直到成功（对照 VT 原版 ScheduledTask）
    startMemberTimer();
    if (!videoElement) startVideoPolling();
    await syncP;
  }

  function leaveRoom() {
    intentionalClose = true;
    clearReconnectTimer();
    reconnectAttempts = 0;
    stopMasterTimer();
    stopMemberTimer();
    stopVideoPolling();
    if (ws) { try { ws.close(); } catch (e) {} }
    ws = null;
    wsReady = false;
    roomName = "";
    password = "";
    role = ROLE.NULL;
    memberCount = 0;
    joinSucceeded = false;
    joinRetryCount = 0;
  }

  function sendText(msg) {
    if (!ws || !wsReady) {
      emit("error", { message: "ws_not_open" });
      return "";
    }
    var id = uuid();
    send({
      method: "send_txtmsg",
      data: { msg: String(msg), id: id, voiceId: senderName || "" }
    });
    return id;
  }

  // 设置聊天昵称（发送消息时写入 voiceId，接收端据此显示发送者）
  function setNickname(name) {
    senderName = name ? String(name) : "";
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
    clearReconnectTimer();
    reconnectAttempts = 0;
    stopMasterTimer();
    stopMemberTimer();
    stopVideoPolling();
    if (ws) { try { ws.close(); } catch (e) {} }
    ws = null;
    wsReady = false;
    roomName = "";
    password = "";
    role = ROLE.NULL;
    memberCount = 0;
    joinSucceeded = false;
    joinRetryCount = 0;
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
      setNickname: setNickname,
      getState: getState,
      setVideo: setVideo,
      flushEvents: flushEvents,
      destroy: destroy
    };
  }
})();

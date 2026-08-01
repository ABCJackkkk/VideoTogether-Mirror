// ==UserScript==
// @name         VtLite 一起看
// @namespace    https://github.com/avideotogether/vt-lite
// @version      1.0.0
// @description  异地同看视频 - 在任意视频页面注入同步控件，跟 Android App / PWA 互通
// @author       avideotogether
// @match        *://*/*
// @grant        none
// @run-at       document-idle
// @license      MIT
// ==/UserScript==

(function () {
  "use strict";

  // 防止重复注入
  if (window.__VtLiteUserScript) return;
  window.__VtLiteUserScript = true;

  // ============ 配置 ============
  var API_HOST = "https://vt.panghair.com:5000";
  var WS_URLS = [
    "wss://vt.panghair.com:5000/ws?language=zh-cn",
    "wss://dogyun.2gether.video/ws?language=zh-cn"
  ];
  var ROLE = { NULL: "null", MASTER: "master", MEMBER: "member" };

  // ============ 状态 ============
  var ws = null;
  var wsReady = false;
  var timeOffset = 0;
  var roomName = "";
  var password = "";
  var role = ROLE.NULL;
  var memberCount = 0;
  var masterTimer = null;
  var memberTimer = null;
  var videoElement = null;
  var intentionalClose = false;
  var destroyed = false;
  var senderName = ""; // 聊天昵称（发送时写入 voiceId）
  var tempUser = "vt_" + Date.now() + "_" + uuid();
  var listeners = {};
  var messages = []; // 聊天消息缓存

  // ===== 自动重连状态 =====
  var reconnectTimer = null;
  var reconnectAttempts = 0;
  var RECONNECT_DELAYS = [1000, 2000, 4000, 8000, 16000, 30000];

  // ============ 工具函数 ============
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
    listeners[event] = listeners[event].filter(function (fn) { return fn !== cb; });
  }

  function emit(event, data) {
    var cbs = listeners[event];
    if (cbs) {
      cbs.slice().forEach(function (cb) {
        try { cb(data); } catch (e) {}
      });
    }
  }

  function send(obj) {
    if (ws && ws.readyState === 1) {
      try { ws.send(JSON.stringify(obj)); } catch (e) {}
    }
  }

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
      emit("error", { message: "sync_time_failed", error: String(e) });
    } finally {
      if (timer) clearTimeout(timer);
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

  // ============ WebSocket 消息处理 ============
  function handleWsMessage(raw) {
    var lines = String(raw).split("\n");
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line) continue;
      var msg;
      try { msg = JSON.parse(line); } catch (e) { continue; }
      if (!msg) continue;
      msg = normalizeServerMsg(msg);
      if (!msg.method) continue;
      var data = msg.data || {};
      // 错误响应：VT 服务器返回 { method: "...", data: { errorMessage: "..." } }
      if (data.errorMessage != null || data.error || msg.method === "error") {
        var errMsg = String(data.errorMessage || data.error || data.message || "unknown_error");
        if (errMsg.indexOf("password") >= 0 || errMsg.indexOf("密码") >= 0) {
          emit("error", { message: "password_error", error: errMsg });
        } else if (errMsg.indexOf("not found") >= 0 ||
                   errMsg.indexOf("不存在") >= 0 ||
                   errMsg.indexOf("room not exist") >= 0) {
          emit("error", { message: "room_not_found", error: errMsg });
        } else {
          emit("error", { message: "server_error", error: errMsg });
        }
        continue;
      }
      if (msg.method === "/room/update" ||
          msg.method === "/room/update_member" ||
          msg.method === "/room/join") {
        if (typeof data.memberCount === "number") memberCount = data.memberCount;
        if (msg.method === "/room/join") {
          // join 成功响应通常不携带播放状态；只广播成员数与房间名，
          // 避免缺字段默认值把成员视频暂停/seek 到 0
          var joinData = { name: data.name || roomName, memberCount: memberCount };
          if (typeof data.currentTime === "number") joinData.currentTime = data.currentTime;
          if (typeof data.paused === "boolean") joinData.paused = data.paused;
          if (typeof data.playbackRate === "number") joinData.playbackRate = data.playbackRate;
          var ts = data.lastUpdateServerTime;
          if (typeof ts !== "number") ts = data.lastUpdateClientTime;
          if (typeof ts === "number") joinData.lastUpdateServerTime = ts;
          emit("room_update", joinData);
        } else {
          emit("room_update", data);
        }
      } else if (msg.method === "send_txtmsg") {
        var msgId = data.id || "";
        // 按消息 id 去重：发送方本地已回显过，服务端广播回来不再重复显示
        var exists = messages.some(function (m) { return m.id === msgId; });
        if (!exists) {
          messages.push({
            text: data.msg || "",
            id: msgId,
            ts: Date.now(),
            sender: data.voiceId || ""
          });
        }
        emit("text_message", data);
      }
    }
  }

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
      reconnectAttempts = 0; // 连接成功，重置重连计数
      emit("ws_open", {});
      if (role === ROLE.MEMBER && roomName) {
        send({ method: "/room/join", data: { name: roomName, password: password } });
        if (!memberTimer) startMemberTimer();
      }
      if (role === ROLE.MASTER && roomName) {
        sendUpdateOnce();
        if (!masterTimer) startMasterTimer();
      }
    };
    ws.onmessage = function (e) {
      try { handleWsMessage(e.data); } catch (err) {
        emit("error", { message: "ws_message_handler_error", error: String(err) });
      }
    };
    ws.onerror = function () {};
    ws.onclose = function () {
      var wasReady = wsReady;
      var wasIntentional = intentionalClose;
      intentionalClose = false;
      ws = null;
      wsReady = false;
      if (wasIntentional) return;
      if (!wasReady && urlIndex + 1 < WS_URLS.length) {
        connectWs(urlIndex + 1);
        return;
      }
      emit("ws_close", { wasOpen: wasReady });
      // 非主动断开：进入自动重连流程
      scheduleReconnect();
    };
  }

  // ============ 自动重连调度 ============
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

  // 立即发送一次 /room/update（房主初始化房间用）
  function sendUpdateOnce() {
    send({ method: "/room/update", data: buildUpdatePayload() });
  }

  // 构造一次 /room/update 上报负载。video 缺失时用默认值。
  function buildUpdatePayload() {
    var currentTime = 0, paused = true, playbackRate = 1, duration = 0;
    if (videoElement) {
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

  // ============ 房主上报循环 ============
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

  // ============ 成员心跳循环（每 2 秒发送 /room/update_member） ============
  // 协议要求成员定期上报，否则服务端不认为成员在线，memberCount 不会更新
  function startMemberTimer() {
    stopMemberTimer();
    memberTimer = setInterval(function () {
      if (role !== ROLE.MEMBER || !roomName) return;
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

  // ============ 成员同步逻辑 ============
  // 守卫：仅当更新携带明确的播放字段时才动视频，避免 join 等不完整更新误伤
  on("room_update", function (room) {
    if (role !== ROLE.MEMBER || !videoElement || !room) return;
    var v = videoElement;
    try {
      var hasValidTime = typeof room.currentTime === "number" &&
          typeof room.lastUpdateServerTime === "number" &&
          room.lastUpdateServerTime > 0;
      if (hasValidTime) {
        var realCurrent = room.currentTime +
          (Date.now() / 1000 + timeOffset - room.lastUpdateServerTime) *
          (room.playbackRate || 1);
        // 仅在合理范围内外推（0~3600s），避免时间戳异常导致跳到几十亿秒
        var elapsed = Date.now() / 1000 + timeOffset - room.lastUpdateServerTime;
        if (elapsed >= 0 && elapsed < 3600 &&
            typeof v.currentTime === "number" &&
            Math.abs(v.currentTime - realCurrent) > 1) {
          v.currentTime = realCurrent;
        }
      }
      if (typeof room.paused === "boolean" && v.paused !== room.paused) {
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

  // ============ 公开 API ============
  async function createRoom(name, pwd, videoEl, nickname) {
    if (!name) throw new Error("房间名必填");
    destroyed = false;
    clearReconnectTimer();
    stopMasterTimer();
    stopMemberTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MASTER;
    videoElement = videoEl || null;
    memberCount = 1;
    if (nickname) senderName = String(nickname);
    await syncTime();
    if (!ws) connectWs(0);
    startMasterTimer();
  }

  async function joinRoom(name, pwd, videoEl, nickname) {
    if (!name) throw new Error("房间名必填");
    destroyed = false;
    clearReconnectTimer();
    stopMasterTimer();
    stopMemberTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MEMBER;
    videoElement = videoEl || null;
    memberCount = 0;
    if (nickname) senderName = String(nickname);
    await syncTime();
    if (!ws) connectWs(0);
    send({ method: "/room/join", data: { name: roomName, password: password } });
    startMemberTimer();
  }

  function leaveRoom() {
    intentionalClose = true;
    clearReconnectTimer();
    reconnectAttempts = 0;
    stopMasterTimer();
    stopMemberTimer();
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

  // 暴露到 window 方便调试
  window.VtLite = {
    on: on, off: off,
    createRoom: createRoom, joinRoom: joinRoom,
    leaveRoom: leaveRoom, sendText: sendText,
    setNickname: setNickname,
    getState: getState, destroy: destroy
  };

  // ============ 自动寻找 video 元素 ============
  // 在 B 站/YouTube/腾讯等站点上，视频元素可能在页面加载后才出现
  function findVideoElement() {
    // 优先找 main video
    var v = document.querySelector("video");
    if (v) return v;
    // YouTube 特殊处理
    var yt = document.querySelector(".html5-main-video");
    if (yt) return yt;
    // B 站特殊处理
    var bili = document.querySelector("#bilibili-player video");
    if (bili) return bili;
    return null;
  }

  // 等 video 元素出现（最多等 30 秒）
  function waitForVideo(cb) {
    var tries = 0;
    function check() {
      var v = findVideoElement();
      if (v) { cb(v); return; }
      tries++;
      if (tries > 60) { // 30 秒
        cb(null);
        return;
      }
      setTimeout(check, 500);
    }
    check();
  }

  // ============ UI 面板 ============
  // 样式注入
  function injectStyles() {
    var css = `
.vtl-panel {
  position: fixed;
  bottom: 16px;
  right: 16px;
  z-index: 2147483647;
  width: 300px;
  background: #F7F5F2;
  border: 1px solid #D4C8B8;
  border-radius: 4px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.12);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 13px;
  color: #2C2418;
  overflow: hidden;
}
.vtl-header {
  padding: 10px 12px;
  background: #8B7355;
  color: #F7F5F2;
  cursor: pointer;
  display: flex;
  justify-content: space-between;
  align-items: center;
  user-select: none;
}
.vtl-header-title {
  font-weight: 600;
  letter-spacing: 0.5px;
}
.vtl-header-status {
  font-size: 11px;
  opacity: 0.85;
}
.vtl-body {
  padding: 12px;
  display: block;
}
.vtl-body.collapsed {
  display: none;
}
.vtl-field {
  margin-bottom: 8px;
}
.vtl-field label {
  display: block;
  font-size: 11px;
  color: #8B7355;
  margin-bottom: 4px;
  letter-spacing: 0.3px;
}
.vtl-field input {
  width: 100%;
  box-sizing: border-box;
  padding: 6px 8px;
  border: 1px solid #D4C8B8;
  border-radius: 3px;
  background: #FFFFFF;
  color: #2C2418;
  font-size: 13px;
  font-family: inherit;
}
.vtl-field input:focus {
  outline: none;
  border-color: #8B7355;
}
.vtl-btn {
  width: 100%;
  padding: 8px;
  background: #2C2418;
  color: #F7F5F2;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  font-size: 13px;
  font-family: inherit;
  letter-spacing: 0.5px;
}
.vtl-btn:disabled {
  background: #C4B8A8;
  cursor: not-allowed;
}
.vtl-tab-row {
  display: flex;
  margin-bottom: 10px;
  border-bottom: 1px solid #D4C8B8;
}
.vtl-tab {
  flex: 1;
  padding: 6px;
  text-align: center;
  cursor: pointer;
  color: #8B7355;
  font-size: 12px;
  border-bottom: 2px solid transparent;
}
.vtl-tab.active {
  color: #2C2418;
  border-bottom-color: #8B7355;
  font-weight: 600;
}
.vtl-msgs {
  max-height: 160px;
  overflow-y: auto;
  padding: 6px;
  background: #FFFFFF;
  border: 1px solid #E8DFD0;
  border-radius: 3px;
  margin-bottom: 8px;
  font-size: 12px;
}
.vtl-msg {
  margin-bottom: 4px;
  word-wrap: break-word;
}
.vtl-msg-meta {
  font-size: 10px;
  color: #8B7355;
  margin-right: 6px;
}
.vtl-chat-input {
  display: flex;
  gap: 4px;
}
.vtl-chat-input input {
  flex: 1;
  padding: 5px 8px;
  border: 1px solid #D4C8B8;
  border-radius: 3px;
  font-size: 12px;
  font-family: inherit;
}
.vtl-chat-input button {
  padding: 5px 10px;
  background: #8B7355;
  color: #F7F5F2;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  font-size: 12px;
}
.vtl-info {
  font-size: 11px;
  color: #8B7355;
  margin-top: 6px;
  line-height: 1.5;
}
.vtl-error {
  color: #B8431D;
  font-size: 11px;
  margin-top: 4px;
}
`;
    var style = document.createElement("style");
    style.textContent = css;
    document.head.appendChild(style);
  }

  // 构建 UI
  function buildPanel() {
    var panel = document.createElement("div");
    panel.className = "vtl-panel";
    panel.innerHTML = `
      <div class="vtl-header" id="vtlHeader">
        <span class="vtl-header-title">一起看</span>
        <span class="vtl-header-status" id="vtlStatus">未连接</span>
      </div>
      <div class="vtl-body" id="vtlBody">
        <div class="vtl-tab-row">
          <div class="vtl-tab active" data-tab="create">创建房间</div>
          <div class="vtl-tab" data-tab="join">加入房间</div>
        </div>
        <div class="vtl-field">
          <label>昵称</label>
          <input type="text" id="vtlName" placeholder="你的昵称" />
        </div>
        <div class="vtl-field">
          <label>房间名</label>
          <input type="text" id="vtlRoom" placeholder="房间名" />
        </div>
        <div class="vtl-field">
          <label>密码（可选）</label>
          <input type="password" id="vtlPwd" placeholder="留空表示无密码" />
        </div>
        <button class="vtl-btn" id="vtlAction">创建房间</button>
        <div class="vtl-info" id="vtlInfo"></div>
        <div class="vtl-error" id="vtlError"></div>
        <hr style="border:none;border-top:1px solid #E8DFD0;margin:10px 0;" />
        <div class="vtl-msgs" id="vtlMsgs"></div>
        <div class="vtl-chat-input">
          <input type="text" id="vtlChatInput" placeholder="发消息..." />
          <button id="vtlChatSend">发送</button>
        </div>
      </div>
    `;
    document.body.appendChild(panel);

    // 折叠/展开
    var body = panel.querySelector("#vtlBody");
    var header = panel.querySelector("#vtlHeader");
    var collapsed = false;
    header.addEventListener("click", function () {
      collapsed = !collapsed;
      body.style.display = collapsed ? "none" : "block";
    });

    // Tab 切换
    var currentTab = "create";
    var tabs = panel.querySelectorAll(".vtl-tab");
    var actionBtn = panel.querySelector("#vtlAction");
    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        tabs.forEach(function (t) { t.classList.remove("active"); });
        tab.classList.add("active");
        currentTab = tab.dataset.tab;
        actionBtn.textContent = currentTab === "create" ? "创建房间" : "加入房间";
      });
    });

    // 创建/加入
    actionBtn.addEventListener("click", async function () {
      var name = panel.querySelector("#vtlName").value.trim();
      var room = panel.querySelector("#vtlRoom").value.trim();
      var pwd = panel.querySelector("#vtlPwd").value.trim();
      var errEl = panel.querySelector("#vtlError");
      errEl.textContent = "";

      if (!name) { errEl.textContent = "请输入昵称"; return; }
      if (!room) { errEl.textContent = "请输入房间名"; return; }

      actionBtn.disabled = true;
      actionBtn.textContent = "处理中...";

      var v = findVideoElement();
      if (!v) {
        errEl.textContent = "未找到视频元素，请先打开视频页面";
        actionBtn.disabled = false;
        actionBtn.textContent = currentTab === "create" ? "创建房间" : "加入房间";
        return;
      }

      try {
        var nickname = name; // 聊天昵称
        if (currentTab === "create") {
          await createRoom(room, pwd, v, nickname);
        } else {
          await joinRoom(room, pwd, v, nickname);
        }
        panel.querySelector("#vtlInfo").textContent =
          (currentTab === "create" ? "已创建" : "已加入") + " 房间：" + room;
      } catch (e) {
        errEl.textContent = "失败：" + e.message;
      }
      actionBtn.disabled = false;
      actionBtn.textContent = currentTab === "create" ? "创建房间" : "加入房间";
    });

    // 发送消息
    function sendChat() {
      var input = panel.querySelector("#vtlChatInput");
      var text = input.value.trim();
      if (!text) return;
      // 本地昵称：发送时写入 voiceId，接收端据此显示发送者
      var name = panel.querySelector("#vtlName").value.trim() || "匿名";
      setNickname(name);
      var id = sendText(text);
      // 本地回显（服务端广播回来时按 id 去重）
      messages.push({ text: text, id: id || uuid(), ts: Date.now(), self: true, sender: name });
      renderMessages();
      input.value = "";
    }
    panel.querySelector("#vtlChatSend").addEventListener("click", sendChat);
    panel.querySelector("#vtlChatInput").addEventListener("keydown", function (e) {
      if (e.key === "Enter") sendChat();
    });

    // 状态更新
    on("ws_open", function () {
      panel.querySelector("#vtlStatus").textContent = "已连接";
    });
    on("ws_close", function () {
      panel.querySelector("#vtlStatus").textContent = "已断开";
    });
    on("reconnecting", function (e) {
      panel.querySelector("#vtlStatus").textContent =
        "重连中(" + (e && e.attempt ? e.attempt : 1) + ")";
    });
    on("room_update", function (data) {
      var count = data.memberCount || 0;
      panel.querySelector("#vtlStatus").textContent = "在线 " + count + " 人";
    });
    on("text_message", function () {
      renderMessages();
    });
    on("error", function (e) {
      if (e && e.message) {
        panel.querySelector("#vtlError").textContent = "错误：" + userFriendlyError(e.message, e.error);
      }
    });

    function userFriendlyError(code, detail) {
      switch (code) {
        case "password_error": return "房间密码错误";
        case "room_not_found": return "房间不存在，请检查房间名";
        case "server_error": return "服务器错误：" + (detail || "");
        case "ws_all_urls_failed": return "无法连接同步服务器，请检查网络";
        case "ws_construct_failed": return "WebSocket 创建失败：" + (detail || "");
        case "ws_not_open": return "连接未建立，请稍候";
        case "sync_time_failed": return "时间同步失败，进度可能有偏差";
        case "member_sync_error": return "同步播放状态失败";
        default: return detail || code || "未知错误";
      }
    }

    function renderMessages() {
      var box = panel.querySelector("#vtlMsgs");
      box.innerHTML = "";
      messages.slice(-50).forEach(function (m) {
        var div = document.createElement("div");
        div.className = "vtl-msg";
        var time = new Date(m.ts).toLocaleTimeString().slice(0, 5);
        var sender = m.sender
          ? '<span class="vtl-msg-meta">' + time + " " + escapeHtml(m.sender) + "</span>"
          : '<span class="vtl-msg-meta">' + time + "</span>";
        div.innerHTML = sender + escapeHtml(m.text);
        box.appendChild(div);
      });
      box.scrollTop = box.scrollHeight;
    }

    function escapeHtml(s) {
      return String(s).replace(/[&<>"']/g, function (c) {
        return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
      });
    }
  }

  // ============ 启动 ============
  function start() {
    if (!document.body) {
      setTimeout(start, 200);
      return;
    }
    injectStyles();
    buildPanel();
  }

  // 等 DOM 就绪
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();

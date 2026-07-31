// 复用 Flutter 项目中的 VtLite 脚本（完全相同，零修改）
// 直接从 ../assets/vt-lite.js 复制过来，浏览器原生兼容
(function () {
  if (typeof window !== "undefined" && window.VtLite) return;

  var API_HOST = "https://vt.panghair.com:5000";
  var WS_URLS = [
    "wss://vt.panghair.com:5000/ws?language=zh-cn",
    "wss://dogyun.2gether.video/ws?language=zh-cn"
  ];

  var ROLE = { NULL: "null", MASTER: "master", MEMBER: "member" };

  var ws = null;
  var wsReady = false;
  var timeOffset = 0;
  var roomName = "";
  var password = "";
  var role = ROLE.NULL;
  var memberCount = 0;
  var videoElement = null;
  var masterTimer = null;
  var tempUser = "";
  var urlIndex = 0;
  var intentionalClose = false;
  var destroyed = false;

  var listeners = {};

  function on(event, cb) {
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(cb);
  }
  function off(event, cb) {
    if (!listeners[event]) return;
    listeners[event] = listeners[event].filter(function (f) { return f !== cb; });
  }
  function emit(event, data) {
    (listeners[event] || []).forEach(function (cb) {
      try { cb(data); } catch (e) {}
    });
  }

  function uuid() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      var v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  async function syncTime() {
    try {
      var res = await fetch(API_HOST + "/timestamp", { cache: "no-store" });
      var serverTs = parseFloat(await res.text());
      if (!isNaN(serverTs)) {
        timeOffset = serverTs - Date.now() / 1000;
      }
    } catch (e) {
      emit("error", { message: "time_sync_failed", error: String(e) });
    }
  }

  function send(obj) {
    if (!ws || !wsReady) return;
    try { ws.send(JSON.stringify(obj)); } catch (e) {}
  }

  function handleWsMessage(evt) {
    if (!evt || typeof evt.data !== "string") return;
    evt.data.split("\n").forEach(function (line) {
      if (!line) return;
      var msg;
      try { msg = JSON.parse(line); } catch (e) { return; }
      if (!msg) return;

      if (msg.type === "send_txtmsg") {
        emit("text_message", {
          sender: msg.data.user || "",
          text: msg.data.msg || "",
          timestamp: Date.now() / 1000
        });
        return;
      }

      if (msg.method === "/room/update" || msg.method === "/room/join") {
        var data = msg.data || {};
        memberCount = data.connectedCount || memberCount;
        emit("room_update", {
          name: data.name || roomName,
          currentTime: data.currentTime || 0,
          paused: data.paused !== false,
          playbackRate: data.playbackRate || 1,
          duration: data.duration || 0,
          lastUpdateServerTime: data.lastUpdateClientTime || 0,
          memberCount: memberCount,
          url: data.url || ""
        });
        return;
      }
    });
  }

  function connectWs(idx) {
    urlIndex = idx;
    if (idx >= WS_URLS.length) {
      emit("error", { message: "all_ws_failed" });
      return;
    }
    try { ws = new WebSocket(WS_URLS[idx]); } catch (e) {
      connectWs(idx + 1); return;
    }
    ws.onopen = function () {
      wsReady = true;
      tempUser = uuid();
      emit("ws_open", {});
      if (role === ROLE.MEMBER) {
        send({ method: "/room/join", data: { name: roomName, password: password } });
      }
    };
    ws.onmessage = handleWsMessage;
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
    };
  }

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
      } catch (e) { return; }
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
          protected: !!password,
          videoTitle: (typeof document !== "undefined" && document.title) || "",
          sendLocalTimestamp: Date.now() / 1000,
          m3u8Url: ""
        }
      });
    }, 2000);
  }

  function stopMasterTimer() {
    if (masterTimer) { try { clearInterval(masterTimer); } catch (e) {} masterTimer = null; }
  }

  on("room_update", function (room) {
    if (role !== ROLE.MEMBER || !videoElement || !room) return;
    var v = videoElement;
    try {
      var realCurrent = room.currentTime +
        (Date.now() / 1000 + timeOffset - (room.lastUpdateServerTime || 0)) * (room.playbackRate || 1);
      if (typeof v.currentTime === "number" && Math.abs(v.currentTime - realCurrent) > 1) {
        v.currentTime = realCurrent;
      }
      if (v.paused !== !!room.paused) {
        if (room.paused) { try { v.pause(); } catch (e) {} }
        else { try { v.play().catch(function () {}); } catch (e) {} }
      }
      if (typeof room.playbackRate === "number" && v.playbackRate !== room.playbackRate) {
        try { v.playbackRate = room.playbackRate; } catch (e) {}
      }
    } catch (e) {
      emit("error", { message: "member_sync_error", error: String(e) });
    }
  });

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
    send({ method: "/room/join", data: { name: roomName, password: password } });
  }

  function leaveRoom() {
    intentionalClose = true;
    stopMasterTimer();
    if (ws) { try { ws.close(); } catch (e) {} }
    ws = null; wsReady = false;
    roomName = ""; password = "";
    role = ROLE.NULL; memberCount = 0;
  }

  function sendText(msg) {
    if (!ws || !wsReady) { emit("error", { message: "ws_not_open" }); return; }
    send({ method: "send_txtmsg", data: { msg: String(msg), id: uuid(), voiceId: "" } });
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
    ws = null; wsReady = false;
    roomName = ""; password = "";
    role = ROLE.NULL; memberCount = 0;
    videoElement = null;
    Object.keys(listeners).forEach(function (k) { delete listeners[k]; });
  }

  if (typeof window !== "undefined") {
    window.VtLite = {
      on: on, off: off,
      createRoom: createRoom,
      joinRoom: joinRoom,
      leaveRoom: leaveRoom,
      sendText: sendText,
      getState: getState,
      destroy: destroy
    };
  }
})();

"use strict";

(function () {
  const U = window.AdminUI, R = window.Router, { el, button } = U;
  let active = null;
  const pollInterval = 4000;

  function formatTime(val) {
    if (!val) return "—";
    const d = new Date(String(val) + (/(?:Z|[+-]\d{2}:\d{2})$/i.test(val) ? "" : "Z"));
    if (isNaN(d.getTime())) return "—";
    return new Intl.DateTimeFormat("vi-VN", {
      hour: "2-digit",
      minute: "2-digit",
      day: "2-digit",
      month: "2-digit"
    }).format(d);
  }

  function renderStatusBadge(status) {
    switch (status) {
      case "RESOLVED":
        return el("span", "badge bg-success", "Đã giải quyết");
      case "IN_PROGRESS":
        return el("span", "badge bg-primary", "Đang xử lý");
      default:
        return el("span", "badge bg-warning text-dark", "Chờ tiếp nhận");
    }
  }

  function renderSeverityBadge(sev) {
    switch (sev) {
      case "CRITICAL":
        return el("span", "badge bg-danger", "Khẩn cấp");
      case "WARNING":
        return el("span", "badge bg-warning text-dark", "Cảnh báo");
      default:
        return el("span", "badge bg-secondary", "Thông tin");
    }
  }


  function playEmergencyBeep() {
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      const ctx = new AudioCtx();
      if (ctx.state === "suspended") ctx.resume();

      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sawtooth";

      // Dual siren tone: 880Hz -> 1175Hz -> 880Hz
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      osc.frequency.setValueAtTime(1175, ctx.currentTime + 0.15);
      osc.frequency.setValueAtTime(880, ctx.currentTime + 0.3);
      osc.frequency.setValueAtTime(1175, ctx.currentTime + 0.45);

      gain.gain.setValueAtTime(0.3, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.6);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 0.6);
    } catch {}
  }

  function showCriticalEmergencyAlert(item) {
    let alertHost = document.getElementById("critical-emergency-alert-bar");
    if (!alertHost) {
      alertHost = el("div", "position-fixed top-0 start-50 translate-middle-x mt-3 z-3");
      alertHost.id = "critical-emergency-alert-bar";
      alertHost.style.zIndex = "99999";
      alertHost.style.maxWidth = "600px";
      alertHost.style.width = "90%";
      document.body.append(alertHost);
    }

    const toast = el("div", "alert alert-danger shadow-lg border-2 border-danger d-flex justify-content-between align-items-center p-3");
    toast.style.cssText = "border-radius: 12px; background: #FEF2F2; box-shadow: 0 10px 30px rgba(220,38,38,0.3);";

    const content = el("div", "d-flex align-items-center gap-2");
    content.innerHTML = `<span style="font-size:24px;">🚨</span>
      <div>
        <div class="fw-bold text-danger" style="font-size:14px;">CẢNH BÁO SỰ CỐ KHẨN CẤP (CRITICAL)!</div>
        <div class="small text-dark">${item.title || "Tài xế báo sự cố khẩn cấp"} · ${item.lastSenderName || "Shipper"}</div>
      </div>`;

    const btnActions = el("div", "d-flex gap-2 align-items-center");
    const viewBtn = button("Xử lý ngay", () => {
      toast.remove();
      if (active) selectIncident(active, item.incidentId);
      else window.Router.navigate(window.Router.href("incident-chat", {}, { incidentId: item.incidentId }));
    }, "btn btn-danger btn-sm");
    const closeBtn = button("✕", () => toast.remove(), "btn btn-outline-secondary btn-sm");

    btnActions.append(viewBtn, closeBtn);
    toast.append(content, btnActions);
    alertHost.replaceChildren(toast);
    playEmergencyBeep();
  }

  window.EmergencyIncidentAlert = { playEmergencyBeep, showCriticalEmergencyAlert };

  async function mount(host, route) {
    if (active) active.destroy();

    const state = {
      host,
      route,
      conversations: [],
      selectedIncidentId: null,
      chatThread: null,
      timer: null,
      isSending: false,
      searchKeyword: "",
      destroyed: false,
      destroy() {
        this.destroyed = true;
        if (this.timer) clearInterval(this.timer);
      }
    };
    active = state;

    host.replaceChildren();

    // Container
    const container = el("div", "incident-chat-container d-flex flex-column flex-md-row gap-3 h-100 p-3");
    container.style.minHeight = "720px";

    // Left sidebar: Danh sách cuộc trò chuyện sự cố
    const leftPane = el("div", "card shadow-sm col-12 col-md-4 d-flex flex-column");
    leftPane.style.maxHeight = "800px";

    const leftHeader = el("div", "card-header bg-light d-flex justify-content-between align-items-center py-3");
    leftHeader.append(
      el("h6", "mb-0 fw-bold", [el("i", "bi bi-exclamation-triangle-fill text-danger me-2"), "Sự cố & Hỗ trợ"]),
      button("Làm mới", () => loadConversations(state), "btn btn-sm btn-outline-secondary")
    );

    const searchBox = el("div", "p-2 border-bottom");
    const searchInput = el("input", "form-control form-control-sm");
    searchInput.placeholder = "Tìm mã sự cố, đơn hàng, shipper…";
    searchInput.addEventListener("input", (e) => {
      state.searchKeyword = e.target.value.toLowerCase().trim();
      renderConversationsList(state, convListHost);
    });
    searchBox.append(searchInput);

    const convListHost = el("div", "list-group list-group-flush overflow-auto flex-grow-1");
    leftPane.append(leftHeader, searchBox, convListHost);

    // Right panel: Khung chat và xử lý
    const rightPane = el("div", "card shadow-sm col-12 col-md-8 d-flex flex-column");
    rightPane.style.maxHeight = "800px";

    const rightHeader = el("div", "card-header bg-white d-flex justify-content-between align-items-center py-2");
    const rightTitle = el("div", "chat-header-info", el("span", "text-muted", "Chọn sự cố bên trái để xem trao đổi"));
    const rightActions = el("div", "chat-header-actions");
    rightHeader.append(rightTitle, rightActions);

    const messagesHost = el("div", "chat-messages-body p-3 overflow-auto flex-grow-1 bg-light");
    messagesHost.style.minHeight = "450px";

    const chatFooter = el("div", "card-footer bg-white p-2 d-none");
    const quickBar = el("div", "quick-replies mb-2 d-flex flex-wrap gap-1");
    const inputRow = el("div", "d-flex gap-2");
    const textarea = el("textarea", "form-control form-control-sm");
    textarea.rows = 2;
    textarea.placeholder = "Nhập hướng dẫn xử lý gửi đến tài xế… (Enter để gửi)";

    const sendBtn = button("Gửi", () => sendMessage(state, textarea), "btn btn-primary px-4");
    textarea.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        sendMessage(state, textarea);
      }
    });

    inputRow.append(textarea, sendBtn);
    chatFooter.append(quickBar, inputRow);

    rightPane.append(rightHeader, messagesHost, chatFooter);
    container.append(leftPane, rightPane);
    host.append(container);

    state.elements = {
      convListHost,
      rightTitle,
      rightActions,
      messagesHost,
      chatFooter,
      textarea,
      quickBar
    };

    // Load dữ liệu
    await loadConversations(state);

    // Bật timer polling
    state.timer = setInterval(() => {
      if (state.destroyed) return;
      pollActiveChat(state);
    }, pollInterval);
  }

  async function loadConversations(state) {
    try {
      const res = await window.ApiClient.request("/api/v1/incidents/conversations");
      if (state.destroyed) return;
      state.conversations = Array.isArray(res) ? res : [];
      state.alertedIncidents = state.alertedIncidents || new Set();
      for (const item of state.conversations) {
        if (item.severity === "CRITICAL" && item.status !== "RESOLVED" && !state.alertedIncidents.has(item.incidentId)) {
          state.alertedIncidents.add(item.incidentId);
          showCriticalEmergencyAlert(item);
        }
      }
      renderConversationsList(state, state.elements.convListHost);

      // Nếu đang chọn một sự cố thì reload chat, hoặc tự chọn item đầu tiên nếu chưa chọn
      if (!state.selectedIncidentId && state.conversations.length > 0) {
        selectIncident(state, state.conversations[0].incidentId);
      } else if (state.selectedIncidentId) {
        loadChatThread(state, state.selectedIncidentId);
      }
    } catch (e) {
      if (state.destroyed) return;
      state.elements.convListHost.replaceChildren(
        el("div", "p-3 text-center text-danger", "Không tải được danh sách: " + e.message)
      );
    }
  }

  function renderConversationsList(state, host) {
    host.replaceChildren();

    const filtered = state.conversations.filter(c => {
      if (!state.searchKeyword) return true;
      const kw = state.searchKeyword;
      return (c.title || "").toLowerCase().includes(kw) ||
             (c.orderCode || "").toLowerCase().includes(kw) ||
             (c.tripCode || "").toLowerCase().includes(kw) ||
             (c.lastSenderName || "").toLowerCase().includes(kw) ||
             (c.lastMessage || "").toLowerCase().includes(kw);
    });

    if (filtered.length === 0) {
      host.append(el("div", "p-4 text-center text-muted", "Không có sự cố nào phù hợp."));
      return;
    }

    for (const item of filtered) {
      const isSelected = item.incidentId === state.selectedIncidentId;
      const btn = el("button", "list-group-item list-group-item-action text-start p-3 border-bottom " + (isSelected ? "active" : ""));
      btn.type = "button";
      btn.addEventListener("click", () => selectIncident(state, item.incidentId));

      const topRow = el("div", "d-flex justify-content-between align-items-center mb-1");
      const titleSpan = el("span", "fw-bold small text-truncate me-1", item.title || ("Sự cố #" + item.incidentId));
      const badgeBox = el("div", "d-flex gap-1 align-items-center");
      badgeBox.append(renderStatusBadge(item.status), renderSeverityBadge(item.severity));
      topRow.append(titleSpan, badgeBox);

      const msgPreview = el("div", "small text-truncate " + (isSelected ? "text-light" : "text-muted"), [
        item.lastSenderName ? el("strong", "", item.lastSenderName + ": ") : "",
        item.lastMessage || "(Chưa có tin nhắn)"
      ]);

      const btmRow = el("div", "d-flex justify-content-between align-items-center mt-2 small " + (isSelected ? "text-light" : "text-secondary"));
      btmRow.append(
        el("span", "", formatTime(item.lastMessageAt)),
        item.unreadCount > 0 ? el("span", "badge bg-danger rounded-pill", String(item.unreadCount)) : ""
      );

      btn.append(topRow, msgPreview, btmRow);
      host.append(btn);
    }
  }

  async function selectIncident(state, incidentId) {
    state.selectedIncidentId = incidentId;
    renderConversationsList(state, state.elements.convListHost);
    await loadChatThread(state, incidentId);
  }

  async function loadChatThread(state, incidentId) {
    const { rightTitle, rightActions, messagesHost, chatFooter, quickBar } = state.elements;
    messagesHost.replaceChildren(el("div", "p-4 text-center text-muted", "Đang tải tin nhắn sự cố…"));

    try {
      const thread = await window.ApiClient.request("/api/v1/incidents/chat?incidentId=" + incidentId);
      if (state.destroyed || state.selectedIncidentId !== incidentId) return;
      state.chatThread = thread;

      // Cập nhật header
      rightTitle.replaceChildren();
      const h5 = el("h6", "mb-0 fw-bold", [
        thread.title || ("Sự cố #" + incidentId),
        el("span", "ms-2", renderStatusBadge(thread.status)),
        el("span", "ms-1", renderSeverityBadge(thread.severity))
      ]);
      const sub = el("small", "text-muted", [
        thread.orderCode ? "Đơn: " + thread.orderCode + " · " : "",
        thread.tripCode ? "Chuyến: " + thread.tripCode + " · " : "",
        "Phân loại: " + (thread.category || "Sự cố")
      ]);
      rightTitle.append(h5, sub);

      // Actions header
      rightActions.replaceChildren();
      if (thread.status !== "RESOLVED") {
        const resolveBtn = button("Đã giải quyết", () => promptResolve(state, incidentId), "btn btn-sm btn-outline-success");
        rightActions.append(resolveBtn);
      }

      // Quick bar suggestions
      quickBar.replaceChildren();
      const templates = [
        "🚑 Đã điều xe cứu hộ đến hỗ trợ bạn",
        "📦 Đã thu hồi đơn và điều phối lại cho tài xế khác",
        "📞 Đang liên hệ khách hàng để xác nhận lại thời gian",
        "✅ Đã ghi nhận, bạn giữ nguyên vị trí an toàn",
        "🔧 Khắc phục xong báo lại để tiếp tục chuyến"
      ];
      for (const t of templates) {
        const chip = button(t, () => {
          state.elements.textarea.value = t;
          state.elements.textarea.focus();
        }, "btn btn-xs btn-outline-secondary small py-0 px-2");
        chip.style.fontSize = "11px";
        quickBar.append(chip);
      }

      chatFooter.classList.remove("d-none");
      renderMessages(messagesHost, thread.messages || []);
    } catch (e) {
      if (state.destroyed) return;
      messagesHost.replaceChildren(el("div", "p-4 text-center text-danger", "Không tải được tin nhắn: " + e.message));
    }
  }

  async function pollActiveChat(state) {
    if (!state.selectedIncidentId || state.isSending) return;
    try {
      const thread = state.chatThread;
      const lastId = thread && thread.messages && thread.messages.length > 0
        ? thread.messages.at(-1).id
        : null;

      const url = "/api/v1/incidents/chat?incidentId=" + state.selectedIncidentId + (lastId ? "&afterId=" + lastId : "");
      const updated = await window.ApiClient.request(url);
      if (state.destroyed || !updated.messages || updated.messages.length === 0) return;

      const currentMsgs = state.chatThread?.messages || [];
      const existingIds = new Set(currentMsgs.map(m => m.id));
      const brandNew = updated.messages.filter(m => !existingIds.contains(m.id));

      if (brandNew.length > 0) {
        state.chatThread.messages = [...currentMsgs, ...brandNew];
        renderMessages(state.elements.messagesHost, state.chatThread.messages);
      }
    } catch (_) {
      // Bỏ qua lỗi polling nền
    }
  }

  function renderMessages(host, messages) {
    host.replaceChildren();

    if (messages.length === 0) {
      host.append(el("div", "p-5 text-center text-muted", "Chưa có trao đổi nào. Hãy nhập tin nhắn hướng dẫn tài xế bên dưới."));
      return;
    }

    for (const msg of messages) {
      if (msg.senderRole === "SYSTEM") {
        const sys = el("div", "text-center my-2",
          el("span", "badge bg-light text-secondary border px-3 py-2 text-wrap", [
            el("i", "bi bi-info-circle me-1"),
            msg.content
          ])
        );
        host.append(sys);
        continue;
      }

      const isMe = msg.isMe; // Admin/Dispatcher gửi
      const wrapper = el("div", "d-flex mb-3 " + (isMe ? "justify-content-end" : "justify-content-start"));

      const bubble = el("div", "p-3 rounded-3 shadow-sm", { style: "max-width: 75%;" });
      if (isMe) {
        bubble.className += " bg-primary text-white";
      } else {
        bubble.className += " bg-white border";
      }

      const senderHeader = el("div", "d-flex align-items-center justify-content-between mb-1 gap-2 small");
      senderHeader.append(
        el("strong", isMe ? "text-white-50" : "text-primary", msg.senderName + " (" + msg.senderRole + ")"),
        el("span", isMe ? "text-white-50" : "text-muted", formatTime(msg.sentAt))
      );

      const bodyText = el("div", "text-break", msg.content);
      bubble.append(senderHeader, bodyText);

      wrapper.append(bubble);
      host.append(wrapper);
    }

    host.scrollTop = host.scrollHeight;
  }

  async function sendMessage(state, textarea) {
    const text = textarea.value.trim();
    if (!text || state.isSending || !state.selectedIncidentId) return;

    state.isSending = true;
    textarea.disabled = true;

    try {
      const newMsg = await window.ApiClient.request("/api/v1/incidents/chat", {
        method: "POST",
        body: {
          incidentId: state.selectedIncidentId,
          content: text
        }
      });

      textarea.value = "";
      if (state.chatThread) {
        state.chatThread.messages = [...(state.chatThread.messages || []), newMsg];
        renderMessages(state.elements.messagesHost, state.chatThread.messages);
      }
      loadConversations(state);
    } catch (e) {
      alert("Không gửi được tin nhắn: " + e.message);
    } finally {
      state.isSending = false;
      textarea.disabled = false;
      textarea.focus();
    }
  }

  async function promptResolve(state, incidentId) {
    const note = prompt("Nhập ghi chú kết quả xử lý sự cố (hoặc để trống):", "Đã hướng dẫn và hỗ trợ tài xế khắc phục xong");
    if (note === null) return;

    try {
      await window.ApiClient.request("/api/v1/incidents/resolve", {
        method: "POST",
        body: {
          incidentId,
          resolutionNote: note
        }
      });
      alert("Đã đánh dấu sự cố giải quyết thành công!");
      await loadConversations(state);
      await loadChatThread(state, incidentId);
    } catch (e) {
      alert("Lỗi cập nhật sự cố: " + e.message);
    }
  }

  window.IncidentChatPage = { mount, destroy: () => active?.destroy() };
})();

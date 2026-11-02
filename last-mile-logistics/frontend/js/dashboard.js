"use strict";
(function(){
  const U=window.AdminUI,R=window.Router,{el,button}=U;
  const metrics=[
    ["waitingInbound","Chờ nhập kho","bi-box-arrow-in-down","Đơn CONFIRMED hoặc WAITING_INBOUND, chưa có kho hiện tại và chưa có bản ghi tồn kho. Không giới hạn ngày tạo."],
    ["waitingAssignment","Chờ phân công","bi-person-plus","Tất cả đơn hiện ở WAITING_ASSIGNMENT, không giới hạn ngày tạo. Điều kiện phân công được kiểm tra lại khi xử lý."],
    ["inDelivery","Đang giao","bi-truck","Đơn hiện ở IN_DELIVERY, không giới hạn ngày tạo; chưa bao gồm các trạng thái lấy hàng hoặc chờ bàn giao."],
    ["failedNeedsAction","Giao thất bại cần xử lý","bi-exclamation-triangle","Đơn FAILED có lần giao mới nhất thất bại; chưa có yêu cầu giao lại/hoàn đang chờ, đang thực hiện hoặc đã hoàn tất cho lần thất bại đó."]
  ];
  let active=null;
  const count=n=>new Intl.NumberFormat("vi-VN").format(n);
  const timestamp=value=>window.TrackingPage.date(value);
  const validCount=n=>Number.isSafeInteger(n)&&n>=0;
  const icon=name=>{const n=el("i","bi "+name);n.setAttribute("aria-hidden","true");return n;};
  function info(text){const n=el("span","dashboard-info","ⓘ");n.tabIndex=0;n.title=text;n.setAttribute("aria-label",text);return n;}
  function link(label,href,cls="btn btn-outline-orange btn-sm"){const n=el("a",cls,label);n.href=href;return n;}
  function destroy(){active?.charts?.forEach(c=>{try{c.destroy();}catch{}});active?.destroy();active=null;}
  function busy(box,text){box.setAttribute("aria-busy","true");box.replaceChildren(el("p","dashboard-message",text));}
  function failed(s,box,error,retry){box.setAttribute("aria-busy","false");U.failure(s,box,error,retry);}
  function today(utc){return new Date(Date.parse(utc)+7*3600000).toISOString().slice(0,10);}
  function codeDialog(s,code){
    const d=U.dialog(s,"Mã đầy đủ");if(!d)return;const input=el("input","form-control"),feedback=el("div");input.value=code;input.readOnly=true;input.setAttribute("aria-label","Mã đầy đủ");
    const copy=button("Sao chép",async()=>{try{await navigator.clipboard.writeText(code);U.notice(feedback,"Đã sao chép mã.","success");}catch{input.focus();input.select();U.notice(feedback,"Mã đã được chọn. Nhấn Ctrl+C hoặc dùng lệnh Sao chép của trình duyệt.","warning");}},"btn btn-orange");d.body.replaceChildren(input,copy,feedback);
  }
  function renderMetrics(s,data){
    const grid=el("div","dashboard-metrics");
    const descriptions={waitingInbound:"Đơn đã xác nhận, đang chờ tiếp nhận vào kho. Bao gồm đơn còn chờ từ các ngày trước.",waitingAssignment:"Đơn đang chờ điều phối chọn shipper và phương tiện phù hợp.",inDelivery:"Đơn đang được shipper giao đến người nhận.",failedNeedsAction:"Đơn giao thất bại chưa có phương án giao lại hoặc hoàn hàng."};
    for(const [key,label,symbol,definition]of metrics){
      if(!s.meta.permissions[key])continue;
      const value=data.metrics?.[key];if(!validCount(value))throw Error("API thiếu chỉ số hợp lệ: "+label);
      const card=el("article","dashboard-stat"),heading=el("div","dashboard-stat-heading");card.dataset.metric=key;
      heading.append(icon(symbol),el("h2","",label),info(definition));
      const amount=el("strong","dashboard-value",count(value));
      const open=link("Xem danh sách",R.href("orders",{},{branchId:s.meta.branchId,operationalGroup:key}),"dashboard-card-link");open.dataset.metric=key;open.setAttribute("aria-label","Xem danh sách "+label.toLowerCase());
      card.append(heading,amount,el("p","dashboard-stat-description",descriptions[key]),open);grid.append(card);
    }
    s.metrics.replaceChildren(grid.childElementCount?grid:el("p","dashboard-message","Bạn chưa được cấp quyền xem số liệu vận hành."));s.metrics.setAttribute("aria-busy","false");
  }
  function renderTasks(s){
    const box=s.tasks;box.replaceChildren();const sources=Object.entries(s.taskSources).filter(([,source])=>source.allowed),ready=sources.filter(([,source])=>source.state==="ready");
    const items=ready.flatMap(([,source])=>source.items).sort((a,b)=>a.priority-b.priority||(Date.parse(a.dueAt)||Infinity)-(Date.parse(b.dueAt)||Infinity)||a.id-b.id).slice(0,5);
    if(items.length){const list=el("ul","dashboard-task-list");for(const item of items){
      const row=el("li","dashboard-task"),identity=el("div","dashboard-task-identity"),detail=el("div","dashboard-task-detail");
      const labels={FAILED:"Giao thất bại",OVERDUE_DISPATCH:"Quá hạn",OVERDUE:"Quá hạn"};
      const code=button(item.code,()=>codeDialog(s,item.code),"dashboard-code");code.title="Xem và sao chép: "+item.code;code.setAttribute("aria-label","Xem mã đầy đủ "+item.code);
      const reason=el("span","dashboard-task-kind "+(item.kind==="FAILED"?"is-failure":"is-overdue"),labels[item.kind]);reason.title=item.dueAt?(item.kind==="FAILED"?"Lần giao: ":"Hạn giao: ")+timestamp(item.dueAt):labels[item.kind];identity.append(reason,code);const person=el("span","dashboard-person",item.receiverName||"Chưa có tên người nhận");person.title=person.textContent;detail.append(person);
      const href=R.href("order-detail",{id:item.id},{returnTo:R.href("overview",{},{branchId:s.meta.branchId})});
      row.append(identity,detail,link("Xử lý",href));list.append(row);
    }box.append(list);}
    if(sources.some(([,source])=>source.state==="loading"))box.append(el("p","dashboard-message","Đang tải công việc…"));
    for(const [key,source]of sources)if(source.state==="error"){const error=el("div","dashboard-section-error");failed(s,error,source.error,()=>loadPart(s,key,s.epoch));box.append(error);}
    const settled=sources.every(([,source])=>source.state==="ready");
    if(!items.length&&settled)box.append(el("p","dashboard-message",sources.length?"Không có công việc cần xử lý trong phạm vi này":"Bạn chưa được cấp quyền xem các công việc xử lý trong phạm vi này."));
    box.setAttribute("aria-busy",String(sources.some(([,source])=>source.state==="loading")));
  }
  function renderDelivery(s,data){
    if(![data.successfulCount,data.failedCount,data.attemptCount].every(validCount)||data.attemptCount!==data.successfulCount+data.failedCount
      ||(data.attemptCount===0?data.successRatePercent!==null:typeof data.successRatePercent!=="number"||!Number.isFinite(data.successRatePercent)))throw Error("API kết quả giao hàng trả dữ liệu không hợp lệ.");
    const content=el("div","dashboard-delivery-stats");
    for(const [label,value,cls]of [["Lượt thành công",count(data.successfulCount),"is-success"],["Lượt thất bại",count(data.failedCount),""],["Tỷ lệ thành công",data.successRatePercent==null?"—":new Intl.NumberFormat("vi-VN",{maximumFractionDigits:2}).format(data.successRatePercent)+"%",""]]){const n=el("div",cls);n.append(el("strong","",value),el("span","",label));content.append(n);}
    const definition="Đếm lượt giao theo ThoiGianThuGiao trong ngày Việt Nam (00:00 đến trước 00:00 hôm sau), kể cả đơn tạo trước hôm nay. Một đơn có thể có nhiều lượt. Tỷ lệ = lượt SUCCESS / tổng lượt SUCCESS và FAILED; không có lượt thì hiển thị —.";
    const note=el("p","dashboard-muted","Lượt giao hôm nay · Giờ Việt Nam ");note.append(info(definition));s.delivery.replaceChildren(content);
    if(data.attemptCount){const ratio=el("div","dashboard-ratio");ratio.setAttribute("role","img");ratio.setAttribute("aria-label",count(data.successfulCount)+" lượt thành công, "+count(data.failedCount)+" lượt thất bại");const success=el("span","dashboard-ratio-success");success.style.width=(data.successfulCount/data.attemptCount*100)+"%";ratio.append(success);s.delivery.append(ratio);}
    else s.delivery.append(el("p","dashboard-no-attempts","Hôm nay chưa có lượt giao"));
    s.delivery.append(note);s.delivery.setAttribute("aria-busy","false");
  }
  function updateTime(s){const pending=Object.values(s.partStatus).some(v=>v==="loading"),errors=Object.values(s.partStatus).some(v=>v==="error");s.updated.textContent=(s.lastUpdated?"Cập nhật: "+timestamp(s.lastUpdated):"Chưa cập nhật")+(pending?" · Đang tải…":errors?" · Một phần dữ liệu chưa tải được":"");}

  function renderVisualAnalytics(s, ordersRep, deliveryRep) {
    if (!s.alive() || !s.analyticsSection) return;
    s.charts?.forEach(c => { try { c.destroy(); } catch {} });
    s.charts = [];

    const wrapper = el("div", "dashboard-analytics-wrap");
    const titleRow = el("div", "d-flex justify-content-between align-items-center mb-3");
    titleRow.innerHTML = `<div class="d-flex align-items-center gap-2">
      <i class="bi bi-graph-up text-primary fs-5"></i>
      <h2 class="h5 fw-bold mb-0 text-dark">Phân tích & Biểu đồ trực quan (7 ngày gần nhất)</h2>
    </div>
    <span class="badge bg-light text-secondary border">Tự động đồng bộ</span>`;

    const row = el("div", "row g-3");

    // 1. Line Chart Card: Doanh thu & sản lượng 7 ngày
    const col1 = el("div", "col-12 col-lg-7");
    col1.innerHTML = `<div class="card shadow-sm h-100 border-0" style="border-radius:12px; background:white;">
      <div class="card-header bg-transparent border-0 pt-3 pb-0 d-flex justify-content-between align-items-center">
        <h6 class="fw-bold mb-0 text-dark">📈 Doanh thu & Sản lượng đơn hàng (7 ngày)</h6>
        <small class="text-muted">Đơn vị: Đơn / VNĐ</small>
      </div>
      <div class="card-body" style="height: 270px; position: relative;">
        <canvas id="dashboard-line-chart"></canvas>
      </div>
    </div>`;

    // 2. Doughnut Chart Card: Tỷ lệ Trạng thái Đơn hàng
    const col2 = el("div", "col-12 col-md-6 col-lg-5");
    col2.innerHTML = `<div class="card shadow-sm h-100 border-0" style="border-radius:12px; background:white;">
      <div class="card-header bg-transparent border-0 pt-3 pb-0 d-flex justify-content-between align-items-center">
        <h6 class="fw-bold mb-0 text-dark">🎯 Tỷ lệ Trạng thái Đơn hàng</h6>
        <small class="text-muted">Phân bổ</small>
      </div>
      <div class="card-body d-flex align-items-center justify-content-center" style="height: 270px; position: relative;">
        <canvas id="dashboard-pie-chart"></canvas>
      </div>
    </div>`;

    // 3. Bar Chart Card: Top 5 tài xế giao nhiều đơn nhất
    const col3 = el("div", "col-12");
    col3.innerHTML = `<div class="card shadow-sm border-0" style="border-radius:12px; background:white;">
      <div class="card-header bg-transparent border-0 pt-3 pb-0 d-flex justify-content-between align-items-center">
        <h6 class="fw-bold mb-0 text-dark">🏆 Bảng xếp hạng Top 5 Tài xế Giao nhiều đơn nhất (Leaderboard KPI)</h6>
        <small class="text-muted">Hiệu suất 7 ngày</small>
      </div>
      <div class="card-body" style="height: 230px; position: relative;">
        <canvas id="dashboard-bar-chart"></canvas>
      </div>
    </div>`;

    row.append(col1, col2, col3);
    wrapper.append(titleRow, row);
    s.analyticsSection.replaceChildren(wrapper);

    if (window.Chart) {
      try {
        // Prepare Line Chart data
        const daily = ordersRep?.dailyOrders || [];
        const lineLabels = daily.map(d => d.date.split("-").reverse().slice(0, 2).join("/"));
        const orderCounts = daily.map(d => d.createdOrderCount || 0);
        const revenues = daily.map(d => d.shippingFees || 0);

        const canvas1 = col1.querySelector("#dashboard-line-chart");
        if (canvas1) {
          const c1 = new window.Chart(canvas1.getContext("2d"), {
            type: "line",
            data: {
              labels: lineLabels.length ? lineLabels : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
              datasets: [
                {
                  label: "Sản lượng đơn (đơn)",
                  data: orderCounts.length ? orderCounts : [0, 0, 0, 0, 0, 0, 0],
                  borderColor: "#FA5A00",
                  backgroundColor: "rgba(250, 90, 0, 0.12)",
                  tension: 0.35,
                  fill: true,
                  yAxisID: "y"
                },
                {
                  label: "Doanh thu cước (VNĐ)",
                  data: revenues.length ? revenues : [0, 0, 0, 0, 0, 0, 0],
                  borderColor: "#2563EB",
                  backgroundColor: "transparent",
                  borderDash: [4, 4],
                  tension: 0.35,
                  yAxisID: "y1"
                }
              ]
            },
            options: {
              responsive: true,
              maintainAspectRatio: false,
              interaction: { mode: "index", intersect: false },
              scales: {
                y: { type: "linear", position: "left", beginAtZero: true, title: { display: true, text: "Đơn" } },
                y1: { type: "linear", position: "right", beginAtZero: true, grid: { drawOnChartArea: false }, title: { display: true, text: "VNĐ" } }
              }
            }
          });
          s.charts.push(c1);
        }

        // Prepare Pie/Doughnut Chart data
        const statusMap = new Map((ordersRep?.ordersByStatus || []).map(r => [r.status, r.orderCount || 0]));
        const successCount = (statusMap.get("DELIVERED") || 0) + (statusMap.get("COMPLETED") || 0);
        const failedCount = statusMap.get("FAILED") || 0;
        const returnCount = (statusMap.get("RETURNING") || 0) + (statusMap.get("RETURNED") || 0);
        const deliveringCount = (statusMap.get("IN_DELIVERY") || 0) + (statusMap.get("ASSIGNED") || 0);
        const pendingCount = (statusMap.get("WAITING_INBOUND") || 0) + (statusMap.get("WAITING_ASSIGNMENT") || 0) + (statusMap.get("CONFIRMED") || 0) + (statusMap.get("NEW") || 0);

        const pieLabels = ["Giao thành công", "Giao thất bại", "Hủy / Chuyển hoàn", "Đang đi giao", "Chờ xử lý / Kho"];
        const pieData = [successCount, failedCount, returnCount, deliveringCount, pendingCount];
        const hasPieData = pieData.some(v => v > 0);

        const canvas2 = col2.querySelector("#dashboard-pie-chart");
        if (canvas2) {
          const c2 = new window.Chart(canvas2.getContext("2d"), {
            type: "doughnut",
            data: {
              labels: hasPieData ? pieLabels : ["Chưa có dữ liệu"],
              datasets: [{
                data: hasPieData ? pieData : [1],
                backgroundColor: hasPieData ? ["#16A34A", "#DC2626", "#EA580C", "#2563EB", "#94A3B8"] : ["#E2E8F0"]
              }]
            },
            options: {
              responsive: true,
              maintainAspectRatio: false,
              plugins: {
                legend: { position: "bottom", labels: { boxWidth: 12, font: { size: 11 } } }
              }
            }
          });
          s.charts.push(c2);
        }

        // Prepare Leaderboard Bar Chart data
        const shippers = (deliveryRep?.items || [])
          .filter(sh => (sh.successfulCount || 0) > 0 || (sh.attemptCount || 0) > 0)
          .sort((a, b) => (b.successfulCount || 0) - (a.successfulCount || 0))
          .slice(0, 5);

        const topNames = shippers.length ? shippers.map(sh => sh.shipperName) : ["Chưa có lượt giao"];
        const topValues = shippers.length ? shippers.map(sh => sh.successfulCount || 0) : [0];

        const canvas3 = col3.querySelector("#dashboard-bar-chart");
        if (canvas3) {
          const c3 = new window.Chart(canvas3.getContext("2d"), {
            type: "bar",
            data: {
              labels: topNames,
              datasets: [{
                label: "Đơn giao thành công",
                data: topValues,
                backgroundColor: ["#FA5A00", "#FB923C", "#FDBA74", "#FED7AA", "#E2E8F0"],
                borderRadius: 6
              }]
            },
            options: {
              responsive: true,
              maintainAspectRatio: false,
              plugins: { legend: { display: false } },
              scales: {
                y: { beginAtZero: true, title: { display: true, text: "Số đơn thành công" }, ticks: { precision: 0 } }
              }
            }
          });
          s.charts.push(c3);
        }
      } catch (chartErr) {
        console.warn("Chart.js render error:", chartErr);
      }
    }
  }

  async function loadAnalytics(s, epoch) {
    if (!s.alive() || epoch !== s.epoch || !s.analyticsSection) return;
    s.analyticsSection.replaceChildren(el("p", "dashboard-message", "Đang tải biểu đồ phân tích 7 ngày…"));
    try {
      const endDay = today(s.meta.generatedAtUtc || new Date().toISOString());
      const startDay = new Date(Date.parse(endDay + "T00:00:00Z") - 6 * 86400000).toISOString().slice(0, 10);
      const queryParams = { from: startDay, to: endDay, branchId: s.meta.branchId || "" };
      const [ordersRep, deliveryRep] = await Promise.all([
        s.read("/api/v1/reports/dashboard?" + U.query({ ...queryParams, report: "orders" }), s.loadAbort.signal),
        s.read("/api/v1/reports/dashboard?" + U.query({ ...queryParams, report: "delivery", pageSize: 50 }), s.loadAbort.signal)
      ]);
      if (!s.alive() || epoch !== s.epoch) return;
      renderVisualAnalytics(s, ordersRep, deliveryRep);
    } catch (err) {
      if (!s.alive() || epoch !== s.epoch || err.name === "AbortError") return;
      s.analyticsSection.replaceChildren(
        el("div", "alert alert-light border small text-muted", "Biểu đồ phân tích chưa sẵn sàng hoặc cần thêm quyền báo cáo.")
      );
    }
  }

  async function loadPart(s,key,epoch){
    if(!s.alive()||epoch!==s.epoch)return;
    s.partStatus[key]="loading";if(key==="orders"){busy(s.metrics,"Đang tải chỉ số…");}if(key==="delivery")busy(s.delivery,"Đang tải kết quả hôm nay…");if(s.taskSources[key]){s.taskSources[key].state="loading";renderTasks(s);}updateTime(s);
    const query=U.query({branchId:s.meta.branchId});
    const path=key==="delivery"?"/api/v1/dashboard/delivery-today":"/api/v1/dashboard/operations";
    try{
      const data=await s.read(path+"?"+query,s.loadAbort.signal);if(!s.alive()||epoch!==s.epoch)return;
      if(key==="orders"){if(!Array.isArray(data.tasks))throw Error("API thiếu danh sách công việc.");renderMetrics(s,data);s.taskSources.orders.items=data.tasks;s.taskSources.orders.state="ready";}
      else if(key==="delivery")renderDelivery(s,data);
      s.partStatus[key]="ready";s.lastUpdated=data.generatedAtUtc||s.meta.generatedAtUtc;
    }catch(error){if(!s.alive()||epoch!==s.epoch||error.name==="AbortError"||error.sessionExpired)return;s.partStatus[key]="error";
      if(key==="orders")failed(s,s.metrics,error,()=>loadPart(s,key,s.epoch));if(key==="delivery")failed(s,s.delivery,error,()=>loadPart(s,key,s.epoch));if(s.taskSources[key])Object.assign(s.taskSources[key],{state:"error",error});
    }
    if(s.alive()&&epoch===s.epoch){renderTasks(s);updateTime(s);}
  }
  async function load(s){
    s.loadAbort?.abort();s.loadAbort=new AbortController();const epoch=++s.epoch;s.lastUpdated=null;s.partStatus={};s.scope.textContent="Đang xác định phạm vi…";s.updated.textContent="Đang cập nhật…";s.refresh.disabled=true;s.selector.disabled=true;
    busy(s.metrics,"Đang tải chỉ số…");busy(s.tasks,"Đang tải công việc…");busy(s.delivery,"Đang tải kết quả hôm nay…");U.notice(s.feedback,"");
    try{
      const meta=await s.read("/api/v1/dashboard/context?"+U.query({branchId:s.query.branchId}),s.loadAbort.signal);if(!s.alive()||epoch!==s.epoch)return;
      if(!Array.isArray(meta.branches)||!meta.permissions)throw Error("API phạm vi tổng quan không hợp lệ.");s.meta=meta;
      s.selector.replaceChildren(...U.select([...(meta.canChangeBranch?[["","Toàn hệ thống"]]:[]),...meta.branches.map(b=>[b.id,b.name])],meta.branchId??"").children);s.selector.value=meta.branchId??"";s.selector.disabled=!meta.canChangeBranch;
      s.scope.textContent=meta.branchId?meta.branches.find(b=>b.id===meta.branchId)?.name||"Bưu cục #"+meta.branchId:"Toàn hệ thống";
      s.taskSources={orders:{allowed:metrics.some(([key])=>meta.permissions[key]),state:"loading",items:[]}};
      s.deliverySection.hidden=!meta.permissions.delivery;
      s.report.hidden=!(meta.permissions.reports&&s.can("BAOCAO_XEM"));s.report.href=R.href("reports",{},{branchId:meta.branchId,from:today(meta.generatedAtUtc),to:today(meta.generatedAtUtc),tab:"delivery"});
      const jobs=[];if(s.taskSources.orders.allowed)jobs.push(loadPart(s,"orders",epoch));else renderMetrics(s,{metrics:{}});
      if(meta.permissions.delivery)jobs.push(loadPart(s,"delivery",epoch));jobs.push(loadAnalytics(s,epoch));renderTasks(s);await Promise.allSettled(jobs);
    }catch(error){if(!s.alive()||epoch!==s.epoch||error.name==="AbortError"||error.sessionExpired)return;failed(s,s.feedback,error,()=>load(s));for(const box of [s.metrics,s.tasks,s.delivery]){box.setAttribute("aria-busy","false");box.replaceChildren(el("p","dashboard-message","Chưa xác định được phạm vi. Hãy thử lại ở phía trên."));}s.updated.textContent="Chưa cập nhật";}
    finally{if(s.alive()&&epoch===s.epoch){s.refresh.disabled=false;s.selector.disabled=!s.meta?.canChangeBranch;}}
  }
  async function mount(container,user,route,context){
    destroy();const s=active=U.state(container,user,route,context),base=s.destroy;s.root.className="dashboard-page";s.query={...route.query};s.route=route;s.epoch=0;
    s.selector=document.getElementById("header-branch-selector");const label=document.getElementById("header-branch"),chevron=label.nextElementSibling;
    s.selector.hidden=false;label.hidden=true;if(chevron!==s.selector)chevron.hidden=true;
    const change=()=>{s.query={branchId:s.selector.value};R.updateQuery(s.query,s.route);s.route=R.current();load(s);};s.selector.addEventListener("change",change);
    s.destroy=()=>{if(!s.alive())return;s.loadAbort?.abort();s.selector.removeEventListener("change",change);s.selector.hidden=true;label.hidden=false;if(chevron!==s.selector)chevron.hidden=false;base();};
    const header=el("div","dashboard-toolbar"),meta=el("div");s.scope=el("strong","dashboard-scope","Đang xác định phạm vi…");s.updated=el("span","dashboard-updated","Chưa cập nhật");meta.append(el("h1","","Tổng quan"),s.scope,s.updated);s.refresh=button("Làm mới",()=>load(s),"btn btn-orange");header.append(meta,s.refresh);
    s.feedback=el("div","dashboard-feedback");s.metrics=el("section","dashboard-metric-region");s.metrics.setAttribute("aria-label","Các chỉ số vận hành");
    const main=el("div","dashboard-main"),tasksSection=el("section","dashboard-panel");tasksSection.append(el("h2","","Cần xử lý"));s.tasks=el("div","dashboard-tasks");tasksSection.append(s.tasks);
    s.deliverySection=el("section","dashboard-panel dashboard-delivery");s.deliverySection.append(el("h2","","Kết quả giao hàng hôm nay"));s.delivery=el("div");s.deliverySection.append(s.delivery);main.append(tasksSection,s.deliverySection);
    s.report=link("Xem báo cáo",R.href("reports"),"dashboard-report-link");s.report.hidden=true;s.analyticsSection=el("section","dashboard-analytics mt-4 mb-3");s.root.append(header,s.feedback,s.metrics,main,s.analyticsSection,s.report);await load(s);
  }
  window.DashboardPage=Object.freeze({mount,destroy});
}());

"use strict";
(function () {
  const U=window.AdminUI, R=window.Router, {el,button}=U;
  const interval=30000, staleAfter=5*60*1000;
  let active=null;
  function utc(value){return value?new Date(String(value)+(/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)?"":"Z")):null;}
  function date(value){const d=utc(value);return !d||Number.isNaN(d.getTime())?"—":new Intl.DateTimeFormat("en-GB",{timeZone:"Asia/Ho_Chi_Minh",day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit",hourCycle:"h23"}).format(d);}
  function coordinates(point){return point&&typeof point.latitude==="number"&&typeof point.longitude==="number"&&Number.isFinite(point.latitude)&&Number.isFinite(point.longitude)&&Math.abs(point.latitude)<=90&&Math.abs(point.longitude)<=180;}
  function locationState(point,now=Date.now()){if(!coordinates(point))return "missing";const time=utc(point.locationUpdatedAt)?.getTime();return !Number.isFinite(time)?"undated":now-time>staleAfter?"stale":time>now+60000?"future":"recent";}
  function label(s,status){return s.options.statuses.find(n=>n.code===status)?.name||status||"Chưa rõ trạng thái";}
  function badge(s,status){const tone=["FAILED","RETRY_WAITING","RETURNING"].includes(status)?"attention":["DELIVERED","COMPLETED","RETURNED"].includes(status)?"success":"neutral";return el("span","tracking-badge tracking-"+tone,label(s,status));}
  function query(s){return {...s.filters,statusGroup:s.filters.statusGroup||"ALL",orderId:s.selected||"",view:s.view,auto:String(s.auto)};}
  function sync(s){R.updateQuery(query(s),s.route);s.route=R.current()||s.route;}
  function requestPath(s){return "/api/v1/orders?"+U.query(s.filters);}
  function releaseMap(s){s.mapResize?.disconnect();cancelAnimationFrame(s.resizeFrame);s.map?.remove();s.map=null;s.markers=null;s.mapFitted=false;s.tileFailed=false;}
  const compact=()=>window.matchMedia("(max-width:1099.98px)").matches;
  const pointIcons={pickup:"box-seam",delivery:"geo-alt-fill",shipper:"person-badge"};
  function icon(name){const n=el("i","bi bi-"+name);n.setAttribute("aria-hidden","true");return n;}
  function resizeMap(s){cancelAnimationFrame(s.resizeFrame);s.resizeFrame=requestAnimationFrame(()=>{if(!s.alive()||!s.map||!s.mapHost.getClientRects().length)return;const size=s.map.getSize();if(size.x!==s.mapHost.clientWidth||size.y!==s.mapHost.clientHeight)s.map.invalidateSize({animate:false,pan:true,debounceMoveend:true});});}
  function fitPoints(s){if(s.map&&s.points?.length)s.map.fitBounds(s.points.map(p=>[p.latitude,p.longitude]),{padding:[52,52],maxZoom:15,animate:false});}
  function releaseEvidence(s){s.evidenceAbort?.abort();for(const url of s.fileUrls||[])URL.revokeObjectURL(url);s.fileUrls=[];}
  function destroy(){active?.destroy();active=null;}
  function schedule(s){clearTimeout(s.timer);if(s.alive()&&s.refreshButton&&s.auto&&!document.hidden&&!s.busy)s.timer=setTimeout(()=>refresh(s),interval);}
  function toggleAuto(s){s.auto=s.autoControl.checked;sync(s);s.updateTime();schedule(s);}
  function resetSelection(s){s.detailAbort?.abort();releaseEvidence(s);releaseMap(s);s.selected=null;s.data=null;s.detail.replaceChildren(el("p","tracking-empty","Chọn một đơn để xem tiến độ giao hàng."));s.root.classList.remove("tracking-show-detail");}
  function shell(s){
    const form=el("form","tracking-filters"),fields={};s.fields=fields;
    const main=el("div","tracking-filter-main");
    U.field(main,fields,"keyword","Mã vận đơn / mã đơn",s.filters.keyword,{type:"search",maxLength:100});fields.keyword.control.placeholder="Nhập mã để tìm đơn";
    U.field(main,fields,"branchId","Bưu cục",s.filters.branchId,{items:[...(s.user.role==="ADMIN"?[["","Tất cả bưu cục"]]:[]),...s.options.branches.map(n=>[n.id,n.name])]});
    const shippers=()=>[["","Tất cả shipper"],...s.options.shippers.filter(n=>!fields.branchId.control.value||String(n.branchId)===fields.branchId.control.value).map(n=>[n.id,n.name])];
    U.field(main,fields,"shipperId","Shipper",s.filters.shipperId,{items:shippers()});
    fields.shipperId.control.title="Lọc theo phân công hiện tại còn hiệu lực, không phải shipper của các lần giao đã kết thúc.";
    fields.branchId.control.addEventListener("change",()=>{fields.shipperId.control.replaceChildren(...U.select(shippers(),"").children);fields.shipperId.control.value="";});
    const statuses=[["PROGRESS","Đang thực hiện"],["ATTENTION","Cần xử lý"],["DONE","Đã kết thúc"],["ALL","Mọi trạng thái"],...s.options.statuses.map(n=>[n.code,n.name])];
    U.field(main,fields,"statusChoice","Trạng thái",s.filters.status||s.filters.statusGroup||"ALL",{items:statuses});
    const find=button("Tìm kiếm",null,"btn btn-orange");find.type="submit";main.append(find);
    const more=el("details","tracking-more"),caption=el("summary","","Bộ lọc thêm"),dates=el("div","tracking-date-filters");
    U.field(dates,fields,"fromDate","Từ ngày cập nhật đơn",s.filters.fromDate,{type:"date",min:"1900-01-01",max:"9999-12-30"});
    U.field(dates,fields,"toDate","Đến ngày cập nhật đơn",s.filters.toDate,{type:"date",min:"1900-01-01",max:"9999-12-30"});
    dates.append(button("Xóa ngày lọc",()=>{fields.fromDate.control.value="";fields.toDate.control.value="";draft();},"btn btn-link"));
    more.append(caption,dates,el("small","text-secondary","Lọc theo lần cập nhật đơn gần nhất, gồm cả hai ngày · Giờ Việt Nam (UTC+7)."));more.open=!!(s.filters.fromDate||s.filters.toDate);
    const draft=()=>{s.draft.textContent="Bộ lọc đã đổi. Chọn Tìm kiếm để áp dụng.";caption.textContent="Bộ lọc thêm"+((fields.fromDate.control.value||fields.toDate.control.value)?" · Có ngày lọc":"");};
    form.addEventListener("input",draft);form.addEventListener("change",draft);
    form.addEventListener("submit",async event=>{event.preventDefault();if(fields.fromDate.control.value&&fields.toDate.control.value&&fields.fromDate.control.value>fields.toDate.control.value){U.notice(s.feedback,"Từ ngày không được sau đến ngày.");return;}
      // Abort the previous filter cohort before replacing it. Automatic ticks never overlap.
      s.listAbort?.abort();s.detailAbort?.abort();s.epoch++;s.busy=false;
      const choice=fields.statusChoice.control.value;
      s.filters={...s.filters,keyword:fields.keyword.control.value.trim(),branchId:fields.branchId.control.value,shipperId:fields.shipperId.control.value,status:["PROGRESS","ATTENTION","DONE","ALL"].includes(choice)?"":choice,statusGroup:["PROGRESS","ATTENTION","DONE"].includes(choice)?choice:"",fromDate:fields.fromDate.control.value,toDate:fields.toDate.control.value,page:1};
      s.draft.textContent="";U.notice(s.feedback,"");resetSelection(s);sync(s);await refresh(s);
    });
    s.draft=el("p","tracking-draft");s.feedback=el("div","tracking-feedback");s.feedback.setAttribute("aria-live","polite");
    form.append(main,more,s.draft);
    const toolbar=el("div","tracking-toolbar"),autoLabel=el("label","tracking-auto"),auto=el("input","form-check-input");s.autoControl=auto;auto.type="checkbox";auto.checked=s.auto;auto.addEventListener("change",()=>toggleAuto(s));autoLabel.append(auto,document.createTextNode("Tự cập nhật mỗi 30 giây"));
    const stamp=el("span","tracking-update-time");s.updateTime=()=>{stamp.textContent=(s.lastUpdate?"Đã tải lúc "+date(s.lastUpdate):"Chưa tải dữ liệu")+(document.hidden?" · Tạm dừng khi ẩn tab":s.auto?" · Tự cập nhật":" · Đã tắt tự cập nhật");};s.updateTime();
    s.refreshButton=button("Làm mới",()=>refresh(s),"btn btn-outline-orange");toolbar.append(autoLabel,stamp,s.refreshButton);
    s.layout=el("div","tracking-layout");const listPane=el("section","tracking-list-pane");listPane.setAttribute("aria-label","Danh sách đơn giao hàng");
    s.list=el("div","tracking-list");s.list.setAttribute("aria-label","Kết quả tìm kiếm");s.pager=el("div","tracking-pager");s.count=el("p","tracking-count");s.listScope=el("p","tracking-scope");listPane.append(s.count,s.listScope,s.list,s.pager);
    s.detail=el("section","tracking-detail");s.detail.setAttribute("aria-label","Tiến độ đơn được chọn");s.layout.append(listPane,s.detail);s.root.replaceChildren(form,toolbar,s.feedback,s.layout);resetSelection(s);
  }
  function renderList(s,data){
    const pageScroll=window.scrollY,scroll=s.list.scrollTop,focused=document.activeElement?.dataset?.orderId;
    s.count.textContent=data.totalItems+" đơn phù hợp";
    const f=s.filters,scope=s.options.branches.find(n=>String(n.id)===String(f.branchId))?.name||"Tất cả bưu cục",shipper=s.options.shippers.find(n=>String(n.id)===String(f.shipperId))?.name;
    s.listScope.textContent=scope+(shipper?" · "+shipper:"")+(f.keyword?" · “"+f.keyword+"”":"")+(f.status?" · "+label(s,f.status):f.statusGroup?" · "+({PROGRESS:"Đang thực hiện",ATTENTION:"Cần xử lý",DONE:"Đã kết thúc"}[f.statusGroup]):" · Mọi trạng thái")+(f.fromDate||f.toDate?" · Ngày cập nhật: "+(f.fromDate||"…")+" – "+(f.toDate||"…"):"");
    const nodes=data.items.map(row=>{const card=button("",()=>select(s,row.id,true),"tracking-order"+(s.selected===row.id?" is-selected":""));card.replaceChildren();card.dataset.orderId=row.id;card.setAttribute("aria-pressed",String(s.selected===row.id));
      const top=el("div","tracking-order-top");top.append(el("strong","",row.trackingNumber),badge(s,row.status));const address=el("span","tracking-address",row.deliveryAddress||"Chưa có địa chỉ giao");address.title=row.deliveryAddress||"";
      card.append(top,el("span","tracking-recipient",row.receiverName),address,el("span","tracking-shipper",row.shipperName||"Chưa có phân công hiện tại"));return card;});
    s.list.replaceChildren(...(nodes.length?nodes:[el("p","tracking-empty","Không tìm thấy đơn phù hợp. Hãy thử đổi mã hoặc bộ lọc.")]));s.list.scrollTop=scroll;
    if(focused)s.list.querySelector('[data-order-id="'+focused+'"]')?.focus({preventScroll:true});
    window.scrollTo({top:pageScroll,behavior:"instant"});s.pager.replaceChildren();if(!data.totalItems)return;
    const pages=Math.ceil(data.totalItems/data.pageSize),navigate=page=>{s.listAbort?.abort();s.detailAbort?.abort();s.epoch++;s.busy=false;s.filters.page=page;sync(s);refresh(s);};
    s.pager.append(el("span","","Trang "+data.page+" / "+pages));
    if(pages>1){const prev=button("Trước",()=>navigate(data.page-1)),next=button("Sau",()=>navigate(data.page+1));prev.disabled=data.page<=1;next.disabled=data.page>=pages;s.pager.append(prev,next);}
  }
  async function refresh(s){
    if(!s.alive()||s.busy)return;
    clearTimeout(s.timer);s.busy=true;s.refreshButton.disabled=true;const epoch=++s.epoch;
    s.listAbort=new AbortController();const signal=AbortSignal.any([s.abort.signal,s.listAbort.signal]);s.list.setAttribute("aria-busy","true");
    if(!s.loaded)s.list.replaceChildren(el("p","tracking-empty","Đang tải danh sách đơn…"));
    try{
      const data=window.ApiClient.validatePage(await s.read(requestPath(s),signal),requestPath(s),["id"]);
      if(!s.alive()||signal.aborted||epoch!==s.epoch)return;
      const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize));if(data.page>pages){s.filters.page=pages;s.busy=false;return refresh(s);}
      s.filters.page=data.page;s.filters.pageSize=data.pageSize;renderList(s,data);s.loaded=true;s.lastUpdate=new Date().toISOString();s.updateTime();U.notice(s.feedback,"");
      if(!s.selected&&data.items.length)await select(s,data.items[0].id,false);
      else if(s.selected)await readDetail(s,s.selected,true);
      if(s.alive()&&epoch===s.epoch)sync(s);
    }catch(error){if(s.alive()&&!signal.aborted&&epoch===s.epoch){U.failure(s,s.feedback,error);if(!s.loaded)s.list.replaceChildren(el("p","tracking-empty",error.status===403?"Không có quyền xem danh sách đơn.":"Chưa tải được danh sách. Chọn Làm mới để thử lại."));}}
    finally{if(s.alive()&&epoch===s.epoch){s.busy=false;s.refreshButton.disabled=false;s.list.setAttribute("aria-busy","false");schedule(s);}}
  }
  async function select(s,id,open){
    if(open){s.root.classList.add("tracking-show-detail");if(compact())s.detail.scrollIntoView({block:"start",behavior:"instant"});}
    if(s.selected===id&&s.data){updateMap(s);return;}
    s.selected=id;s.data=null;releaseMap(s);releaseEvidence(s);sync(s);
    for(const card of s.list.querySelectorAll(".tracking-order")){const chosen=Number(card.dataset.orderId)===id;card.classList.toggle("is-selected",chosen);card.setAttribute("aria-pressed",String(chosen));}
    buildDetail(s);await readDetail(s,id,false);
  }
  function buildDetail(s){
    const back=button("‹ Quay lại danh sách",()=>{s.root.classList.remove("tracking-show-detail");s.list.querySelector('[data-order-id="'+s.selected+'"]')?.focus({preventScroll:true});s.root.scrollIntoView({behavior:"instant"});},"btn btn-outline-secondary tracking-back");
    s.summary=el("div","tracking-order-summary");s.summary.append(el("p","tracking-empty","Đang tải tiến độ đơn…"));s.detailError=el("div","tracking-detail-error");s.detailError.setAttribute("aria-live","polite");
    const tabs=el("div","tracking-tabs");tabs.setAttribute("role","tablist");tabs.setAttribute("aria-label","Thông tin giao hàng");s.tabButtons={};
    for(const [key,title]of [["map","Bản đồ"],["history","Lịch sử"]]){const b=button(title,()=>{s.view=key;showTab(s);sync(s);},"tracking-tab");b.id="tracking-tab-"+key;b.setAttribute("role","tab");b.setAttribute("aria-controls","tracking-panel-"+key);b.addEventListener("keydown",event=>{if(!["ArrowLeft","ArrowRight","Home","End"].includes(event.key))return;event.preventDefault();s.view=event.key==="Home"?"map":event.key==="End"?"history":s.view==="map"?"history":"map";showTab(s);sync(s);s.tabButtons[s.view].focus();});s.tabButtons[key]=b;tabs.append(b);}
    s.mapPane=el("div","tracking-map-pane");s.mapPane.id="tracking-panel-map";s.mapPane.setAttribute("role","tabpanel");s.mapPane.setAttribute("aria-labelledby","tracking-tab-map");
    s.gps=el("div","tracking-gps");s.gps.setAttribute("role","status");s.mapStatus=el("p","tracking-map-status");s.mapStatus.setAttribute("role","status");s.mapHost=el("div","tracking-map");s.mapHost.setAttribute("aria-label","Bản đồ điểm lấy hàng, điểm giao và vị trí shipper gần nhất");
    const legend=el("div","tracking-map-legend");for(const [key,name]of [["pickup","Điểm lấy hàng"],["delivery","Điểm giao hàng"],["shipper","Shipper"]]){const item=el("span","tracking-legend-"+key);item.append(icon(pointIcons[key]),document.createTextNode(name));legend.append(item);}
    const tools=el("div","tracking-map-tools");s.fitButton=button("Xem tất cả điểm",()=>fitPoints(s),"btn btn-outline-secondary btn-sm");s.locateButton=button("Vị trí shipper",()=>{const a=s.data?.tracking.currentAssignment;if(s.map&&coordinates(a))s.map.setView([a.latitude,a.longitude],16,{animate:false});},"btn btn-outline-secondary btn-sm");
    s.mapReason=el("small","tracking-map-reason");s.mapReason.id="tracking-map-reason";for(const b of [s.fitButton,s.locateButton]){b.disabled=true;b.setAttribute("aria-describedby",s.mapReason.id);}tools.append(s.fitButton,s.locateButton,s.mapReason);
    s.mapPane.append(s.gps,legend,tools,s.mapStatus,s.mapHost);
    s.historyPane=el("div","tracking-history-pane");s.historyPane.id="tracking-panel-history";s.historyPane.setAttribute("role","tabpanel");s.historyPane.setAttribute("aria-labelledby","tracking-tab-history");s.historyPane.append(el("p","tracking-empty","Đang tải lịch sử…"));s.summarySignature=null;s.historySignature=null;
    s.gpsSignature=null;s.detail.replaceChildren(back,s.summary,s.detailError,tabs,s.mapPane,s.historyPane);showTab(s);
  }
  function showTab(s){for(const key of ["map","history"]){const selected=s.view===key;s.tabButtons[key].setAttribute("aria-selected",String(selected));s.tabButtons[key].tabIndex=selected?0:-1;}s.mapPane.hidden=s.view!=="map";s.historyPane.hidden=s.view!=="history";if(s.view==="map"&&s.data)updateMap(s);}
  async function readDetail(s,id,refreshing){
    s.detailAbort?.abort();const abort=s.detailAbort=new AbortController(),signal=AbortSignal.any([s.abort.signal,abort.signal]);
    try{const data=await s.read("/api/v1/orders/"+id+"?tracking=true",signal);if(!s.alive()||signal.aborted||s.selected!==id)return;
      if(!Array.isArray(data.statusHistory)||!Array.isArray(data.deliveryPoints)||!Array.isArray(data.tracking?.attempts))throw Error("API thiếu dữ liệu theo dõi đơn.");
      const scroll=window.scrollY;s.data=data;renderDetail(s);if(refreshing)window.scrollTo({top:scroll,behavior:"instant"});U.notice(s.detailError,"");
    }catch(error){if(!s.alive()||signal.aborted||s.selected!==id)return;U.failure(s,s.detailError,error);if(!refreshing||[403,404].includes(error.status)){releaseMap(s);releaseEvidence(s);s.data=null;s.mapHost.hidden=true;s.fitButton.disabled=true;s.locateButton.disabled=true;s.mapReason.textContent="Chưa tải được tọa độ đơn.";s.summary.replaceChildren(el("p","tracking-empty",error.status===404?"Không tìm thấy đơn trong phạm vi được phép xem.":error.status===403?"Không có quyền xem tiến độ đơn.":"Chưa tải được chi tiết đơn."));s.historyPane.replaceChildren();s.gps.textContent="Chưa tải được vị trí.";s.gpsSignature=null;}}
  }
  function renderDetail(s){
    const d=s.data,a=d.tracking.currentAssignment,delivery=d.deliveryPoints.find(p=>p.type==="DELIVERY"),signature=JSON.stringify([d.trackingNumber,d.receiverName,d.status,d.updatedAt,d.createdAt,d.expectedDeliveryAt,d.deliveryPoints,a?.shipperName,a?.licensePlate,a?.tripCode]);
    if(signature!==s.summarySignature){const head=el("div","tracking-detail-head"),codes=el("div","tracking-detail-codes");codes.append(el("h2","",d.trackingNumber),badge(s,d.status));
      const link=el("a","btn btn-outline-orange btn-sm","Chi tiết đơn");link.href=R.href("order-detail",{id:d.id},{returnTo:R.href("tracking",{},query(s))});head.append(codes,link);
      const groups=el("div","tracking-summary-groups"),group=(title,items)=>{const section=el("section","tracking-summary-group"),dl=el("dl","tracking-summary");section.append(el("h3","",title),dl);for(const [name,value]of items){const pair=el("div");pair.append(el("dt","",name),el("dd","",value||"Chưa có"));dl.append(pair);}return section;};
      groups.append(group("Người nhận",[["Họ tên",delivery?.contactName||d.receiverName],["Điện thoại",delivery?.phone],["Địa chỉ giao",delivery?.address]]),group("Người giao",[["Shipper",a?.shipperName||"Chưa có phân công hiện tại"],["Biển số xe",a?.licensePlate],...(a?.tripCode?[["Chuyến giao",a.tripCode]]:[])]));
      const times=group("Thời gian",[["Dự kiến giao",date(d.expectedDeliveryAt)],["Cập nhật gần nhất",date(d.updatedAt||d.createdAt)]]);times.classList.add("tracking-summary-times");
      s.summary.replaceChildren(head,groups,times);s.summarySignature=signature;}
    const historySignature=JSON.stringify([d.statusHistory,d.tracking.attempts]);
    if(historySignature!==s.historySignature){releaseEvidence(s);const timeline=el("ol","tracking-timeline");for(const h of [...d.statusHistory].sort((a,b)=>utc(b.changedAt)-utc(a.changedAt)||b.id-a.id)){const li=el("li");li.append(badge(s,h.newStatus),el("time","",date(h.changedAt)),el("p","",h.changedByName||"Không có tên người thực hiện"));if(h.reason)li.append(el("p","tracking-event-note",h.reason));timeline.append(li);}
      const attempts=el("div","tracking-attempts");attempts.append(el("h3","","Các lần giao"));for(const attempt of d.tracking.attempts){const n=el("article","tracking-attempt"),title=el("strong","","Lần giao "+attempt.attemptNumber+" · "+(attempt.result==="SUCCESS"?"Thành công":"Thất bại"));n.append(title,el("time","",date(attempt.attemptedAt)),el("p","",attempt.recordedByName||attempt.shipperName));for(const note of [attempt.failureReason,attempt.notes,attempt.retryExpectedAt?"Dự kiến giao lại: "+date(attempt.retryExpectedAt):null])if(note)n.append(el("p","tracking-event-note",note));attempts.append(n);}
      if(!d.tracking.attempts.length)attempts.append(el("p","text-secondary","Chưa có lần giao được ghi nhận."));
      s.evidence=el("section","tracking-evidence");s.evidence.append(el("h3","","Bằng chứng giao hàng"),button("Xem bằng chứng",()=>loadEvidence(s,1),"btn btn-outline-secondary btn-sm"));
      s.historyPane.replaceChildren(el("h3","","Lịch sử trạng thái"),timeline.children.length?timeline:el("p","text-secondary","Chưa có lịch sử trạng thái."),attempts,s.evidence);s.historySignature=historySignature;}
    updateMap(s);
  }
  function updateMap(s){
    const d=s.data,a=d.tracking.currentAssignment,state=locationState(a);
    const warning=["stale","undated","future"].includes(state),gpsSignature=JSON.stringify([state,a?.locationUpdatedAt]);
    if(s.gpsSignature!==gpsSignature){const text=el("div"),title=el("strong","",{missing:"Chưa có vị trí shipper",stale:"Vị trí shipper đã cũ",undated:"Vị trí shipper chưa có thời gian",future:"Thời gian GPS cần kiểm tra",recent:"Vị trí shipper gần nhất"}[state]);text.append(title);if(state!=="missing")text.append(el("small","","Cập nhật gần nhất: "+date(a.locationUpdatedAt)));s.gps.replaceChildren(icon(state==="missing"?"geo-alt":warning?"clock-history":"geo-alt-fill"),text);s.gps.classList.toggle("tracking-gps-warning",warning);s.gpsSignature=gpsSignature;}
    // Native tooltip also works without Bootstrap's JS tooltip initializer.
    s.gps.title="Vị trí được xem là cũ khi lần cập nhật GPS cách hiện tại hơn 5 phút. Đây là vị trí ghi nhận gần nhất, không phải trạng thái trực tuyến.";
    const points=d.deliveryPoints.filter(p=>["PICKUP","DELIVERY"].includes(p.type)&&coordinates(p)).map((p,index)=>({...p,key:"point-"+(p.id??index),kind:p.type==="PICKUP"?"pickup":"delivery",title:p.type==="PICKUP"?"Điểm lấy hàng":"Điểm giao hàng",name:p.contactName}));
    if(coordinates(a))points.push({...a,key:"shipper",kind:"shipper",title:"Shipper · "+(warning?"Vị trí cần kiểm tra":"Vị trí gần nhất"),name:a.shipperName,state});s.points=points;
    const unavailable=!window.L||!points.length;s.fitButton.disabled=unavailable;s.locateButton.disabled=unavailable||!coordinates(a);
    s.fitButton.title=unavailable?(!window.L?"Chưa tải được thư viện bản đồ":"Chưa có tọa độ hợp lệ"):"Căn bản đồ vừa tất cả điểm";s.locateButton.title=s.locateButton.disabled?(!window.L?"Chưa tải được thư viện bản đồ":"Chưa có tọa độ shipper hợp lệ"):"Xem vị trí shipper ghi nhận gần nhất";
    s.mapReason.textContent=unavailable?s.fitButton.title:!coordinates(a)?"Chưa có tọa độ shipper hợp lệ.":"";
    if(s.view!=="map"||!s.mapPane.getClientRects().length)return;
    if(!points.length){releaseMap(s);s.mapHost.hidden=true;s.mapStatus.textContent="Chưa có tọa độ hợp lệ để hiển thị bản đồ.";return;}
    s.mapHost.hidden=false;
    if(!window.L){s.mapStatus.textContent="Chưa tải được thư viện bản đồ. Thông tin đơn và lịch sử vẫn sử dụng được.";return;}
    if(!s.map){s.map=window.L.map(s.mapHost,{scrollWheelZoom:false});s.markers=new Map();const tiles=window.L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:19,attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'});tiles.on("tileerror",()=>{if(s.alive()){s.tileFailed=true;s.mapStatus.textContent="Chưa tải được nền bản đồ. Các điểm tọa độ vẫn được giữ.";}});tiles.on("tileload",()=>{if(s.alive()){s.tileFailed=false;s.mapStatus.textContent="";}});tiles.addTo(s.map);s.mapResize=new ResizeObserver(()=>resizeMap(s));s.mapResize.observe(s.mapHost);}
    if(!s.mapFitted){s.map.invalidateSize({pan:false});fitPoints(s);s.mapFitted=true;}
    const keys=new Set(points.map(p=>p.key));for(const [key,entry]of s.markers)if(!keys.has(key)){entry.marker.remove();s.markers.delete(key);}
    for(const p of points){
      const same=points.filter(n=>n.latitude===p.latitude&&n.longitude===p.longitude),offset=(same.indexOf(p)-(same.length-1)/2)*42,signature=JSON.stringify([p,offset,same.length]);let entry=s.markers.get(p.key);
      if(entry?.signature===signature)continue;
      const glyph=el("span","tracking-marker-symbol tracking-marker-"+p.kind+(p.kind==="shipper"&&warning?" tracking-marker-old":""));glyph.append(icon(pointIcons[p.kind]));if(p.kind==="shipper"&&warning)glyph.append(icon("clock-history"));
      const markerIcon=window.L.divIcon({className:"tracking-map-marker",html:glyph,iconSize:[36,40],iconAnchor:[18-offset,40],popupAnchor:[offset,-40]});
      if(!entry){entry={marker:window.L.marker([p.latitude,p.longitude],{keyboard:true,autoPanOnFocus:false}).addTo(s.map)};entry.marker.on("popupopen",({popup})=>{popup.options.autoPan=true;popup.update();popup.options.autoPan=false;});s.markers.set(p.key,entry);}else entry.marker.setLatLng([p.latitude,p.longitude]);
      entry.marker.setIcon(markerIcon);const popup=el("div","tracking-point-popup");popup.append(el("strong","",p.title),el("p","",p.name||"Chưa có tên liên hệ"));if(p.address)popup.append(el("p","",p.address));if(p.kind==="shipper")popup.append(el("p","","Cập nhật gần nhất: "+date(p.locationUpdatedAt)));
      if(same.length>1)popup.append(el("small","","Cùng tọa độ: "+same.map(n=>n.title).join(" · ")+". Các biểu tượng được dàn cạnh nhau để chọn từng điểm."));
      entry.marker.bindPopup(popup,{autoPan:false,maxWidth:280,maxHeight:180});const element=entry.marker.getElement();element.setAttribute("aria-label",p.title+" · "+(p.name||"Chưa có tên liên hệ")+(same.length>1?" · Cùng tọa độ với "+(same.length-1)+" điểm khác":""));element.title=element.getAttribute("aria-label");element.onkeydown=event=>{if(event.key===" "){event.preventDefault();entry.marker.openPopup();}};entry.signature=signature;
    }
    resizeMap(s);s.mapStatus.textContent=s.tileFailed?"Chưa tải được nền bản đồ. Các điểm tọa độ vẫn được giữ.":"";
  }
  async function loadEvidence(s,page){
    releaseEvidence(s);const id=s.selected,abort=s.evidenceAbort=new AbortController(),signal=AbortSignal.any([s.abort.signal,abort.signal]),host=s.evidence;host.replaceChildren(el("h3","","Bằng chứng giao hàng"),el("p","text-secondary","Đang tải bằng chứng…"));
    try{const data=window.ApiClient.validatePage(await s.read("/api/v1/orders/"+id+"/evidence?"+U.query({page,pageSize:10}),signal),"evidence",["id"]);if(!s.alive()||signal.aborted||s.selected!==id)return;host.replaceChildren(el("h3","","Bằng chứng giao hàng"));if(!data.items.length)host.append(el("p","text-secondary","Chưa có bằng chứng được ghi nhận."));
      for(const item of data.items){const row=el("article","tracking-evidence-row");row.append(el("p","","Lần "+item.attemptNumber+" · "+({PHOTO:"Ảnh giao hàng",SIGNATURE:"Chữ ký",OTP:"Xác nhận OTP",RECEIVER_CONFIRMATION:"Người nhận xác nhận"}[item.type]||item.type)+" · "+date(item.recordedAt)));if(item.hasFile){const open=button("Xem ảnh",async()=>{open.disabled=true;try{const blob=await window.ApiClient.request("/api/v1/orders/"+id+"/evidence/"+item.id+"/file",{signal,responseType:"blob"});if(!s.alive()||signal.aborted||s.selected!==id)return;if(!["image/jpeg","image/png"].includes(blob.type))throw Error("Tệp bằng chứng không phải ảnh JPEG/PNG.");const url=URL.createObjectURL(blob);s.fileUrls.push(url);const img=el("img","tracking-evidence-image");img.src=url;img.alt="Bằng chứng lần giao "+item.attemptNumber;row.append(img);open.remove();}catch(error){if(!signal.aborted)U.failure(s,row,error);open.disabled=false;}},"btn btn-outline-secondary btn-sm");row.append(open);}host.append(row);}
      const controls=el("div","tracking-evidence-pager");controls.append(el("span","",data.totalItems+" bằng chứng · Trang "+data.page));if(page>1)controls.append(button("Bằng chứng trước",()=>loadEvidence(s,page-1)));if(page*data.pageSize<data.totalItems)controls.append(button("Bằng chứng sau",()=>loadEvidence(s,page+1)));host.append(controls);
    }catch(error){if(!signal.aborted&&s.selected===id)U.failure(s,host,error,()=>loadEvidence(s,page));}
  }
  async function mount(container,user,route,context){
    destroy();const s=active=U.state(container,user,route,context),baseDestroy=s.destroy;s.root.className="tracking-page";s.auto=route.query.auto!=="false";s.view=route.query.view||"map";s.selected=null;s.fileUrls=[];s.busy=false;
    s.visibility=()=>{clearTimeout(s.timer);s.updateTime?.();if(document.hidden){s.listAbort?.abort();s.detailAbort?.abort();}else if(!s.busy)schedule(s);};document.addEventListener("visibilitychange",s.visibility);
    s.destroy=()=>{clearTimeout(s.timer);s.listAbort?.abort();s.detailAbort?.abort();releaseEvidence(s);releaseMap(s);document.removeEventListener("visibilitychange",s.visibility);baseDestroy();};
    s.filters={keyword:route.query.keyword||"",branchId:route.query.branchId||(user.role==="ADMIN"?"":user.branchId)||"",shipperId:route.query.shipperId||"",status:route.query.status||"",statusGroup:route.query.statusGroup||(route.query.status?"":"PROGRESS"),fromDate:route.query.fromDate||"",toDate:route.query.toDate||"",page:route.query.page||1,pageSize:route.query.pageSize||10};
    // ALL has no backend filter, but remains explicit in the URL on reload.
    if(s.filters.statusGroup==="ALL")s.filters.statusGroup="";
    s.root.append(el("p","tracking-empty","Đang mở trang theo dõi giao hàng…"));
    try{s.options=await s.read("/api/v1/orders/tracking-options");if(!s.alive())return;if(!Array.isArray(s.options.branches)||!Array.isArray(s.options.shippers)||!Array.isArray(s.options.statuses))throw Error("API thiếu bộ lọc theo dõi.");shell(s);if(route.query.orderId){s.selected=Number(route.query.orderId);buildDetail(s);s.root.classList.add("tracking-show-detail");}await refresh(s);}catch(error){U.failure(s,s.root,error,()=>mount(container,user,route,context));}
  }
  window.TrackingPage=Object.freeze({mount,destroy,date,coordinates,locationState,interval});
}());

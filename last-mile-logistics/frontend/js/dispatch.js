"use strict";
(function () {
  const U=window.AdminUI,R=window.Router,{el,button}=U,UI=window.LogisticsUI;
  const storageKey="tvd.dispatch.selection",colors=["#1a73e8","#059669","#7c3aed","#ea580c","#db2777"],letters="ABCDEFGHIJKLMNO";
  // The solver alone can take 20s; allow data loading, confirmation locks,
  // persistence and response download to finish as well.
  const planningTimeoutMs=60000;
  const changedInputsMessage="Thông tin đã thay đổi. Vui lòng tính lại đề xuất.";
  const tripLabels={PLANNED:"Chờ phân công",ASSIGNED:"Chờ shipper nhận",ACCEPTED:"Đã nhận chuyến",IN_PROGRESS:"Đang thực hiện",COMPLETED:"Hoàn tất",CANCELLED:"Đã hủy"};
  const assignmentLabels={PENDING:"Chờ nhận",ACCEPTED:"Đã nhận",IN_PROGRESS:"Đang xử lý",COMPLETED:"Hoàn tất",ATTEMPT_FAILED:"Giao thất bại",REJECTED:"Đã từ chối",CANCELLED:"Đã hủy",REASSIGNED:"Đã đổi người giao"};
  let active=null;
  const number=v=>new Intl.NumberFormat("vi-VN",{maximumFractionDigits:2}).format(v||0);
  const date=value=>window.TrackingPage.date(value);
  const waiting=stop=>Number.isFinite(stop?.waitingMinutes)?number(stop.waitingMinutes)+" phút":"Chưa có dữ liệu";
  function link(label,href,cls="btn btn-outline-orange btn-sm"){const n=el("a",cls,label);n.href=href;return n;}
  function badge(value,kind="trip"){return el("span","dispatch-badge",(kind==="trip"?tripLabels:assignmentLabels)[value]||UI.statuses?.[value]||value);}
  function disable(node,condition,reason){node.disabled=!!condition;node.title=condition?reason:"";return node;}
  function readDraft(){try{const value=JSON.parse(sessionStorage.getItem(storageKey));return value&&typeof value==="object"&&!Array.isArray(value)?value:{};}catch{return {};}}
  function persist(s){checkInputs(s);try{sessionStorage.setItem(storageKey,JSON.stringify({...s.draft,ids:[...s.selected.keys()],planId:s.proposal?.id||s.draft.planId,proposalBinding:s.proposalBinding||null}));}catch{U.notice(s.feedback,"Trình duyệt không lưu được lựa chọn. Lựa chọn hiện tại vẫn dùng được.","warning");}}
  // Compare values, not mutable arrays or form controls. Order/shipper selection is a set.
  function planningKey(s){try{const r=requestFor(s);return JSON.stringify({...r,orderIds:r.orderIds.map(Number).sort((a,b)=>a-b),shipperIds:r.shipperIds.map(Number).sort((a,b)=>a-b)});}catch{return null;}}
  function invalidateProposal(s){
    s.planningRevision=(s.planningRevision||0)+1;s.proposalBinding=null;
    if(s.confirmButton)s.confirmButton.disabled=true;
    if((s.proposal||s.calculating)&&!s.confirmed)U.notice(s.feedback,changedInputsMessage,"warning");
  }
  function checkInputs(s){
    const key=planningKey(s);
    if((s.inputsKey!==undefined&&s.inputsKey!==key)||(s.proposalBinding&&s.proposalBinding.key!==key)){
      invalidateProposal(s);s.edits=null;
    }
    s.inputsKey=key;return key;
  }
  function proposalIsCurrent(s){return !!s.proposal&&!!s.proposalBinding&&s.proposalBinding.id===s.proposal.id&&s.proposalBinding.key!==null&&s.proposalBinding.key===planningKey(s);}
  function restoreProposal(s,p){
    const saved=s.draft.proposalBinding,orders=[...p.routes.flatMap(r=>r.stops),...p.unplanned];s.proposal=p;
    if(s.draft.planId!==p.id){
      // Legacy/bookmarked plans do not contain the complete original shipper set.
      // Display their saved result, but require a fresh calculation before confirming.
      s.draft={...s.draft,warehouseId:p.warehouseId,departure:localValue(p.departureAt),serviceMinutes:p.serviceMinutes,returnToDepot:p.returnToDepot,shipperIds:[...new Set(p.routes.map(r=>r.shipperId))]};
      s.selected=new Map(orders.map(o=>[o.orderId,{...o,id:o.orderId,warehouseId:p.warehouseId}]));
    }
    const key=planningKey(s);
    // Also compare the fields supplied by the persisted API result. Never bind an
    // arbitrary loaded plan ID to whichever draft happens to be in this tab.
    const sameOrders=JSON.stringify(orders.map(o=>o.orderId).sort((a,b)=>a-b))===JSON.stringify([...s.selected.keys()].sort((a,b)=>a-b));
    const matches=key&&Number(s.draft.warehouseId)===p.warehouseId&&Date.parse(requestFor(s).departureAt)===Date.parse(p.departureAt)
      &&Number(s.draft.serviceMinutes??5)===p.serviceMinutes&&(s.draft.returnToDepot!==false)===p.returnToDepot
      &&sameOrders&&p.routes.every(r=>(s.draft.shipperIds||[]).includes(r.shipperId));
    s.proposalBinding=s.draft.planId===p.id&&saved?.id===p.id&&typeof saved.key==="string"&&saved.key===key&&matches?saved:null;
    s.inputsKey=key;persist(s);
  }
  function freeMap(s){s.mapObserver?.disconnect();cancelAnimationFrame(s.mapFrame);s.map?.remove();s.map=null;}
  function destroy(){active?.destroy();active=null;}
  function sync(s,extra={}){s.query={...s.query,...extra};R.updateQuery(s.query,s.route);s.route=R.current()||s.route;}
  function field(form,fields,key,label,value,config={}){U.field(form,fields,key,label,value,config);return fields[key].control;}
  function rowCode(row){const n=el("div","dispatch-code");n.append(el("strong","",row.trackingNumber||row.tripCode),el("small","",row.orderCode||row.branchName||""));return n;}
  function orderDetails(s,row){
    const d=U.dialog(s,"Thông tin đơn hàng");if(!d)return;
    const content=el("div","dispatch-order-detail"),feedback=el("div");
    for(const [label,value] of [["Mã vận đơn",row.trackingNumber],["Mã đơn",row.orderCode]]){
      const box=el("div"),caption=el("label","form-label",label),input=el("input","form-control");input.readOnly=true;input.value=value||"";input.setAttribute("aria-label",label+" đầy đủ");
      const copy=button("Sao chép "+label.toLocaleLowerCase("vi"),async()=>{
        try{await navigator.clipboard.writeText(input.value);U.notice(feedback,"Đã sao chép "+label.toLocaleLowerCase("vi")+".","success");}
        catch{input.focus();input.select();U.notice(feedback,"Trình duyệt chưa cho phép sao chép. Mã đã được chọn; nhấn Ctrl+C hoặc dùng lệnh Sao chép.","warning");}
      });copy.disabled=!value;box.append(caption,input,copy);content.append(box);
    }
    const details=el("dl","dispatch-detail-grid");
    for(const [label,value]of [["Người nhận",row.receiverName],["Điện thoại",row.receiverPhone],["Địa chỉ giao",row.deliveryAddress],["Khu vực",row.deliveryAreaName],["Bưu cục",row.branchName],["Kho",row.warehouseName],["Khối lượng",number(row.weightKg)+" kg"],["Bắt đầu giao sớm nhất (giờ VN)",row.requestedDeliveryAt?date(row.requestedDeliveryAt):"Không giới hạn"],["Bắt đầu giao muộn nhất (giờ VN)",date(row.expectedDeliveryAt)]]){
      const item=el("div");item.append(el("dt","",label),el("dd","",value||"Chưa có"));details.append(item);
    }
    content.append(details,feedback);d.body.replaceChildren(content);
  }
  function queueCode(s,row){const n=el("div","dispatch-code"),open=button(row.trackingNumber||row.orderCode,()=>orderDetails(s,row),"dispatch-code-button");open.title="Xem đầy đủ và sao chép: "+row.trackingNumber;open.setAttribute("aria-label","Chi tiết đơn "+row.trackingNumber);const secondary=el("small","",row.orderCode);secondary.title=row.orderCode;n.append(open,secondary);return n;}
  function deadlineCell(value){
    const n=el("time","dispatch-deadline");if(!value){n.textContent="Chưa có";return n;}
    const parsed=new Date(/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)?value:value+"Z");
    if(!Number.isFinite(parsed.getTime())){n.textContent="Chưa có";return n;}
    n.dateTime=parsed.toISOString();n.append(el("span","",parsed.toLocaleDateString("vi-VN",{timeZone:"Asia/Ho_Chi_Minh"})),el("small","",parsed.toLocaleTimeString("vi-VN",{timeZone:"Asia/Ho_Chi_Minh",hour:"2-digit",minute:"2-digit"})));return n;
  }
  function isOverdue(row){const value=row.expectedDeliveryAt;if(!value)return false;return Date.parse(/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)?value:value+"Z")<Date.now();}
  function routeName(route,index){return "Tuyến "+letters[index]+" · "+route.shipperName;}
  async function write(s,path,body,signal=s.abort.signal,timeoutMs,method="POST"){window.WriteOutcome.assertCanSend(s.dialog?.signal===signal?s.dialog:s,{path,payload:body});return window.ApiClient.request(path,{method,body:JSON.stringify(body),signal,timeoutMs});}
  function pager(s,host,data,load){host.replaceChildren();if(data.totalItems<=data.pageSize)return;const total=Math.ceil(data.totalItems/data.pageSize);host.append(disable(button("Trước",()=>{sync(s,{page:data.page-1});load();}),data.page<=1,"Trang đầu"),el("span","","Trang "+data.page+" / "+total),disable(button("Sau",()=>{sync(s,{page:data.page+1});load();}),data.page>=total,"Trang cuối"));}
  function filters(s,host,kind,load){
    if(kind==="queue"){queueFilters(s,host,load);return;}
    const form=el("form","dispatch-filters"),fields={};
    field(form,fields,"keyword",kind==="trips"?"Mã chuyến / shipper / biển số":"Mã đơn / vận đơn",s.query.keyword,{type:"search",maxLength:100});
    field(form,fields,"branchId","Bưu cục",s.query.branchId,{items:[["","Tất cả bưu cục"],...s.options.branches.map(n=>[n.id,n.name])]});
    field(form,fields,"shipperId","Shipper",s.query.shipperId,{items:[["","Tất cả shipper"],...s.options.shippers.map(n=>[n.id,n.name])]});
    field(form,fields,"status","Trạng thái",s.query.status,{items:[["","Tất cả trạng thái"],...Object.entries(kind==="trips"?tripLabels:assignmentLabels)]});
    if(kind==="trips")for(const [key,label]of [["fromDate","Từ ngày"],["toDate","Đến ngày"]])field(form,fields,key,label,s.query[key],{type:"date",max:"9999-12-30"});
    const submit=button("Tìm kiếm",null,"btn btn-orange");submit.type="submit";form.append(submit,button("Làm mới",()=>load(),"btn btn-outline-orange"));
    form.addEventListener("submit",event=>{event.preventDefault();const values={page:1};for(const [key,f]of Object.entries(fields))values[key]=f.control.value;sync(s,values);load();});host.append(form);
  }
  function queueFilters(s,host,load){
    const form=el("form","dispatch-filters dispatch-queue-filters"),main=el("div","dispatch-filter-main"),fields={},advanced=el("details","dispatch-filter-more"),more=el("div","dispatch-filter-extra");
    field(main,fields,"keyword","Mã đơn / vận đơn",s.query.keyword,{type:"search",maxLength:100});
    const branch=field(main,fields,"branchId","Bưu cục",s.query.branchId,{items:[["","Tất cả bưu cục"],...s.options.branches.map(n=>[n.id,n.name])]});
    const warehouse=field(main,fields,"warehouseId",s.page==="route-optimization"?"Kho xuất phát":"Kho",s.query.warehouseId,{items:[["","Tất cả kho"]]});
    field(main,fields,"pageSize","Số đơn mỗi trang",s.query.pageSize||10,{items:[10,20,50,60].map(n=>[n,n+" đơn / trang"])});
    const actions=el("div","dispatch-filter-actions"),submit=button("Tìm kiếm",null,"btn btn-orange"),refresh=button("Làm mới",()=>{restoreFilters();load();},"btn btn-outline-orange");submit.type="submit";actions.append(submit,refresh);main.append(actions);
    advanced.append(el("summary","","Bộ lọc thêm"),more);advanced.open=!!(s.query.areaId||s.query.priority||s.query.deadlineDate);
    field(more,fields,"areaId","Khu vực giao",s.query.areaId,{items:[["","Tất cả khu vực"],...s.options.areas.map(n=>[n.id,n.name])]});
    field(more,fields,"priority","Ưu tiên",s.query.priority,{items:[["","Tất cả"],...[1,2,3,4,5].map(n=>[n,"Mức "+n+(n===1?" · Cao nhất":"")])]});
    field(more,fields,"deadlineDate","Hạn giao đến ngày",s.query.deadlineDate,{type:"date",max:"9999-12-30"});
    const setWarehouses=(items,value)=>{const allowed=items.filter(n=>!branch.value||n.branchId===Number(branch.value));warehouse.replaceChildren(...U.select([["","Tất cả kho"],...allowed.map(n=>[n.id,n.name])],"").children);warehouse.value=allowed.some(n=>n.id===Number(value))?value:"";};
    function restoreFilters(){s.filterAbort?.abort();submit.disabled=false;warehouse.disabled=false;for(const [key,f]of Object.entries(fields))f.control.value=s.query[key]??"";setWarehouses(s.options.warehouses,s.query.warehouseId);}
    setWarehouses(s.options.warehouses,s.query.warehouseId);
    branch.addEventListener("change",async()=>{
      s.filterAbort?.abort();const pending=s.filterAbort=new AbortController(),signal=AbortSignal.any([s.abort.signal,pending.signal]);const previous=warehouse.value;setWarehouses(s.options.warehouses,previous);submit.disabled=true;warehouse.disabled=true;
      try{const options=await s.read("/api/v1/dispatch/options?"+U.query({branchId:branch.value}),signal);if(signal.aborted)return;setWarehouses(options.warehouses,warehouse.value);}
      catch(error){if(!signal.aborted)U.failure(s,s.feedback,error,()=>branch.dispatchEvent(new Event("change")));}
      finally{if(!signal.aborted){submit.disabled=false;warehouse.disabled=false;}}
    });
    form.addEventListener("submit",event=>{event.preventDefault();if(submit.disabled)return;const values={page:1};for(const [key,f]of Object.entries(fields))values[key]=f.control.value;
      if(s.page==="route-optimization"&&Number(s.draft.warehouseId)!==Number(values.warehouseId)){s.draft.warehouseId=Number(values.warehouseId)||null;s.draft.shipperIds=[];s.draft.planId=null;s.draft.proposalBinding=null;values.planId=null;s.proposal=null;s.edits=null;s.dirty=false;invalidateProposal(s);}
      sync(s,values);load(true);});
    form.append(main,advanced);host.append(form);
  }
  function queryFor(s,keys){return Object.fromEntries(keys.filter(k=>s.query[k]!==undefined&&s.query[k]!=="").map(k=>[k,s.query[k]]));}
  async function hydrate(s){
    const ids=Array.isArray(s.draft.ids)?s.draft.ids.filter(id=>Number.isSafeInteger(id)&&id>0).slice(0,60):[];
    if(!ids.length)return;
    const data=await s.read("/api/v1/dispatch/orders?"+U.query({ids:ids.join(","),pageSize:100}));if(!s.alive())return;
    for(const row of data.items)if(!isOverdue(row))s.selected.set(row.id,row);
    if(data.items.length!==ids.length)s.selectionNotice="Một số đơn đã rời hàng chờ và được bỏ khỏi lựa chọn. Hãy kiểm tra lại.";
  }
  function selectionBar(s){
    const bar=el("div","dispatch-selection"),summary=el("div"),total=el("span"),hint=el("small","dispatch-selection-hint"),actions=el("div","dispatch-actions");summary.append(total,hint);
    const next=button("Lập phương án giao",()=>{s.draft.warehouseId=[...s.selected.values()][0]?.warehouseId;persist(s);if(s.page==="route-optimization")wizard(s,2);else R.navigate(R.href("route-optimization",{},{step:2}));},"btn btn-orange");
    const clear=button("Bỏ chọn",()=>{s.selected.clear();persist(s);s.selectionUpdate();});
    const manual=button("Tạo chuyến thủ công",()=>createTrip(s),"btn btn-outline-orange");
    hint.id="dispatch-selection-guidance";next.setAttribute("aria-describedby",hint.id);manual.setAttribute("aria-describedby",hint.id);
    actions.append(clear,next);
    if(s.page==="dispatch-queue"&&s.can("DIEUPHOI_PHANCONG"))actions.append(manual);
    bar.append(summary,actions);s.selectionUpdate=()=>{
      total.textContent=s.selected.size+" đơn đã chọn · "+number([...s.selected.values()].reduce((sum,n)=>sum+Number(n.weightKg),0))+" kg";
      const chosen=[...s.selected.values()],mixed=chosen.some(n=>!n.warehouseId||n.warehouseId!==chosen[0]?.warehouseId);
      hint.textContent=mixed?"Chọn đơn trong cùng một kho để lập chuyến. Hãy lọc theo kho trước.":!s.selected.size?"Chọn đơn trong một kho để tiếp tục; có thể hiển thị tối đa 60 đơn mỗi trang.":"Lựa chọn thuộc trang hiện tại; đổi bộ lọc hoặc trang sẽ bỏ chọn.";
      disable(next,s.loading||!s.selected.size||mixed||!s.can("DIEUPHOI_TOIUUTUYEN"),mixed?"Các đơn phải cùng kho.":!s.can("DIEUPHOI_TOIUUTUYEN")?"Cần quyền tối ưu tuyến.":"Chọn ít nhất một đơn để tiếp tục");
      disable(manual,s.loading||!s.selected.size||mixed,mixed?"Các đơn phải cùng kho.":"Chọn ít nhất một đơn để tiếp tục");clear.disabled=s.loading||!s.selected.size;s.queueSelectionUpdate?.();
    };s.selectionUpdate();return bar;
  }
  async function queue(s,host){
    const wrap=el("section","dispatch-section"),controls=el("div"),body=el("div","dispatch-table-host"),pages=el("div","dispatch-pager");s.queueHost=body;
    const load=async(reset=false)=>{
      s.listAbort?.abort();const pending=s.listAbort=new AbortController(),signal=AbortSignal.any([s.abort.signal,pending.signal]);
      s.loading=true;s.queueSelectionUpdate=null;s.selectionUpdate?.();body.setAttribute("aria-busy","true");body.replaceChildren(el("p","dispatch-empty","Đang tải hàng chờ…"));pages.replaceChildren();U.notice(s.feedback,"");
      if(reset&&s.selected.size){s.selected.clear();persist(s);U.notice(s.feedback,"Đã bỏ chọn khi đổi bộ lọc hoặc trang. Chỉ chọn đơn trên trang đang xem.","info");s.selectionUpdate?.();}
      try{
        const q=queryFor(s,["keyword","branchId","warehouseId","areaId","priority","deadlineDate","page","pageSize"]);q.pageSize=q.pageSize||10;
        const data=window.ApiClient.validatePage(await s.read("/api/v1/dispatch/orders?"+U.query(q),signal),"dispatch/orders",["id"]);if(!s.alive()||signal.aborted)return;
        const visible=new Map(data.items.map(row=>[row.id,row]));let removed=0;
        for(const id of s.selected.keys()){const row=visible.get(id);if(!visible.has(id)||row?.hasEligibleShipper===false||isOverdue(row||{})){s.selected.delete(id);removed++;}else s.selected.set(id,row);}persist(s);
        if(removed)U.notice(s.feedback,"Đã bỏ "+removed+" đơn không còn ở trang này hoặc không còn đủ điều kiện. Lựa chọn chỉ thuộc trang đang xem.","info");
        const all=el("input","form-check-input");all.type="checkbox";all.setAttribute("aria-label","Chọn các đơn trên trang hiện tại");
        s.queueSelectionUpdate=()=>{
          const selectable=data.items.filter(n=>n.hasEligibleShipper!==false&&!isOverdue(n));
          const count=selectable.filter(n=>s.selected.has(n.id)).length;
          all.checked=selectable.length>0&&count===selectable.length;
          all.indeterminate=count>0&&count<selectable.length;
          all.disabled=s.loading||!selectable.length;
          body.querySelectorAll("input[data-order]").forEach(n=>{
            const id=Number(n.dataset.order);
            const rowData=visible.get(id);
            n.checked=s.selected.has(id);
            n.disabled=!!s.loading||rowData?.hasEligibleShipper===false||isOverdue(rowData||{});
          });
        };
        const select=(row,chosen)=>{
          if(row.hasEligibleShipper===false||isOverdue(row))return false;
          if(chosen&&s.selected.size>=60&&!s.selected.has(row.id)){U.notice(s.feedback,"Mỗi phương án chọn tối đa 60 đơn.","warning");return false;}
          if(chosen)s.selected.set(row.id,row);else s.selected.delete(row.id);persist(s);s.selectionUpdate?.();return true;
        };
        all.addEventListener("change",()=>{
          const chosen=all.checked;
          for(const row of data.items){
            if(row.hasEligibleShipper===false||isOverdue(row))continue;
            select(row,chosen);
          }
          s.selectionUpdate?.();
        });
        const rows=data.items.map(row=>{
          const late=isOverdue(row),canDeliver=row.hasEligibleShipper!==false;
          const pick=el("input","form-check-input");pick.type="checkbox";pick.dataset.order=row.id;pick.checked=s.selected.has(row.id);pick.setAttribute("aria-label","Chọn "+row.trackingNumber);
          if(!canDeliver||late){pick.disabled=true;pick.title=late?"Quá hạn: cần CSKH xác nhận lại với khách.":"Khu vực giao chưa có shipper nào của bưu cục phụ trách";}
          pick.addEventListener("change",()=>{if(!select(row,pick.checked))pick.checked=false;const selectable=data.items.filter(n=>n.hasEligibleShipper!==false&&!isOverdue(n));all.checked=selectable.length>0&&selectable.every(n=>s.selected.has(n.id));});
          const recipient=el("div","dispatch-recipient");recipient.append(el("span","",row.receiverName),el("small","dispatch-address",row.deliveryAddress));recipient.lastChild.title=row.deliveryAddress;
          const actions=el("div","dispatch-row-actions");
          if(late){
            actions.append(s.can("DONHANG_CAPNHAT")||(s.can("DONHANG_HUY")&&s.can("KHO_KIEMKE"))?button("Xử lý quá hạn",()=>overdueDialog(s,row)):el("small","","Cần CSKH xử lý quá hạn"));
          }else if(s.can("DIEUPHOI_PHANCONG")){
            const assignBtn=button("Phân công",()=>assignmentDialog(s,row));
            if(!canDeliver){assignBtn.disabled=true;assignBtn.title="Chưa có shipper phụ trách khu vực này";}
            actions.append(assignBtn);
          }else actions.append(el("small","","Cần quyền phân công"));
          const areaCell=el("div","dispatch-area-info");areaCell.append(el("span","",row.deliveryAreaName||"Chưa có"));
          if(!canDeliver){const badgeNoShipper=el("small","badge bg-danger ms-1 text-white","Chưa có shipper");badgeNoShipper.title="Khu vực giao chưa có shipper nào của bưu cục phụ trách";areaCell.append(badgeNoShipper);}
          const deadline=deadlineCell(row.expectedDeliveryAt);if(late)deadline.append(el("strong","text-danger","Quá hạn · Chờ CSKH"));
          return [pick,queueCode(s,row),recipient,areaCell,el("span","dispatch-weight",number(row.weightKg)+" kg"),deadline,badge(row.statusName||row.status),actions];
        });
        const selectableCount=data.items.filter(n=>n.hasEligibleShipper!==false).length;
        body.replaceChildren(el("p","dispatch-count",data.totalItems+" đơn chờ · Trang này: "+selectableCount+" có người phụ trách, "+(data.items.length-selectableCount)+" chưa có người phụ trách · Đơn quá hạn cần CSKH xác nhận trước khi giao hoặc hủy."),data.items.length?UI.table(["Chọn","Vận đơn","Người nhận / địa chỉ","Khu vực","Khối lượng","Hạn giao","Trạng thái","Thao tác"],rows):el("p","dispatch-empty","Không có đơn chờ với bộ lọc này."));
        // The shared table header accepts text; replace the first heading with the actual accessible checkbox.
        body.querySelector("th")?.replaceChildren(all);
        const table=body.querySelector("table");if(table){table.classList.add("dispatch-queue-table");const cols=el("colgroup");for(const name of ["select","code","recipient","area","weight","deadline","status","actions"]){const col=el("col","dispatch-col-"+name);cols.append(col);}table.prepend(cols);const scroll=table.parentElement;scroll.tabIndex=0;scroll.setAttribute("role","region");scroll.setAttribute("aria-label","Danh sách đơn hàng; cuộn ngang trên màn hình nhỏ");}
        pager(s,pages,data,()=>load(true));
      }catch(error){if(!signal.aborted){s.queueSelectionUpdate=null;U.failure(s,s.feedback,error,()=>load());body.replaceChildren(el("p","dispatch-empty","Không tải được hàng chờ. Xem lỗi phía trên và thử lại."));s.selected.clear();persist(s);}}
      finally{if(!signal.aborted){s.loading=false;body.setAttribute("aria-busy","false");s.selectionUpdate?.();}}
    };
    filters(s,controls,"queue",load);wrap.append(controls,selectionBar(s),body,pages);host.append(wrap);await load();
  }
  function overdueDialog(s,row){
    const d=U.dialog(s,"CSKH xác nhận đơn quá hạn");if(!d)return;
    const form=el("form","dispatch-dialog-form"),fields={},feedback=el("div"),choices=[["","Chọn kết quả xác nhận với khách"]];
    if(s.can("DONHANG_CAPNHAT"))choices.push(["KEEP","Khách vẫn nhận — ưu tiên giao"]);
    if(s.can("DONHANG_HUY")&&s.can("KHO_KIEMKE")&&s.can("KHO_XEM"))choices.push(["CANCEL","Khách hủy — chuyển hàng chờ xử lý"]);
    form.append(el("p","",row.trackingNumber+" · "+row.receiverName+" · "+(row.receiverPhone||"Chưa có số điện thoại")),el("p","text-secondary","Gọi hoặc nhắn tin xác nhận trước khi chọn. Chưa liên hệ được khách thì đóng hộp thoại; đơn vẫn chờ CSKH xử lý."));
    const decision=field(form,fields,"decision","Kết quả khách xác nhận","",{items:choices,required:true});
    field(form,fields,"contactNote","Nội dung xác nhận / lý do hủy","",{required:true,maxLength:500,multiline:true});
    const deadlineBox=el("div"),locationBox=el("div");
    const deadline=field(deadlineBox,fields,"deliveryDeadline","Hạn giao mới đã thống nhất (giờ Việt Nam)","",{type:"datetime-local"});
    const location=field(locationBox,fields,"locationId","Vị trí hàng chờ xử lý","",{items:[["","Chọn vị trí trong cùng kho"]]});
    const submit=button("Lưu kết quả xác nhận",null,"btn btn-orange");submit.type="submit";submit.disabled=true;
    form.append(deadlineBox,locationBox,feedback,submit);d.body.replaceChildren(form);deadlineBox.hidden=true;locationBox.hidden=true;
    let locations=[],sequence=0;
    decision.addEventListener("change",async()=>{const revision=++sequence;deadlineBox.hidden=decision.value!=="KEEP";locationBox.hidden=decision.value!=="CANCEL";deadline.required=decision.value==="KEEP";location.required=decision.value==="CANCEL";submit.disabled=!decision.value;U.notice(feedback,"");
      if(decision.value!=="CANCEL")return;submit.disabled=true;
      try{const data=await s.read("/api/v1/warehouses/"+row.warehouseId+"/locations",d.signal);if(d.signal.aborted||revision!==sequence)return;
        locations=data.filter(n=>n.warehouseId===row.warehouseId&&n.id!==row.locationId&&n.isActive);
        location.replaceChildren(...U.select([["","Chọn vị trí trong cùng kho"],...locations.map(n=>[n.id,n.code+" · "+(n.storageArea||"")])],"").children);
        location.value="";
        if(!locations.length)U.notice(feedback,"Kho chưa có vị trí đích khác nguồn. Cần bổ sung vị trí chờ xử lý.","warning");submit.disabled=!locations.length;
      }catch(error){if(!d.signal.aborted&&revision===sequence)U.failure(s,feedback,error);}
    });
    form.addEventListener("submit",async event=>{event.preventDefault();if(submit.disabled||d.busy||d.writeUnknown||!form.reportValidity())return;
      const payload={decision:decision.value,contactNote:fields.contactNote.control.value.trim()};if(!payload.contactNote){U.notice(feedback,"Cần nội dung xác nhận với khách.","warning");return;}
      if(payload.decision==="KEEP"){const time=new Date(deadline.value+"+07:00");if(!Number.isFinite(time.getTime())||time<=new Date()){U.notice(feedback,"Chọn hạn giao mới trong tương lai.","warning");return;}payload.deliveryDeadline=time.toISOString();}
      else if(payload.decision==="CANCEL"&&locations.some(n=>n.id===Number(location.value)))payload.locationId=Number(location.value);else return;
      const path="/api/v1/dispatch/orders/"+row.id+"/resolve-overdue";submit.disabled=true;d.busyState(true);
      try{await write(s,path,payload,d.signal);d.close();R.reload();}catch(error){d.busyState(false);if(window.WriteOutcome.lock(d,feedback,error,{path,payload,scope:form}))return;U.failure(s,feedback,error);submit.disabled=error.status===409;}
    });
  }
  async function assignmentDialog(s,row,reassign=false){
    const d=U.dialog(s,reassign?"Đổi người giao":"Phân công đơn");if(!d)return;
    try{
      const candidatePath="/api/v1/dispatch/shippers?"+U.query({orderId:row.orderId||row.id,assignmentId:reassign?row.id:""});
      let data=await s.read(candidatePath,d.signal),conflicted=false;if(d.signal.aborted)return;
      const form=el("form","dispatch-dialog-form"),fields={},feedback=el("div");
      form.append(el("p","dispatch-dialog-order",row.trackingNumber+" · "+number(data.orderWeightKg??row.weightKg)+" kg"));
      form.append(el("p","text-secondary","Phân công từng đơn xét tải còn lại của xe. Lập tuyến mới cần shipper/xe không có nhiệm vụ hoặc chuyến chưa kết thúc; không tự ghép vào tuyến đang chạy."));
      const driver=field(form,fields,"shipperId","Shipper đủ điều kiện","",{items:[],required:true});
      const vehicle=field(form,fields,"vehicleId","Phương tiện đủ điều kiện / tải trọng","",{items:[],required:true});
      field(form,fields,reassign?"reason":"notes",reassign?"Lý do đổi":"Ghi chú","",{multiline:true,required:reassign,maxLength:500});
      if(!reassign)field(form,fields,"pickupDueAt","Hạn đến kho lấy hàng (giờ Việt Nam, có thể để trống)","",{type:"datetime-local"});
      const reasons=el("details","dispatch-reasons");form.append(reasons);
      const save=button(reassign?"Xác nhận đổi người giao":"Xác nhận phân công",null,"btn btn-orange"),cancel=button("Hủy",()=>d.close(),"btn btn-outline-secondary"),actions=el("div","dispatch-actions");save.type="submit";actions.append(cancel,save);form.append(feedback,actions);d.body.replaceChildren(form);
      function vehicles(previous){if(d.writeUnknown)return;const items=data.items.filter(n=>n.id===Number(driver.value));vehicle.replaceChildren(...U.select(items.map(n=>[n.vehicleId,n.licensePlate+" · Tải "+number(n.maxWeightKg)+" kg · Còn "+number(n.remainingWeightKg)+" kg"]),previous||items[0]?.vehicleId).children);vehicle.value=items.some(n=>n.vehicleId===Number(previous))?previous:(items[0]?.vehicleId??"");save.disabled=conflicted||!items.length;}
      function candidates(){const previous=driver.value,items=[...new Map(data.items.map(n=>[n.id,n])).values()];driver.replaceChildren(...U.select([["","Chọn shipper"],...items.map(n=>[n.id,n.fullName])],"").children);driver.value=items.some(n=>n.id===Number(previous))?previous:(items[0]?.id??"");vehicles(vehicle.value);
        const excluded=[...(data.excludedVehicles||[]).map(n=>n.fullName+" · "+(n.licensePlate||"Chưa có xe")+": "+n.eligibilityReason),...(data.excludedShippers||[]).map(n=>n.fullName+": "+n.eligibilityReason)];reasons.hidden=!excluded.length;reasons.replaceChildren(el("summary","","Không đủ điều kiện ("+excluded.length+")"),...excluded.map(text=>el("p","",text)));
      }
      driver.addEventListener("change",()=>vehicles());candidates();
      if(!data.items.length)U.notice(feedback,"Chưa có shipper/xe đủ điều kiện phụ trách khu vực giao.","warning");
      form.addEventListener("submit",async event=>{event.preventDefault();if(save.disabled||d.busy||d.writeUnknown||!form.reportValidity())return;const chosen=data.items.find(n=>n.id===Number(driver.value)&&n.vehicleId===Number(vehicle.value));if(!chosen)return;save.disabled=true;cancel.disabled=true;driver.disabled=true;vehicle.disabled=true;d.busyState(true);
        try{const payload={shipperId:chosen.id,vehicleId:chosen.vehicleId};payload[reassign?"reason":"notes"]=fields[reassign?"reason":"notes"].control.value;if(!reassign){payload.orderId=row.id;const due=fields.pickupDueAt.control.value;if(due)payload.pickupDueAt=new Date(due+"+07:00").toISOString();}await write(s,reassign?"/api/v1/dispatch/assignments/"+row.id+"/reassign":"/api/v1/dispatch/assignments",payload,d.signal);d.close();s.selected.delete(row.orderId||row.id);persist(s);R.reload();}
        catch(error){if(d.signal.aborted)return;d.busyState(false);if(window.WriteOutcome.lock(d,feedback,error,{path:"/api/v1/dispatch/assignments",payload:{orderId:row.orderId||row.id},scope:form}))return;U.failure(s,feedback,error);conflicted=error.status===409;save.disabled=conflicted;cancel.disabled=false;driver.disabled=false;vehicle.disabled=false;
          if(error.status===409){const refresh=button("Cập nhật dữ liệu",async()=>{refresh.disabled=true;save.disabled=true;try{data=await s.read(candidatePath,d.signal);if(d.signal.aborted)return;conflicted=false;candidates();U.notice(feedback,data.items.length?"Đã cập nhật danh sách. Kiểm tra shipper và xe trước khi xác nhận lại.":"Chưa có shipper/xe đủ điều kiện.","warning");}catch(next){if(!d.signal.aborted){U.failure(s,feedback,next);feedback.append(button("Đóng và tải lại hàng chờ",()=>{d.close();R.reload();}));}}finally{refresh.disabled=false;}});feedback.append(refresh);}
        }
      });
    }catch(error){if(!d.signal.aborted)U.failure(s,d.body,error);}
  }
  function pickupDeadlineDialog(s,row){
    const d=U.dialog(s,"Hạn đến kho lấy hàng");if(!d)return;
    const form=el("form","dispatch-dialog-form"),fields={},feedback=el("div");
    form.append(el("p","",row.trackingNumber+" · "+row.shipperName),el("p","text-secondary","Điều phối đặt hạn riêng. Để trống là chưa quy định, không báo trễ. Hạn chỉ để theo dõi, không tự hủy đơn khi trễ."));
    field(form,fields,"due","Hạn đến kho (giờ Việt Nam)",row.pickupDueAt?localValue(row.pickupDueAt):"",{type:"datetime-local"});
    field(form,fields,"reason","Lý do đặt / sửa / bỏ hạn","",{required:true,maxLength:500,multiline:true});
    const save=button("Lưu hạn lấy hàng",null,"btn btn-orange");save.type="submit";form.append(feedback,save);d.body.replaceChildren(form);
    form.addEventListener("submit",async event=>{
      event.preventDefault();if(save.disabled||d.writeUnknown||!form.reportValidity())return;
      const value=fields.due.control.value,due=value?new Date(value+"+07:00"):null;
      if(due&&due<=new Date()){U.notice(feedback,"Chọn hạn trong tương lai.","warning");return;}
      const existing=row.pickupDueAt,payload={pickupDueAt:due?.toISOString()??null,expectedPickupDueAt:existing?new Date(/(?:Z|[+-]\d{2}:\d{2})$/i.test(existing)?existing:existing+"Z").toISOString():null,reason:fields.reason.control.value.trim()};
      const path="/api/v1/dispatch/assignments/"+row.id+"/pickup-deadline";save.disabled=true;d.busyState(true);
      try{await write(s,path,payload,d.signal,undefined,"PATCH");d.close();R.reload();}
      catch(error){d.busyState(false);if(window.WriteOutcome.lock(d,feedback,error,{path,payload,scope:form}))return;U.failure(s,feedback,error);save.disabled=error.status===409;}
    });
  }
  function reasonDialog(s,title,path,payload={}){
    const d=U.dialog(s,title);if(!d)return;const form=el("form","dispatch-dialog-form"),fields={},feedback=el("div");field(form,fields,"reason","Lý do","",{required:true,maxLength:500,multiline:true});const save=button(title,null,"btn btn-orange");save.type="submit";form.append(feedback,save);d.body.replaceChildren(form);
    form.addEventListener("submit",async event=>{event.preventDefault();if(save.disabled||d.writeUnknown||!form.reportValidity())return;save.disabled=true;d.busyState(true);try{await write(s,path,{...payload,reason:fields.reason.control.value},d.signal);d.close();R.reload();}catch(error){d.busyState(false);if(window.WriteOutcome.lock(d,feedback,error,{path,scope:form}))return;U.failure(s,feedback,error);save.disabled=false;}});
  }
  function startListRequest(s,body,pages,message){
    const sequence=s.listSequence=(s.listSequence||0)+1;
    s.listAbort?.abort();const controller=s.listAbort=new AbortController();
    const signal=AbortSignal.any([s.abort.signal,controller.signal]);
    // Check sequence as well as cancellation: a transport may still resolve or
    // reject an older request after abort, including during response parsing.
    const current=()=>s.alive()&&!signal.aborted&&sequence===s.listSequence&&s.listAbort===controller;
    s.loading=true;body.setAttribute("aria-busy","true");body.replaceChildren(el("p","dispatch-empty",message));pages.replaceChildren();U.notice(s.feedback,"");
    return {signal,current,finish(){if(current()){s.loading=false;body.setAttribute("aria-busy","false");s.listAbort=null;}}};
  }
  async function assignments(s){
    const host=el("div"),filtersHost=el("div"),body=el("div","dispatch-table-host"),pages=el("div","dispatch-pager");s.content.append(host);host.append(filtersHost,body,pages);
    const load=async()=>{if(!s.alive())return;const request=startListRequest(s,body,pages,"Đang tải phân công…");
      const query=queryFor(s,["keyword","branchId","shipperId","status","page","pageSize"]);
      try{const response=await s.read("/api/v1/dispatch/assignments?"+U.query(query),request.signal);if(!request.current())return;
      const data=window.ApiClient.validatePage(response,"assignments",["id"]);
      body.replaceChildren(el("p","dispatch-count",data.totalItems+" phân công"),data.items.length?UI.table(["Vận đơn","Shipper / xe","Trạng thái","Phân công lúc","Hạn đến lấy hàng",""],data.items.map(row=>{
        const person=el("div");person.append(el("span","",row.shipperName),el("small","",row.licensePlate));const actions=el("div","dispatch-actions");
        if(row.tripId)actions.append(link("Mở chuyến",R.href("delivery-trips",{},{tripId:row.tripId})));
        else if(row.isActive&&row.orderStatus==="ASSIGNED"&&["PENDING","ACCEPTED"].includes(row.assignmentStatus)&&s.can("DIEUPHOI_PHANCONG"))actions.append(button("Đổi người giao",()=>assignmentDialog(s,row,true)),button("Hủy phân công",()=>reasonDialog(s,"Hủy phân công","/api/v1/dispatch/assignments/"+row.id+"/cancel")));
        if(row.isActive&&row.orderStatus==="ASSIGNED"&&["PENDING","ACCEPTED"].includes(row.assignmentStatus)&&s.can("DIEUPHOI_PHANCONG"))actions.append(button("Đặt hạn lấy hàng",()=>pickupDeadlineDialog(s,row)));
        return [rowCode(row),person,badge(row.assignmentStatus,"assignment"),date(row.assignedAt),row.pickupDueAt?date(row.pickupDueAt):"Chưa đặt hạn",actions];
      })):el("p","dispatch-empty","Không có phân công phù hợp."));pager(s,pages,data,load);
    }catch(error){if(request.current()&&error.name!=="AbortError"){U.failure(s,s.feedback,error,load);body.replaceChildren(el("p","dispatch-empty","Không tải được phân công. Hãy thử lại."));}}
      finally{request.finish();}};filters(s,filtersHost,"assignments",load);await load();
  }
  async function createTrip(s){
    if(!s.selected.size){U.notice(s.feedback,"Chọn đơn trước khi tạo chuyến.","warning");return;}
    const rows=[...s.selected.values()],warehouse=s.options.warehouses.find(w=>w.id===Number(rows[0].warehouseId));
    if(!warehouse||rows.some(n=>n.warehouseId!==warehouse.id)){U.notice(s.feedback,"Chọn các đơn đang nằm trong cùng một kho.","warning");return;}
    const d=U.dialog(s,"Tạo chuyến thủ công");if(!d)return;const form=el("form","dispatch-dialog-form"),fields={},feedback=el("div");form.append(el("p","",warehouse.name+" · "+rows.length+" đơn · "+number(rows.reduce((sum,n)=>sum+n.weightKg,0))+" kg"));
    field(form,fields,"departure","Xuất phát dự kiến",s.draft.departure||localFuture(),{type:"datetime-local",required:true});const save=button("Tạo chuyến chờ phân công",null,"btn btn-orange");save.type="submit";form.append(feedback,save);d.body.replaceChildren(form);
    form.addEventListener("submit",async event=>{event.preventDefault();if(save.disabled||d.writeUnknown||!form.reportValidity())return;save.disabled=true;d.busyState(true);try{const result=await write(s,"/api/v1/trips",{warehouseId:warehouse.id,branchId:warehouse.branchId,orderIds:rows.map(n=>n.id),plannedStartAt:new Date(fields.departure.control.value+"+07:00").toISOString()},d.signal);d.close();s.selected.clear();persist(s);R.navigate(R.href("delivery-trips",{},{tripId:result.id}));}catch(error){d.busyState(false);if(window.WriteOutcome.lock(d,feedback,error,{path:"/api/v1/trips",payload:{branchId:warehouse.branchId},scope:form}))return;U.failure(s,feedback,error);save.disabled=false;}});
  }
  async function trips(s){
    if(s.query.tripId){await tripDetail(s,Number(s.query.tripId));return;}
    const filterHost=el("div"),body=el("div","dispatch-table-host"),pages=el("div","dispatch-pager");s.content.append(filterHost,body,pages);
    const load=async()=>{if(!s.alive())return;const request=startListRequest(s,body,pages,"Đang tải chuyến giao…");
      const query=queryFor(s,["keyword","branchId","shipperId","status","fromDate","toDate","page","pageSize"]);
      try{const response=await s.read("/api/v1/trips?"+U.query(query),request.signal);if(!request.current())return;
      const data=window.ApiClient.validatePage(response,"trips",["id"]);
      body.replaceChildren(el("p","dispatch-count",data.totalItems+" chuyến giao"),data.items.length?UI.table(["Chuyến / kho","Shipper / phương tiện","Trạng thái","Đơn / tải","Xuất phát dự kiến",""],data.items.map(row=>{
        const code=el("div");code.append(el("strong","",row.tripCode),el("small","",row.warehouseName));const driver=el("div");driver.append(el("span","",row.shipperName||"Chưa phân công"),el("small","",row.licensePlate||"Chưa chọn xe"));
        return [code,driver,badge(row.status),row.orderCount+" đơn · "+number(row.totalWeightKg)+" kg",date(row.plannedStartAt),link("Xem chuyến",R.href("delivery-trips",{},{...query,tripId:row.id}))];
      })):el("p","dispatch-empty","Chưa có chuyến phù hợp. Chọn đơn ở Hàng chờ để tạo chuyến."));pager(s,pages,data,load);
    }catch(error){if(request.current()&&error.name!=="AbortError"){U.failure(s,s.feedback,error,load);body.replaceChildren(el("p","dispatch-empty","Không tải được chuyến giao. Hãy thử lại."));}}
      finally{request.finish();}};filters(s,filterHost,"trips",load);s.content.append(link("Chọn đơn tạo chuyến",R.href("dispatch-queue")));await load();
  }

  async function emergencyReassignTripDialog(s, trip) {
    const uncompletedOrders = (trip.orders || []).filter(o =>
      !["DELIVERED", "COMPLETED", "CANCELLED", "RETURNED"].includes(o.orderStatus)
    );
    if (!uncompletedOrders.length) {
      U.notice(s.feedback, "Tất cả các đơn trong chuyến này đã hoàn tất hoặc đã hủy, không còn đơn nào cần chuyển.", "warning");
      return;
    }
    const d = U.dialog(s, "🚨 Chuyển chuyến khẩn cấp khi tài xế gặp sự cố");
    if (!d) return;

    const form = el("form", "dispatch-dialog-form"), fields = {}, feedback = el("div");
    const alertBox = el("div", "alert alert-danger p-2 mb-3");
    alertBox.innerHTML = "<strong>Chuyến: " + trip.tripCode + " · Tài xế hiện tại: " + (trip.shipperName || "Chưa có") + "</strong><div class='small text-muted mt-1'>Sẽ chuyển toàn bộ " + uncompletedOrders.length + " đơn chưa hoàn tất sang tài xế thay thế ngay lập tức.</div>";
    form.append(alertBox);

    field(form, fields, "shipperId", "Tài xế thay thế sẵn sàng *", "", {
      required: true,
      items: [
        ["", "Chọn tài xế tiếp quản"],
        ...s.options.shippers
          .filter(sh => sh.id !== trip.shipperId && (!trip.branchId || sh.branchId === trip.branchId))
          .map(sh => [sh.id, sh.name + " · " + (sh.licensePlate || "Chưa có xe")])
      ]
    });

    field(form, fields, "incidentType", "Loại sự cố khẩn cấp *", "VEHICLE_BREAKDOWN", {
      required: true,
      items: [
        ["VEHICLE_BREAKDOWN", "Hỏng xe dọc đường (Thủng lốp, chết máy, đứt xích...)"],
        ["HEALTH_ACCIDENT", "Tai nạn giao thông / Sức khỏe khẩn cấp"],
        ["WEATHER_FLOOD", "Ngập lụt / Sự cố thời tiết bất khả kháng"],
        ["OTHER", "Lý do khẩn cấp khác"]
      ]
    });

    field(form, fields, "reasonDetail", "Ghi chú chi tiết sự cố *", "", {
      required: true,
      maxLength: 500,
      multiline: true,
      placeholder: "Mô tả sự cố gặp phải và vị trí tài xế bàn giao hàng..."
    });

    const submitBtn = button("🚨 Xác nhận chuyển " + uncompletedOrders.length + " đơn sang tài xế mới", null, "btn btn-danger");
    submitBtn.type = "submit";
    form.append(feedback, submitBtn);
    d.body.replaceChildren(form);

    form.addEventListener("submit", async event => {
      event.preventDefault();
      if (submitBtn.disabled || d.busy || !form.reportValidity()) return;
      const newShipperId = Number(fields.shipperId.control.value);
      const chosenDriver = s.options.shippers.find(n => n.id === newShipperId);
      if (!chosenDriver) {
        U.notice(feedback, "Vui lòng chọn tài xế thay thế.", "warning");
        return;
      }

      const reasonText = "[" + fields.incidentType.control.value + "] " + fields.reasonDetail.control.value.trim();
      submitBtn.disabled = true;
      d.busyState(true);
      U.notice(feedback, "Đang xử lý chuyển toàn bộ " + uncompletedOrders.length + " đơn hàng…", "info");

      let successCount = 0;
      let failCount = 0;

      for (const ord of uncompletedOrders) {
        try {
          if (ord.assignmentId) {
            await write(s, "/api/v1/dispatch/assignments/" + ord.assignmentId + "/reassign", {
              shipperId: chosenDriver.id,
              vehicleId: chosenDriver.vehicleId || 1,
              reason: reasonText
            }, d.signal);
            successCount++;
          }
        } catch (err) {
          failCount++;
        }
      }

      d.busyState(false);
      d.close();
      U.notice(
        s.feedback,
        "Đã chuyển thành công " + successCount + "/" + uncompletedOrders.length + " đơn sang tài xế " + chosenDriver.name + (failCount > 0 ? " (thất bại " + failCount + " đơn)" : "") + ".",
        successCount > 0 ? "success" : "danger"
      );
      R.reload();
    });
  }

  async function tripDetail(s,id){
    const d=await s.read("/api/v1/trips?id="+id);if(!s.alive())return;s.trip=d;
    const actions=el("div","dispatch-actions");actions.append(link("‹ Danh sách chuyến",R.href("delivery-trips",{},{...s.query,tripId:""})));
    if(d.status==="PLANNED"&&s.can("DIEUPHOI_PHANCONG"))actions.append(button("Sửa / phân công chuyến",()=>editTrip(s,d)));
    if(d.status==="PLANNED"&&s.can("DIEUPHOI_TOIUUTUYEN"))actions.append(link("Tính đề xuất tuyến",R.href("route-optimization",{},{tripId:id,step:2}),"btn btn-orange"));
    if(["PLANNED","ASSIGNED","ACCEPTED"].includes(d.status)&&s.can("DIEUPHOI_PHANCONG"))actions.append(button("Hủy chuyến",()=>reasonDialog(s,"Hủy chuyến","/api/v1/trips/"+id+"/actions",{action:"CANCEL"})));
    if(["ASSIGNED","ACCEPTED","IN_PROGRESS","DELIVERING"].includes(d.status)&&s.can("DIEUPHOI_PHANCONG"))actions.append(button("🚨 Chuyển đơn sự cố khẩn cấp",()=>emergencyReassignTripDialog(s,d),"btn btn-outline-danger"));
    const summary=el("div","dispatch-trip-summary");summary.append(el("h2","",d.tripCode),badge(d.status),el("p","",d.warehouseName+" · "+(d.shipperName||"Chưa chọn shipper")+" · "+(d.licensePlate||"Chưa chọn xe")),el("p","",d.orderCount+" đơn · "+number(d.totalWeightKg)+" kg · Xuất phát "+date(d.plannedStartAt)));
    if(d.totalDistanceKm!=null)summary.append(el("p","",number(d.totalDistanceKm)+" km · "+number(d.estimatedDurationMinutes)+" phút (ước tính đã lưu)"));
    s.content.append(actions,summary,el("p","text-secondary","Chuyến kết thúc khi công việc giao đã xử lý xong. Kiện chờ trả kho cuối ca được theo dõi riêng; tài xế có thể nhận chuyến mới khi xe còn tải."));
    const mapHost=el("div","dispatch-map"),timing=el("div","dispatch-trip-timing");s.content.append(mapHost,timing);
    let geometry=null;try{geometry=(await s.read("/api/v1/trips/"+id+"/route")).route;}catch(error){U.failure(s,s.feedback,error);}if(!s.alive())return;
    const savedStops=new Map((geometry?.stops||[]).map(stop=>[stop.orderId,stop]));
    timing.append(el("p","text-secondary","Thời gian dự kiến theo giờ Việt Nam."),UI.table(["Thứ tự","Vận đơn","Người nhận / địa chỉ","Khối lượng","Đến nơi (VN)","Bắt đầu giao (VN)","Chờ","Rời điểm (VN)","Trạng thái"],d.orders.map(o=>{const stop=savedStops.get(o.orderId);return [o.sequence,o.trackingNumber,o.receiverName+" · "+o.deliveryAddress,number(o.weightKg)+" kg",date(stop?.arrivalAt||o.plannedArrivalAt),date(stop?.serviceStartAt),waiting(stop),date(stop?.departureAt),UI.badge(o.orderStatus)];})));
    if(!geometry)s.content.insertBefore(el("p","dispatch-map-note","Chuyến chưa có hình học tuyến đường bộ. Bản đồ chỉ hiển thị các điểm có tọa độ."),mapHost);
    drawMap(s,mapHost,geometry?[geometry]:[{shipperName:d.shipperName||d.tripCode,stops:d.orders.map(o=>({...o,orderId:o.orderId,point:{latitude:o.latitude,longitude:o.longitude}})),legs:[]}],geometry?.depot);
  }
  function editTrip(s,trip){
    const d=U.dialog(s,"Sửa / phân công chuyến nháp");if(!d)return;
    const form=el("form","dispatch-dialog-form"),fields={},feedback=el("div");
    field(form,fields,"shipperId","Shipper / xe","",{items:[["","Chưa phân công"],...s.options.shippers.filter(n=>n.branchId===trip.branchId).map(n=>[n.id,n.name+" · "+(n.licensePlate||"Chưa có xe"),!!n.eligibilityReason])]});
    field(form,fields,"departure","Xuất phát dự kiến",trip.plannedStartAt?localValue(trip.plannedStartAt):localFuture(),{type:"datetime-local",required:true});
    const list=el("ol","dispatch-edit-orders"),ids=trip.orders.map(o=>o.orderId);
    function render(){list.replaceChildren(...ids.map((id,index)=>{const row=trip.orders.find(o=>o.orderId===id),item=el("li");item.append(el("span","",row.trackingNumber),disable(button("↑",()=>{[ids[index-1],ids[index]]=[ids[index],ids[index-1]];render();}),index===0,"Đã ở đầu"),disable(button("↓",()=>{[ids[index],ids[index+1]]=[ids[index+1],ids[index]];render();}),index===ids.length-1,"Đã ở cuối"),disable(button("Bỏ khỏi chuyến",()=>{ids.splice(index,1);render();}),ids.length===1,"Chuyến cần ít nhất một đơn"));return item;}));}render();
    form.append(el("p","text-secondary","Chỉ sửa chuyến nháp. Thứ tự thủ công chưa có khoảng cách đường bộ."),list);
    const save=button("Lưu chuyến",null,"btn btn-orange");save.type="submit";form.append(feedback,save);d.body.replaceChildren(form);
    form.addEventListener("submit",async event=>{event.preventDefault();if(save.disabled||d.writeUnknown||!form.reportValidity())return;save.disabled=true;d.busyState(true);const driver=s.options.shippers.find(n=>n.id===Number(fields.shipperId.control.value));try{window.WriteOutcome.assertCanSend(d,{path:"/api/v1/trips/"+trip.id,method:"PUT",payload:{orderIds:ids,plannedStartAt:new Date(fields.departure.control.value+"+07:00").toISOString(),shipperId:driver?.id||null,vehicleId:driver?.vehicleId||null}});await window.ApiClient.request("/api/v1/trips/"+trip.id,{method:"PUT",signal:d.signal,body:JSON.stringify({orderIds:ids,plannedStartAt:new Date(fields.departure.control.value+"+07:00").toISOString(),shipperId:driver?.id||null,vehicleId:driver?.vehicleId||null})});d.close();R.reload();}catch(error){d.busyState(false);if(window.WriteOutcome.lock(d,feedback,error,{path:"/api/v1/trips/"+trip.id,scope:form}))return;U.failure(s,feedback,error);save.disabled=false;}});
  }
  function localValue(value){const d=new Date(/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)?value:value+"Z");return new Date(d.getTime()+7*3600000).toISOString().slice(0,16);}
  function localFuture(){return localValue(new Date(Date.now()+30*60000).toISOString());}
  function steps(s,step){const nav=el("ol","dispatch-steps");for(const [n,label]of [[1,"Chọn đơn & kho"],[2,"Shipper & xuất phát"],[3,"Xem đề xuất"]]){const item=el("li",n===step?"is-current":""),b=button(n+". "+label,()=>wizard(s,n),"dispatch-step");b.disabled=n===3&&!s.proposal;if(n===step)b.setAttribute("aria-current","step");item.append(b);nav.append(item);}return nav;}
  function depotIssue(w){
    if(!w)return "Không tìm thấy kho trong phạm vi được phép.";
    if(!["latitude","longitude"].every(k=>Object.hasOwn(w,k)))return "API chưa trả đủ tọa độ kho.";
    if(w.latitude==null&&w.longitude==null)return "Kho đang chọn chưa có tọa độ xuất phát.";
    if(!Number.isFinite(w.latitude)||!Number.isFinite(w.longitude)||Math.abs(w.latitude)>90||Math.abs(w.longitude)>180||(w.latitude===0&&w.longitude===0))return "Tọa độ kho đang chọn thiếu hoặc không hợp lệ.";
    return "";
  }
  function capturePlanning(s){
    const form=s.content.querySelector('.dispatch-planning-form');if(!form)return;
    s.draft={...s.draft,shipperIds:[...form.querySelectorAll('[name=shipper]:checked:not(:disabled)')].map(n=>Number(n.value)),departure:form.elements.departure.value,serviceMinutes:Number(form.elements.serviceMinutes.value),returnToDepot:form.elements.returnToDepot.checked};persist(s);
  }
  async function loadDepot(s,warehouse,status,calculate){
    const controller=s.depotAbort=new AbortController(),sequence=++s.depotSequence;
    s.depot=null;status.textContent="Đang tải điểm xuất phát…";status.setAttribute('aria-busy','true');if(calculate)calculate.disabled=true;
    const current=()=>s.alive()&&!controller.signal.aborted&&sequence===s.depotSequence&&status.isConnected&&Number(s.draft.warehouseId)===warehouse.id;
    try{
      const detail=await s.read('/api/v1/warehouses/'+warehouse.id+'/depot',AbortSignal.any([s.abort.signal,controller.signal]));
      if(!current())return;
      if(detail?.id!==warehouse.id||detail.branchId!==warehouse.branchId)throw Error('Điểm xuất phát không khớp kho đang chọn.');
      const issue=depotIssue(detail);status.replaceChildren();
      if(issue){status.append(el('p','alert alert-warning',issue));return;}
      s.depot={warehouseId:detail.id,latitude:detail.latitude,longitude:detail.longitude};
      Object.assign(warehouse,detail);
      const disconnected=(detail.connectivity||[]).filter(n=>n.state==='DISCONNECTED');
      if(disconnected.length)status.append(el('p','alert alert-warning','Kho không nối được mạng đường cho '+disconnected.map(n=>n.profile==='motorcycle'?'xe máy':'xe tải').join(', ')+'.'));
      if((detail.connectivity||[]).some(n=>n.state==='UNAVAILABLE'))status.append(el('p','alert alert-warning','Chưa đọc được mạng đường để kiểm tra điểm xuất phát.'));
      if(calculate){calculate.disabled=!s.options.routing.available;s.updateCalculate?.();}
    }catch(error){if(!current()||error.name==='AbortError'||error.sessionExpired)return;status.replaceChildren(el('p','alert alert-danger','Không tải được điểm xuất phát. '+error.message));}
    finally{if(current())status.setAttribute('aria-busy','false');}
  }
  async function wizard(s,step){
    capturePlanning(s);s.depotAbort?.abort();s.depot=null;s.updateCalculate=null;freeMap(s);s.step=step;sync(s,{step});s.content.replaceChildren(steps(s,step));
    if(step===1){
      if(!s.query.warehouseId&&s.draft.warehouseId)sync(s,{warehouseId:s.draft.warehouseId});
      await queue(s,s.content);return;
    }
    if(step===2){
      if(!s.selected.size&&!s.query.tripId){U.notice(s.feedback,"Chọn ít nhất một đơn tại bước 1.","warning");await wizard(s,1);return;}
      const chosen=[...s.selected.values()],warehouseId=Number(s.draft.warehouseId||chosen[0]?.warehouseId),warehouse=s.options.warehouses.find(n=>n.id===warehouseId);
      if(!warehouse||chosen.some(n=>n.warehouseId!==warehouseId)){U.notice(s.feedback,"Các đơn phải nằm trong cùng kho xuất phát. Hãy chọn kho và kiểm tra lại lựa chọn.","warning");await wizard(s,1);return;}
      s.draft.warehouseId=warehouse.id;persist(s);
      const depotStatus=el('div','dispatch-depot-status');s.content.append(depotStatus);
      const form=el("form","dispatch-planning-form"),fields={},drivers=el("div","dispatch-drivers");form.append(el("h2","",warehouse.name+" · "+chosen.length+" đơn"));
      const selectedDrivers=new Set(s.draft.shipperIds||[]);
      for(const n of s.options.shippers.filter(n=>n.branchId===warehouse.branchId)){
        const label=el("label","dispatch-driver"),pick=el("input","form-check-input");pick.type="checkbox";pick.name="shipper";pick.value=n.id;pick.checked=selectedDrivers.has(n.id);pick.disabled=!!n.eligibilityReason||!n.vehicleId;
        const text=el("span");text.append(el("strong","",n.name),el("small","",(n.licensePlate||"Chưa có xe")+" · "+number(n.capacityKg)+" kg"));if(n.carriedReturnCount>0)text.append(el("small","","Còn "+n.carriedReturnCount+" kiện chờ trả kho · "+number(n.carriedReturnKg)+" kg; đã tính vào tải xe."));if(n.eligibilityReason)text.append(el("small","dispatch-excluded",n.eligibilityReason));label.append(pick,text);drivers.append(label);
      }
      form.append(el("p","text-secondary","Lập tuyến mới khi công việc giao của chuyến trước đã xong. Kiện hoàn chờ trả kho cuối ca không chặn chuyến mới, nhưng vẫn chiếm tải trọng và thể tích xe."),drivers);
      const availableDrivers=[...drivers.querySelectorAll('[name="shipper"]')].filter(n=>!n.disabled);
      if(!availableDrivers.length)form.append(el("p","alert alert-warning","Chưa có shipper/xe rảnh đủ điều kiện. Kiểm tra phân công đang mở hoặc bố trí shipper và xe khác."),link("Xem danh sách phân công",R.href("assignments",{},{branchId:warehouse.branchId})));
      const validDeparture=(!s.draft.departure||new Date(s.draft.departure+"+07:00")<=new Date())?localFuture():s.draft.departure;
      s.draft.departure=validDeparture;
      field(form,fields,"departure","Thời gian xuất phát (giờ Việt Nam)",validDeparture,{type:"datetime-local",required:true,min:localValue(new Date().toISOString())});
      const advanced=el("details","dispatch-advanced"),advancedFields={};advanced.append(el("summary","","Tùy chọn nâng cao"));field(advanced,advancedFields,"serviceMinutes","Phục vụ tại mỗi điểm (phút)",s.draft.serviceMinutes??5,{type:"number",min:0,max:60,required:true});const returnLabel=el("label","dispatch-check"),back=el("input","form-check-input");back.type="checkbox";back.name="returnToDepot";back.checked=s.draft.returnToDepot!==false;returnLabel.append(back,document.createTextNode("Quay về kho sau điểm giao cuối"));advanced.append(returnLabel);form.append(advanced);
      const calculate=button("Tính đề xuất",null,"btn btn-orange");calculate.type="submit";form.append(calculate);
      const readiness=el("p","text-secondary");readiness.setAttribute("aria-live","polite");form.append(readiness);
      s.updateCalculate=()=>{
        const count=form.querySelectorAll('[name="shipper"]:checked:not(:disabled)').length;
        const departure=new Date(fields.departure.control.value+"+07:00"),minutes=Number(advancedFields.serviceMinutes.control.value);
        const issue=!availableDrivers.length?"Chưa có shipper/xe rảnh đủ điều kiện.":!count?"Chọn ít nhất một shipper/xe để tính đề xuất.":count>15?"Mỗi phương án tối đa 15 shipper/xe.":s.query.tripId&&count!==1?"Chuyến nháp cần đúng một shipper/xe.":!Number.isFinite(departure.getTime())||departure<=new Date()?"Chọn thời gian xuất phát trong tương lai.":!Number.isInteger(minutes)||minutes<0||minutes>60?"Thời gian phục vụ phải là số nguyên từ 0 đến 60 phút.":!s.depot?"Chờ điểm xuất phát hợp lệ trước khi tính tuyến.":!s.options.routing.available?"Chưa có mạng đường để tính tuyến.":"";
        calculate.disabled=!!issue||!!s.calculating||!!s.writeUnknown;readiness.textContent=issue;
      };
      calculate.disabled=true;if(!s.options.routing.available)form.append(el("p","alert alert-warning",s.options.routing.message||"Chưa có mạng đường để tính tuyến."));
      form.addEventListener("submit",async event=>{event.preventDefault();if(calculate.disabled||!form.reportValidity())return;
        const depDate=new Date(fields.departure.control.value+"+07:00");
        if(depDate<=new Date()){U.notice(s.feedback,"Thời gian xuất phát phải trong tương lai. Đã tự động cập nhật lại thời gian mới, vui lòng bấm Tính đề xuất lại.","warning");fields.departure.control.value=localFuture();capturePlanning(s);return;}const ids=[...form.querySelectorAll('[name="shipper"]:checked:not(:disabled)')].map(n=>Number(n.value));if(!ids.length||ids.length>15){U.notice(s.feedback,"Chọn từ 1 đến 15 shipper/xe đủ điều kiện.","warning");return;}if(s.query.tripId&&ids.length!==1){U.notice(s.feedback,"Chuyến nháp hiện có cần đúng một shipper/xe.","warning");return;}
        capturePlanning(s);await calculatePlan(s,calculate);});
      form.addEventListener("input",()=>{capturePlanning(s);s.updateCalculate?.();});form.addEventListener("change",()=>{capturePlanning(s);s.updateCalculate?.();});
      s.content.append(form,howItWorks());capturePlanning(s);s.updateCalculate();void loadDepot(s,warehouse,depotStatus,calculate);return;
    }
    if(!s.proposal){await wizard(s,2);return;}result(s);
  }
  function howItWorks(){const detail=el("details","dispatch-how");detail.append(el("summary","","Cách tính"),el("p","","Dijkstra tìm đường ngắn nhất trên snapshot OpenStreetMap có hướng theo loại xe. Phương án nhiều xe dùng cheapest insertion, sau đó cải thiện 2-opt và chuyển đơn giữa tuyến; không bảo đảm tối ưu toàn cục. Tải trọng lấy từ xe đã lưu, khu vực từ phân công thực tế. Đến trước giờ khách yêu cầu thì chờ; bắt đầu giao không muộn hơn hạn giao, sau đó cộng thời gian phục vụ. Tổng phút gồm di chuyển, chờ, phục vụ và quay về kho nếu chọn. Giờ trống không được tự bổ sung. Các đoạn tiếp cận địa chỉ tới nút đường không được tính vào km/phút."));return detail;}
  function requestFor(s){return {warehouseId:Number(s.draft.warehouseId),orderIds:[...s.selected.keys()],shipperIds:[...(s.draft.shipperIds||[])],departureAt:new Date(s.draft.departure+"+07:00").toISOString(),serviceMinutes:Number(s.draft.serviceMinutes??5),returnToDepot:s.draft.returnToDepot!==false,...(s.query.tripId?{existingTripId:Number(s.query.tripId)}:{})};}
  async function calculatePlan(s,control,manual=false){
    if(s.calculating||s.writeUnknown)return;capturePlanning(s);checkInputs(s);invalidateProposal(s);persist(s);s.calculating=true;control.disabled=true;const caption=control.textContent;control.textContent="Đang tính…";s.content.setAttribute("aria-busy","true");U.notice(s.feedback,"");
    const key=planningKey(s),revision=s.planningRevision,edits=JSON.stringify(s.edits);
    try{const request=requestFor(s);if(manual)request.manualRoutes=s.edits;
      const proposal=s.query.tripId&&!manual?await write(s,"/api/v1/trips/"+s.query.tripId+"/optimize",{shipperIds:request.shipperIds,departureAt:request.departureAt,serviceMinutesPerStop:request.serviceMinutes,returnToBranch:request.returnToDepot},s.abort.signal,planningTimeoutMs):await write(s,"/api/v1/dispatch/plans",request,s.abort.signal,planningTimeoutMs);
      if(!s.alive())return;capturePlanning(s);checkInputs(s);
      if(!key||key!==planningKey(s)||revision!==s.planningRevision||edits!==JSON.stringify(s.edits)){U.notice(s.feedback,changedInputsMessage,"warning");return;}
      s.proposal=proposal;s.proposalBinding={id:proposal.id,key};s.edits=null;s.dirty=false;s.confirmed=false;s.calculating=false;persist(s);sync(s,{planId:proposal.id,step:3});await wizard(s,3);
    }catch(error){if(!window.WriteOutcome.lock(s,s.feedback,error,{path:s.query.tripId?"/api/v1/trips/"+s.query.tripId+"/optimize":"/api/v1/dispatch/plans",payload:{orderIds:[...s.selected.keys()]},scope:s.content,signal:s.abort.signal}))U.failure(s,s.feedback,error);}finally{s.calculating=false;control.disabled=!!s.writeUnknown;control.textContent=caption;s.content.setAttribute("aria-busy","false");s.updateCalculate?.();}
  }
  function result(s){
    checkInputs(s);const current=proposalIsCurrent(s);
    const p=s.proposal;s.routeIndex=Math.min(s.routeIndex||0,Math.max(p.routes.length-1,0));
    const legacyTiming=p.routes.some(route=>route.stops.some(stop=>!stop.serviceStartAt||!Number.isFinite(stop.waitingMinutes)));
    const actions=el("div","dispatch-actions"),retry=button(s.edits?"Kiểm tra lại phương án điều chỉnh":"Tính lại",()=>calculatePlan(s,retry,!!s.edits),"btn btn-outline-orange"),confirm=button("Xác nhận tạo chuyến",()=>confirmPlan(s,confirm),"btn btn-orange");s.confirmButton=confirm;
    confirm.disabled=s.writeUnknown||!current||s.calculating||s.confirming||s.dirty||legacyTiming||!p.routes.length||!s.can("DIEUPHOI_PHANCONG")||Date.parse(p.expiresAt)<Date.now()||!!s.confirmed;
    if(!s.can("DIEUPHOI_PHANCONG"))confirm.title="Cần quyền phân công để xác nhận.";actions.append(button("Đổi shipper / thời gian",()=>wizard(s,2)),retry,confirm);
    s.content.append(el("p","dispatch-result-summary",p.warehouseName+" · "+p.routes.length+" tuyến · "+(s.dirty?"Chưa kiểm tra lại":number(p.routes.reduce((sum,r)=>sum+r.distanceKm,0))+" km · "+date(p.departureAt))),actions);
    if(!current&&!s.confirmed)U.notice(s.feedback,changedInputsMessage,"warning");
    if(s.dirty)s.content.append(el("p","alert alert-warning","Phương án đã chỉnh, chưa kiểm tra ràng buộc. Bản đồ và tổng trước đó chỉ để tham khảo; cần tính lại trước khi xác nhận."));
    if(legacyTiming)s.content.append(el("p","alert alert-warning","Phương án cũ chưa có giờ bắt đầu giao và thời gian chờ. Hãy tính lại trước khi xác nhận."));
    if(!p.routes.length)s.content.append(el("p","alert alert-warning","Chưa tìm được tuyến khả thi với dữ liệu và lựa chọn hiện tại. Xem lý do của từng đơn bên dưới."));
    if(p.timeLimitReached)s.content.append(el("p","alert alert-warning","Đã đạt giới hạn thời gian cải thiện; đang giữ phương án khả thi tìm được."));
    if(p.routes.length){
      const layout=el("div","dispatch-result-layout"),list=el("div","dispatch-route-list"),mapHost=el("div","dispatch-map");
      p.routes.forEach((route,index)=>{const chosen=button("",()=>{s.routeIndex=index;resultRefresh(s);},"dispatch-route"+(s.routeIndex===index?" is-selected":""));chosen.replaceChildren();chosen.setAttribute("aria-pressed",String(s.routeIndex===index));const token=el("span","dispatch-route-letter",letters[index]);token.style.background=colors[index%colors.length];chosen.append(token,el("strong","",route.shipperName),el("small","",route.licensePlate+" · "+route.stops.length+" đơn"),el("small","",s.dirty?"Chưa kiểm tra lại":number(route.weightKg)+" / "+number(route.capacityKg)+" kg · "+number(route.distanceKm)+" km · "+number(route.durationMinutes)+" phút"));list.append(chosen);});
      layout.append(list,mapHost);s.content.append(layout);drawMap(s,mapHost,p.routes,p.depot,s.routeIndex);
      const route=p.routes[s.routeIndex],orders=new Map([...p.routes.flatMap(r=>r.stops),...p.unplanned].map(o=>[o.orderId,o]));
      const edit=s.edits?.find(r=>r.shipperId===route.shipperId),ids=edit?.orderIds||route.stops.map(o=>o.orderId);
      const table=UI.table(["Thứ tự","Vận đơn / người nhận","Đến nơi (VN)","Bắt đầu giao (VN)","Chờ","Rời điểm (VN)","Điều chỉnh"],ids.map((id,index)=>{
        const stop=orders.get(id),tools=el("div","dispatch-actions");
        const up=button("↑",()=>editRoute(s,route.shipperId,id,-1));up.setAttribute("aria-label","Đưa "+stop.trackingNumber+" lên trước");disable(up,index===0,"Đã ở đầu tuyến");const down=button("↓",()=>editRoute(s,route.shipperId,id,1));down.setAttribute("aria-label","Đưa "+stop.trackingNumber+" xuống sau");disable(down,index===ids.length-1,"Đã ở cuối tuyến");tools.append(up,down);
        if(p.routes.length>1){const move=U.select([["","Chuyển sang tuyến…"],...p.routes.filter(r=>r.shipperId!==route.shipperId).map(r=>[r.shipperId,r.shipperName])],"");move.setAttribute("aria-label","Chuyển "+stop.trackingNumber+" sang tuyến");move.addEventListener("change",()=>editRoute(s,route.shipperId,id,0,Number(move.value)));tools.append(move);}
        return [index+1,stop.trackingNumber+" · "+(stop.receiverName||s.selected.get(id)?.receiverName||""),s.dirty?"Chưa tính lại":date(stop.arrivalAt),s.dirty?"Chưa tính lại":date(stop.serviceStartAt),s.dirty?"Chưa tính lại":waiting(stop),s.dirty?"Chưa tính lại":date(stop.departureAt),tools];
      }));s.content.append(el("h2","",routeName(route,s.routeIndex)),el("p","text-secondary",route.capacityM3==null?"Chưa có giới hạn thể tích xe; chưa kết luận đủ sức chứa m³.":(s.dirty?"Thể tích cần kiểm tra lại":number(route.volumeM3)+" / "+number(route.capacityM3)+" m³")),table);
    }
    const unplanned=el("section","dispatch-unplanned");unplanned.append(el("h2","","Đơn chưa xếp được · "+p.unplanned.length));for(const order of p.unplanned)unplanned.append(el("p","",order.trackingNumber+": "+order.reason));if(!p.unplanned.length)unplanned.append(el("p","text-secondary","Tất cả đơn đã được xếp vào tuyến đề xuất."));s.content.append(unplanned);
    const warnings=el("details","dispatch-how");warnings.append(el("summary","","Dữ liệu và giả định đã dùng"),...p.warnings.map(text=>el("p","",text)));s.content.append(warnings,howItWorks());
  }
  function resultRefresh(s){freeMap(s);s.content.replaceChildren(steps(s,3));result(s);}
  function editRoute(s,shipper,id,direction,target){
    if(!s.edits)s.edits=s.proposal.routes.map(r=>({shipperId:r.shipperId,orderIds:r.stops.map(o=>o.orderId)}));const source=s.edits.find(r=>r.shipperId===shipper),index=source.orderIds.indexOf(id);
    if(target){source.orderIds.splice(index,1);s.edits.find(r=>r.shipperId===target).orderIds.push(id);}else{const next=index+direction;if(next<0||next>=source.orderIds.length)return;[source.orderIds[index],source.orderIds[next]]=[source.orderIds[next],source.orderIds[index]];}
    invalidateProposal(s);s.dirty=true;s.guard();persist(s);resultRefresh(s);
  }
  async function confirmPlan(s,control){
    if(s.writeUnknown)return;
    capturePlanning(s);checkInputs(s);
    if(!proposalIsCurrent(s)){control.disabled=true;U.notice(s.feedback,changedInputsMessage,"warning");return;}
    if(control.disabled||s.writeUnknown||s.dirty||s.confirming||s.calculating||s.confirmed)return;s.confirming=true;control.disabled=true;control.textContent="Đang xác nhận…";
    try{window.WriteOutcome.assertCanSend(s,{path:"/api/v1/dispatch/plans/"+s.proposal.id+"/confirm",payload:{}});const result=await write(s,"/api/v1/dispatch/plans/"+s.proposal.id+"/confirm",{},s.abort.signal,planningTimeoutMs);if(!s.alive())return;s.confirmed=true;s.dirty=false;s.selected.clear();persist(s);U.notice(s.feedback,result.message,"success");const links=el("div","dispatch-actions");for(const trip of result.trips)links.append(link("Mở "+trip.tripCode,R.href("delivery-trips",{},{tripId:trip.id})));s.feedback.append(links);control.textContent="Đã xác nhận";}
    catch(error){const unknown=window.WriteOutcome.lock(s,s.feedback,error,{path:"/api/v1/dispatch/plans/"+s.proposal.id+"/confirm",scope:s.content,signal:s.abort.signal});if(!unknown)U.failure(s,s.feedback,error);control.textContent="Xác nhận tạo chuyến";control.disabled=unknown||!proposalIsCurrent(s)||error.status===409;}
    finally{s.confirming=false;}
  }
  function drawMap(s,host,routes,depot,selected){
    freeMap(s);s.mapFrame=requestAnimationFrame(()=>{
      if(!s.alive()||!host.isConnected)return;const valid=p=>p&&Number.isFinite(p.latitude)&&Number.isFinite(p.longitude)&&Math.abs(p.latitude)<=90&&Math.abs(p.longitude)<=180;
      const points=routes.flatMap(r=>[...r.stops.map(o=>o.point),...(r.legs||[]).flatMap(l=>l.geometry||[])]).filter(valid);if(valid(depot))points.push(depot);
      if(!points.length||!window.L){host.replaceChildren(el("p","dispatch-empty",!points.length?"Chưa có tọa độ hợp lệ để hiển thị bản đồ.":"Chưa tải được thư viện bản đồ."));return;}
      const map=s.map=window.L.map(host,{scrollWheelZoom:false,preferCanvas:true});const status=el("p","dispatch-map-status");host.after(status);s.mapStatus=status;
      const googleRoadmap=window.L.tileLayer("https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&hl=vi",{maxZoom:20,maxNativeZoom:19,keepBuffer:6,updateWhenIdle:false,subdomains:["0","1","2","3"],attribution:'&copy; <a href="https://maps.google.com" target="_blank">Google Maps</a>'});
      const googleSatellite=window.L.tileLayer("https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}&hl=vi",{maxZoom:20,maxNativeZoom:19,keepBuffer:6,updateWhenIdle:false,subdomains:["0","1","2","3"],attribution:'&copy; <a href="https://maps.google.com" target="_blank">Google Maps</a>'});
      const osm=window.L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:19,attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'});
      googleRoadmap.on("tileerror",()=>{status.textContent="Chưa tải được nền bản đồ. Các điểm và hình học tuyến được giữ.";}).on("tileload",()=>{status.textContent="";}).addTo(map);
      window.L.control.layers({"Google Bản đồ":googleRoadmap,"Google Vệ tinh":googleSatellite,"OpenStreetMap":osm},null,{position:"topright"}).addTo(map);
      map.fitBounds(points.map(p=>[p.latitude,p.longitude]),{padding:[40,40],maxZoom:16});
      routes.forEach((route,index)=>{
        const color=colors[index%colors.length],opacity=selected==null||selected===index?1:.45;
        for(const leg of route.legs||[])if(leg.geometry?.length>1)window.L.polyline(leg.geometry.map(p=>[p.latitude,p.longitude]),{color,opacity,weight:selected===index?6:4,lineJoin:"round",dashArray:index%2?"9 5":null}).addTo(map);
        for(const [i,stop]of route.stops.entries())if(valid(stop.point)){
          const coincident=routes.flatMap(r=>r.stops).filter(o=>valid(o.point)&&o.point.latitude===stop.point.latitude&&o.point.longitude===stop.point.longitude),offset=(coincident.indexOf(stop)-(coincident.length-1)/2)*44;
          const token=el("span","dispatch-map-number",letters[index]+(stop.sequence||i+1));token.style.background=color;const popup=el("div","dispatch-popup");popup.append(el("strong","",routeName(route,index)+" · Điểm "+(stop.sequence||i+1)),el("p","",stop.trackingNumber),el("p","",stop.receiverName),el("p","",stop.address||stop.deliveryAddress));if(stop.arrivalAt)popup.append(el("p","","Đến nơi (giờ VN): "+date(stop.arrivalAt)));if(stop.serviceStartAt)popup.append(el("p","","Bắt đầu giao (giờ VN): "+date(stop.serviceStartAt)),el("p","","Chờ: "+waiting(stop)));if(stop.departureAt)popup.append(el("p","","Rời điểm (giờ VN): "+date(stop.departureAt)));
          if(stop.snapDistanceMeters!=null)popup.append(el("small","","Cách nút đường: "+number(stop.snapDistanceMeters)+"m; đoạn tiếp cận chưa tính vào tuyến."));if(coincident.length>1)popup.append(el("small","","Có "+coincident.length+" điểm cùng tọa độ; biểu tượng được dàn cạnh nhau."));
          const marker=window.L.marker([stop.point.latitude,stop.point.longitude],{icon:window.L.divIcon({className:"dispatch-map-marker",html:token,iconSize:[40,36],iconAnchor:[20-offset,36],popupAnchor:[offset,-36]}),title:routeName(route,index)+" · Điểm "+(stop.sequence||i+1)}).bindPopup(popup,{maxHeight:180}).addTo(map);const markerElement=marker.getElement();markerElement.setAttribute("aria-label",marker.options.title);markerElement.onkeydown=event=>{if(event.key===" "){event.preventDefault();marker.openPopup();}};
        }
      });
      if(valid(depot)){const token=el("i","bi bi-box-seam dispatch-depot-symbol");window.L.marker([depot.latitude,depot.longitude],{title:"Kho xuất phát",icon:window.L.divIcon({className:"dispatch-depot-marker",html:token,iconSize:[36,36]})}).bindPopup(el("strong","","Kho xuất phát")).addTo(map);}
      if(selected!=null){const route=routes[selected],coords=[...route.stops.map(o=>o.point),...(route.legs||[]).flatMap(l=>l.geometry||[])].filter(valid).map(p=>[p.latitude,p.longitude]);if(valid(depot))coords.push([depot.latitude,depot.longitude]);if(coords.length)map.fitBounds(coords,{padding:[44,44],maxZoom:16});}
      s.mapObserver=new ResizeObserver(()=>{if(s.alive()&&map===s.map){const size=map.getSize();if(size.x!==host.clientWidth||size.y!==host.clientHeight)map.invalidateSize({animate:false});}});s.mapObserver.observe(host);
    });
  }
  async function mount(container,user,route,context){
    destroy();const s=active=U.state(container,user,route,context),base=s.destroy;s.root.className="dispatch-page";s.page=route.pageId;s.query={...route.query};s.selected=new Map();s.draft=readDraft();s.depotSequence=0;if(s.query.warehouseId)s.draft.warehouseId=Number(s.query.warehouseId);s.destroy=()=>{s.depotAbort?.abort();s.listAbort?.abort();s.filterAbort?.abort();freeMap(s);base();};
    s.feedback=el("div","dispatch-feedback");s.feedback.setAttribute("aria-live","polite");s.content=el("div","dispatch-content");s.root.append(s.feedback,s.content);s.content.append(el("p","dispatch-empty","Đang tải dữ liệu điều phối…"));
    try{
      s.options=await s.read("/api/v1/dispatch/options");if(!s.alive())return;
      if(s.page==="dispatch-queue"||s.page==="route-optimization")await hydrate(s);if(!s.alive())return;s.content.replaceChildren();if(s.selectionNotice)U.notice(s.feedback,s.selectionNotice,"warning");
      if(s.page==="route-optimization"){
        if(s.query.planId){const p=await s.read("/api/v1/dispatch/plans/"+s.query.planId);if(!s.alive())return;restoreProposal(s,p);}
        else if(s.query.tripId){const trip=await s.read("/api/v1/trips?id="+s.query.tripId);if(!s.alive())return;if(trip.status!=="PLANNED")throw Error("Chỉ lập đề xuất lại cho chuyến nháp chưa phân công.");s.selected=new Map(trip.orders.map(o=>[o.orderId,{...o,id:o.orderId,warehouseId:trip.warehouseId}]));s.draft.warehouseId=trip.warehouseId;s.draft.departure=trip.plannedStartAt?localValue(trip.plannedStartAt):localFuture();}
        await wizard(s,Number(s.query.step)||(s.proposal?3:1));
      }else if(s.page==="dispatch-queue")await queue(s,s.content);else if(s.page==="assignments")await assignments(s);else await trips(s);
    }catch(error){U.failure(s,s.feedback,error);s.content.replaceChildren(el("p","dispatch-empty","Chưa mở được dữ liệu. Kiểm tra thông báo phía trên."),button("Thử lại",()=>R.reload(),"btn btn-outline-orange"));}
  }
  window.DispatchPage=Object.freeze({mount,destroy});
}());

"use strict";
(function(){
  const statuses={OPEN:"Chờ xử lý",NEED_MORE:"Cần tài xế bổ sung",RESOLVED:"Đã xử lý"};
  const kinds={MISSING:"Thiếu/chưa tìm thấy kiện",WRONG_LABEL:"Sai nhãn/mã kiện",DAMAGED:"Kiện hư hại",WAREHOUSE_UNAVAILABLE:"Không thể nhận tại kho",OTHER:"Sự cố khác"};
  const events={REPORT:"Tài xế báo sự cố",SUPPLEMENT:"Tài xế bổ sung",REQUEST_INFO:"Yêu cầu bổ sung",RESOLVE:"Hướng xử lý"};
  const id=v=>Number.isSafeInteger(v)&&v>0;
  const guid=v=>typeof v==="string"&&/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(v);
  function validate(data,orderId){
    if(!id(orderId)||data?.orderId!==orderId||typeof data.available!=="boolean"||typeof data.pickupBlocked!=="boolean"||!Array.isArray(data.items))throw Error("Danh sách hồ sơ sự cố không hợp lệ.");
    const ids=new Set();
    for(const r of data.items){
      if(!id(r.id)||ids.has(r.id)||r.orderId!==orderId||!id(r.assignmentId)||!id(r.shipperId)||!id(r.warehouseId)||!id(r.revision)||
        !Object.hasOwn(statuses,r.status)||r.canReview&&r.status==="RESOLVED"||!Object.hasOwn(kinds,r.kind)||typeof r.canReview!=="boolean"||typeof r.warehouseName!=="string"||typeof r.shipperName!=="string"||
        typeof r.reportedAt!=="string"||!Number.isFinite(Date.parse(r.reportedAt))||!Array.isArray(r.events)||r.events.length!==r.revision||
        (r.status==="RESOLVED")!==(r.closedAt!=null)||r.closedAt!=null&&!Number.isFinite(Date.parse(r.closedAt)))throw Error("Hồ sơ sự cố thiếu hoặc sai dữ liệu.");
      const eventIds=new Set(),requests=new Set();
      r.events.forEach((e,n)=>{
        if(!id(e.id)||eventIds.has(e.id)||!guid(e.requestId)||requests.has(e.requestId)||e.revision!==n+1||!Object.hasOwn(events,e.eventType)||!Object.hasOwn(statuses,e.status)||
          typeof e.notes!=="string"||typeof e.authorName!=="string"||!id(e.authorAccountId)||typeof e.hasEvidence!=="boolean"||typeof e.recordedAt!=="string"||!Number.isFinite(Date.parse(e.recordedAt)))throw Error("Lịch sử hồ sơ sự cố không hợp lệ.");
        eventIds.add(e.id);requests.add(e.requestId);
      });
      if(r.events[0]?.eventType!=="REPORT"||r.events.at(-1)?.status!==r.status)throw Error("Trạng thái hồ sơ không khớp lịch sử.");
      ids.add(r.id);
    }
    if(!data.available&&data.items.length||data.items.some(r=>r.status!=="RESOLVED")&&!data.pickupBlocked)throw Error("Trạng thái chặn nhận kiện không hợp lệ.");
    return data;
  }
  function requestKey(){
    const bytes=crypto.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
    const hex=Array.from(bytes,b=>b.toString(16).padStart(2,"0")).join("");
    return hex.slice(0,8)+"-"+hex.slice(8,12)+"-"+hex.slice(12,16)+"-"+hex.slice(16,20)+"-"+hex.slice(20);
  }
  async function show(owner,orderId){
    const U=window.LogisticsUI,d=U.dialog(owner,"Sự cố nhận kiện / Xử lý",true),urls=new Set();
    let pending=null,busy=false,readGeneration=0;const drafts=new Map();
    function release(){for(const url of urls)URL.revokeObjectURL(url);urls.clear();}
    d.onClose(release);d.signal.addEventListener("abort",release,{once:true});
    const message=U.el("p","text-secondary"),content=U.el("div"),toolbar=U.el("div","order-actions");
    const refresh=U.button("Kiểm tra / làm mới",()=>load());toolbar.append(refresh);d.body.append(toolbar,message,content);
    function found(data,key){return data.items.some(i=>i.events.some(e=>e.requestId.toLowerCase()===key.toLowerCase()));}
    function ack(data,issue,payload){
      if(!data||data.issueId!==issue.id||data.orderId!==orderId||data.assignmentId!==issue.assignmentId||data.requestId!==payload.requestId||
        data.eventType!==payload.action||typeof data.alreadyRecorded!=="boolean"||data.revision!==issue.revision+1||data.reason!==payload.reason||
        data.status!==(payload.action==="RESOLVE"?"RESOLVED":"NEED_MORE")||data.hasEvidence!==false||typeof data.recordedAt!=="string"||!Number.isFinite(Date.parse(data.recordedAt)))throw Object.assign(Error("Chưa đọc được biên nhận xử lý hợp lệ."),{resultUnknown:true});
    }
    async function submit(issue,payload){
      if(busy||d.signal.aborted)return;busy=true;d.setBusy(true);refresh.disabled=true;
      pending={issue,payload};message.textContent="Đang gửi hướng xử lý…";
      try{
        const result=await window.ApiClient.request("/api/v1/orders/"+orderId+"/pickup-issues/"+issue.id+"/response",{method:"POST",body:payload,signal:d.signal});
        if(d.signal.aborted)return;ack(result,issue,payload);drafts.delete(issue.id);pending=null;message.textContent="Máy chủ đã ghi nhận hướng xử lý.";
      }catch(error){
        if(d.signal.aborted)return;
        const uncertain=error.resultUnknown||!error.status||error.status>=500&&error.status!==503;
        if(!uncertain)pending=null;
        message.textContent=uncertain?"Chưa xác định kết quả. Kiểm tra biên nhận trước khi gửi lại.":error.message;
      }finally{
        busy=false;if(!d.signal.aborted){d.setBusy(false);refresh.disabled=false;await load();}
      }
    }
    async function photo(issue,event,host,errorBox,button){
      const generation=readGeneration;
      button.disabled=true;errorBox.textContent="";
      try{
        const blob=await window.ApiClient.request("/api/v1/orders/"+orderId+"/pickup-issues/"+issue.id+"/events/"+event.id+"/image",{signal:d.signal,responseType:"blob"});
        if(d.signal.aborted||generation!==readGeneration)return;
        if(!["image/jpeg","image/png"].includes(blob.type)||blob.size===0||blob.size>5*1024*1024)throw Error("Ảnh sự cố không hợp lệ.");
        for(const image of host.querySelectorAll("img")){URL.revokeObjectURL(image.src);urls.delete(image.src);}
        const url=URL.createObjectURL(blob);urls.add(url);const image=U.el("img");image.src=url;image.alt="Ảnh minh chứng sự cố nhận kiện";image.style.maxWidth="100%";image.style.maxHeight="480px";host.replaceChildren(image);
      }catch(error){if(!d.signal.aborted)errorBox.textContent=error.message;}
      finally{if(!d.signal.aborted)button.disabled=false;}
    }
    function render(data){
      release();content.replaceChildren();
      content.append(U.el("p","text-secondary",data.pickupBlocked?"Đang chặn nhận/xuất kiện do còn hồ sơ mở. Chỉ xử lý sau khi đã kiểm tra thực tế.":"Không có hồ sơ nhận kiện đang mở. Đóng hồ sơ không tự xuất kho hoặc xác nhận tài xế đã nhận kiện."));
      if(!data.available){content.append(U.el("p","text-danger","Chưa áp dụng SQL hồ sơ sự cố nhận kiện."));return;}
      if(pending){
        content.append(U.el("p","text-danger","Chưa có biên nhận cho yêu cầu vừa gửi. Giữ nguyên nội dung và mã yêu cầu khi gửi lại."),
          U.button("Gửi lại đúng yêu cầu này",()=>submit(pending.issue,pending.payload)));
      }
      if(!data.items.length)content.append(U.el("p","text-secondary","Chưa có hồ sơ sự cố nhận kiện. Báo cáo cũ chỉ ghi nhật ký quản trị vẫn tra trong nhật ký."));
      for(const issue of data.items){
        const card=U.el("section","order-section");
        card.append(U.el("h3","h6","#"+issue.id+" · "+kinds[issue.kind]+" · "+statuses[issue.status]),
          U.el("p","","Tài xế: "+issue.shipperName+" · Phân công #"+issue.assignmentId+" · Kho: "+issue.warehouseName));
        for(const event of issue.events){
          card.append(U.el("p","fw-semibold",events[event.eventType]+" · "+event.authorName+" · "+U.date(event.recordedAt)),U.el("p","",event.notes));
          if(event.hasEvidence){const host=U.el("div"),errorBox=U.el("p","text-danger"),view=U.button("Xem ảnh minh chứng",()=>photo(issue,event,host,errorBox,view));card.append(view,errorBox,host);}
        }
        if(issue.canReview&&!pending){
          const form=U.el("form"),label=U.el("label","form-label","Hướng xử lý"),action=U.el("select","form-select"),notes=U.el("textarea","form-control"),errorBox=U.el("p","text-danger");
          for(const [value,text]of [["REQUEST_INFO","Yêu cầu tài xế bổ sung"],["RESOLVE","Đã kiểm tra và đóng hồ sơ"]]){const option=U.el("option","",text);option.value=value;action.append(option);}
          const draft=drafts.get(issue.id);action.value=draft?.action||"REQUEST_INFO";notes.value=draft?.reason||"";
          notes.rows=3;notes.maxLength=500;notes.minLength=3;notes.required=true;notes.placeholder="Ghi rõ thông tin cần bổ sung hoặc kết quả kiểm tra và hướng dẫn tài xế.";
          const save=U.button("Gửi hướng xử lý",()=>{});save.type="submit";save.disabled=notes.value.trim().length<3;
          notes.addEventListener("input",()=>{save.disabled=busy||notes.value.trim().length<3;drafts.set(issue.id,{action:action.value,reason:notes.value});});
          action.addEventListener("change",()=>drafts.set(issue.id,{action:action.value,reason:notes.value}));
          form.append(label,action,notes,errorBox,save);
          form.addEventListener("submit",event=>{event.preventDefault();if(busy||notes.value.trim().length<3)return;save.disabled=true;action.disabled=true;notes.disabled=true;
            return submit(issue,{requestId:requestKey(),action:action.value,expectedRevision:issue.revision,reason:notes.value.trim()});});
          card.append(form);
        }
        content.append(card);
      }
    }
    async function load(){
      if(busy||d.signal.aborted)return;++readGeneration;busy=true;refresh.disabled=true;
      try{
        const data=validate(await window.ApiClient.request("/api/v1/orders/"+orderId+"/pickup-issues",{signal:d.signal}),orderId);
        if(d.signal.aborted)return;
        if(pending&&found(data,pending.payload.requestId)){drafts.delete(pending.issue.id);pending=null;message.textContent="Đã tìm thấy biên nhận, hướng xử lý đã được lưu.";}
        render(data);
      }catch(error){if(!d.signal.aborted){release();content.replaceChildren(U.el("p","text-danger","Không tải được hồ sơ: "+error.message));}}
      finally{busy=false;if(!d.signal.aborted)refresh.disabled=false;}
    }
    await load();
  }
  window.PickupIssues=Object.freeze({show,validate});
})();

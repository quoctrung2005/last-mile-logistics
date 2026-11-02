"use strict";
(function(){
  const labels={NORMAL:"Nguyên vẹn",PREEXISTING_DAMAGE:"Có hư hại được ghi nhận trước khi nhận"};
  function validate(data,orderId){
    if(!Array.isArray(data?.items))throw Error("Danh sách biên nhận nhận kiện không hợp lệ.");
    if(!Number.isSafeInteger(orderId)||orderId<=0)throw Error("Mã đơn không hợp lệ.");
    const ids=new Set();
    for(const r of data.items){
      if(r.orderId!==orderId||!Number.isSafeInteger(r.assignmentId)||r.assignmentId<=0||ids.has(r.assignmentId)||
        !Number.isSafeInteger(r.handoverId)||r.handoverId<=0||!Number.isSafeInteger(r.shipperId)||r.shipperId<=0||
        typeof r.hasEvidence!=="boolean"||typeof r.receivedAt!=="string"||!Number.isFinite(Date.parse(r.receivedAt))||
        !Number.isSafeInteger(r.warehouseId)||r.warehouseId<=0||typeof r.warehouseName!=="string"||
        typeof r.confirmedCode!=="string"||!r.confirmedCode.trim()||r.notes!=null&&typeof r.notes!=="string"||
        r.parcelCondition!=null&&!Object.hasOwn(labels,r.parcelCondition)||
        r.parcelCondition==="PREEXISTING_DAMAGE"&&(!r.hasEvidence||!r.notes?.trim())||
        r.accuracyMeters!=null&&(!Number.isFinite(r.accuracyMeters)||r.accuracyMeters<0||r.accuracyMeters>100||r.latitude==null)||
        (r.latitude==null)!==(r.longitude==null)||r.latitude!=null&&(!Number.isFinite(r.latitude)||Math.abs(r.latitude)>90||!Number.isFinite(r.longitude)||Math.abs(r.longitude)>180))throw Error("Biên nhận nhận kiện thiếu hoặc sai dữ liệu.");
      ids.add(r.assignmentId);
    }
    return data.items;
  }
  async function show(owner,orderId){
    const {el,button,dialog,date}=window.LogisticsUI;
    const d=dialog(owner,"Biên nhận tài xế nhận kiện",true),urls=new Set();
    const release=()=>{for(const url of urls)URL.revokeObjectURL(url);urls.clear();};
    d.onClose(release);d.signal.addEventListener("abort",release,{once:true});
    d.body.append(el("p","text-secondary","Đang tải biên nhận…"));
    try{
      const rows=validate(await window.ApiClient.request("/api/v1/orders/"+orderId+"/pickup-receipts",{signal:d.signal}),orderId);
      if(d.signal.aborted)return;d.body.replaceChildren();
      if(!rows.length){d.body.append(el("p","text-secondary","Chưa có dữ liệu tình trạng/GPS/ảnh nhận kiện. Phiếu cũ vẫn tra thời gian nhận trong lịch sử kho."));return;}
      for(const r of rows){
        const card=el("section","order-section"),photoHost=el("div");let currentPhoto;
        card.append(el("h3","h6","Phân công #"+r.assignmentId+" · Tài xế #"+r.shipperId),
          el("p","","Kho: "+r.warehouseName+" · Nhận lúc "+date(r.receivedAt)),
          el("p","","Mã nhãn đã đối chiếu: "+r.confirmedCode),
          el("p","","Tình trạng: "+(labels[r.parcelCondition]||"Chưa ghi nhận (phiếu cũ)")),
          el("p","","Ghi chú: "+(r.notes||"Không có")),
          el("p","",r.latitude==null?"Chưa ghi vị trí GPS lúc nhận":"GPS: "+r.latitude.toFixed(6)+", "+r.longitude.toFixed(6)+(r.accuracyMeters==null?"":" · Độ chính xác "+r.accuracyMeters+" m")));
        if(r.hasEvidence){
          const errorBox=el("p","text-danger"),view=button("Xem ảnh lúc nhận",async()=>{
            view.disabled=true;errorBox.textContent="";
            try{
              const blob=await window.ApiClient.request("/api/v1/orders/"+orderId+"/pickup-receipts/"+r.assignmentId+"/image",{signal:d.signal,responseType:"blob"});
              if(d.signal.aborted)return;
              if(!["image/jpeg","image/png"].includes(blob.type)||blob.size===0||blob.size>5*1024*1024)throw Error("Ảnh nhận kiện không hợp lệ.");
              if(currentPhoto){URL.revokeObjectURL(currentPhoto);urls.delete(currentPhoto);}
              const url=URL.createObjectURL(blob);currentPhoto=url;urls.add(url);const image=el("img");image.src=url;image.alt="Ảnh kiện tại lúc tài xế nhận";image.style.maxWidth="100%";image.style.maxHeight="520px";image.style.objectFit="contain";photoHost.replaceChildren(image);
            }catch(error){if(!d.signal.aborted)errorBox.textContent=error.message;}
            finally{if(!d.signal.aborted)view.disabled=false;}
          });card.append(view,errorBox,photoHost);
        }else card.append(el("p","text-secondary","Không có ảnh lúc nhận."));
        d.body.append(card);
      }
    }catch(error){if(!d.signal.aborted)d.body.replaceChildren(el("p","text-danger","Không tải được biên nhận: "+error.message));}
  }
  window.PickupReceipts=Object.freeze({show,validate});
})();

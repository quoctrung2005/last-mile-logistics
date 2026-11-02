"use strict";
(function(){
  const U=window.AdminUI,states={PENDING:"Chờ xét duyệt",NEEDS_INFO:"Cần bổ sung",APPROVED:"Đã được duyệt",REJECTED:"Đã từ chối"};
  const documents={IDENTITY_FRONT:"CCCD mặt trước",IDENTITY_BACK:"CCCD mặt sau",LICENSE:"Giấy phép lái xe",PORTRAIT:"Ảnh chân dung"};
  const vehicleTypes={MOTORBIKE:"Xe máy",VAN:"Xe van",TRUCK:"Xe tải"};
  const dateOnly=value=>value?String(value).slice(0,10).split("-").reverse().join("/"):null;
  const base="/api/v1/admin/shipper-registrations";
  let current;
  function destroy(){current?.destroy();current=null;}
  function row(box,label,value){const p=U.el("p");p.append(U.el("strong","",label+": "),U.el("span","",value??"Chưa cập nhật"));box.append(p);}
  async function detail(s,id){
    const d=U.dialog(s,"Hồ sơ đăng ký tài xế");if(!d)return;
    const urls=[];d.signal.addEventListener("abort",()=>{for(const url of urls)URL.revokeObjectURL(url);},{once:true});
    try{
      const data=await s.read(base+"/"+id,d.signal);if(d.closed||!s.alive())return;
      const box=U.el("div");
      for(const [label,value]of [["Trạng thái",states[data.status]],["Họ tên",data.fullName],["Tên đăng nhập",data.username],["Điện thoại",data.phone],["Email",data.email],["Ngày sinh",dateOnly(data.birthDate)],["CCCD",data.identityNumber],["Giấy phép",data.licenseNumber],["Hạn giấy phép",dateOnly(data.licenseExpiresAt)],["Bưu cục",data.branchName],["Khu vực",data.areaName],["Phương tiện đề xuất",(vehicleTypes[data.vehicleType]||data.vehicleType)+" · "+data.licensePlate],["Phản hồi",data.reviewReason]])row(box,label,value);
      box.append(U.el("p","alert alert-info","Ảnh được kiểm tra thủ công. Duyệt hồ sơ tạo tài khoản tài xế và khu vực phụ trách; phương tiện được kiểm tra, phân công riêng trong quản lý nhân viên/phương tiện."));
      const gallery=U.el("div","row g-3");
      for(const doc of data.documents){
        const tile=U.el("div","col-md-6"),label=documents[doc.kind]||doc.kind;
        tile.append(U.el("h3","h6",label));const pending=U.el("p","text-secondary","Đang tải ảnh…");tile.append(pending);gallery.append(tile);
        window.ApiClient.request(base+"/"+id+"/documents/"+encodeURIComponent(doc.kind),{responseType:"blob",signal:d.signal}).then(blob=>{
          if(d.closed||!s.alive())return;const url=URL.createObjectURL(blob);urls.push(url);
          const image=U.el("img","img-fluid border rounded");image.alt=label;image.src=url;image.style.maxHeight="260px";image.style.objectFit="contain";
          pending.replaceWith(image);
        }).catch(error=>{if(!d.closed)pending.textContent=error.sessionExpired?"Phiên đăng nhập đã hết hạn.":"Chưa tải được ảnh. Hãy đóng và mở lại hồ sơ.";});
      }
      box.append(gallery);
      if(data.history?.length){const history=U.el("div","mt-3");history.append(U.el("h3","h6","Lịch sử xử lý"));for(const event of data.history)history.append(U.el("p","",U.date(event.createdAt)+" · "+states[event.status]+(event.reason?" · "+event.reason:"")));box.append(history);}
      if(data.shipperId){const link=U.el("a","btn btn-outline-orange mt-3","Xem hồ sơ tài xế đã tạo");link.href=window.Router.href("shipper-detail",{id:data.shipperId});box.append(link);}
      if(s.can("TAIKHOAN_QUANLY")&&["PENDING","NEEDS_INFO"].includes(data.status)){
        const form=U.el("form","row g-3 mt-3"),fields={};
        const choices=data.status==="PENDING"?[["NEEDS_INFO","Yêu cầu bổ sung"],["APPROVE","Duyệt và tạo tài khoản"],["REJECT","Từ chối"]]:[["REJECT","Từ chối hồ sơ"]];
        const action=U.field(form,fields,"action","Quyết định",choices[0][0],{items:choices,required:true});
        const reason=U.field(form,fields,"reason","Lý do / nội dung cần bổ sung","",{multiline:true,maxLength:500,required:true,full:true});
        action.addEventListener("change",()=>{reason.required=action.value!=="APPROVE";});
        const commandId=crypto.randomUUID();
        U.save(s,d,form,fields,base+"/"+id+"/review","POST",()=>({action:action.value,reason:reason.value.trim()||null,expectedVersion:data.version,commandId}),()=>load(s),"Lưu kết quả xét duyệt");
        box.append(form);
      }
      d.body.replaceChildren(box);
    }catch(error){if(!d.closed)U.failure(s,d.body,error);}
  }
  async function load(s){
    const {epoch,signal}=U.request(s);s.results.replaceChildren(U.el("p","text-secondary","Đang tải…"));
    try{
      const data=await s.read(base+"?"+U.query(s.filters),signal);if(!s.alive()||epoch!==s.epoch)return;
      if(!Array.isArray(data.items))throw Error("Danh sách hồ sơ không hợp lệ.");
      const wrapper=U.el("div","table-responsive"),table=U.el("table","table align-middle"),head=U.el("thead"),line=U.el("tr");
      for(const title of ["Họ tên / tài khoản","Bưu cục","Trạng thái","Gửi lúc","Thao tác"])line.append(U.el("th","",title));head.append(line);table.append(head);
      const body=U.el("tbody");for(const item of data.items){const tr=U.el("tr"),name=U.el("td");name.append(U.el("div","fw-semibold",item.fullName),U.el("small","text-secondary",item.username));tr.append(name,U.el("td","",item.branchName),U.el("td","",states[item.status]),U.el("td","",U.date(item.submittedAt)));
        const action=U.el("td");action.append(U.button("Xem và xét duyệt",()=>detail(s,item.id),"btn btn-outline-orange btn-sm"));tr.append(action);body.append(tr);}
      table.append(body);wrapper.append(table);s.results.replaceChildren(data.items.length?wrapper:U.el("p","text-secondary py-4","Không có hồ sơ phù hợp."));
      U.pager(s.pager,data,changes=>{Object.assign(s.filters,changes);load(s);});
    }catch(error){if(s.alive()&&!signal.aborted)U.failure(s,s.results,error,()=>load(s));}
  }
  function mount(container,user,route,context){
    destroy();const s=current=U.state(container,user,route,context);s.filters={page:1,pageSize:10,status:"PENDING",keyword:"",...route.query};
    s.root.append(U.el("h1","h3","Hồ sơ đăng ký tài xế"),U.el("p","text-secondary","Kiểm tra thông tin, ảnh giấy tờ và quyết định tiếp nhận tài xế."));
    const form=U.el("form","row g-3 mb-3"),fields={};U.field(form,fields,"status","Trạng thái",s.filters.status,{items:[["","Tất cả"],...Object.entries(states)]});U.field(form,fields,"keyword","Họ tên, tài khoản, điện thoại",s.filters.keyword,{maxLength:100});
    const submit=U.button("Lọc",null,"btn btn-orange");submit.type="submit";form.append(U.actions(submit));
    form.addEventListener("submit",e=>{e.preventDefault();s.filters.status=fields.status.control.value;s.filters.keyword=fields.keyword.control.value.trim();s.filters.page=1;load(s);});
    s.results=U.el("div");s.pager=U.el("div","d-flex gap-2 align-items-center flex-wrap");s.root.append(form,s.results,s.pager);load(s);
  }
  window.RegistrationsPage=Object.freeze({mount,destroy});
}());

"use strict";
(function () {
  const UI=window.LogisticsUI,Router=window.Router,{el,button,table,summary,date}=UI;
  const states={AVAILABLE:"Sẵn sàng",IN_USE:"Đang sử dụng",MAINTENANCE:"Bảo trì",INACTIVE:"Ngừng sử dụng"};
  const tripStates={PLANNED:"Đã lập kế hoạch",ASSIGNED:"Đã phân công",ACCEPTED:"Đã nhận",IN_PROGRESS:"Đang thực hiện",COMPLETED:"Hoàn tất",CANCELLED:"Đã hủy"};
  const assignmentStates={PENDING:"Chờ nhận",ACCEPTED:"Đã nhận",IN_PROGRESS:"Đang thực hiện",COMPLETED:"Hoàn tất",ATTEMPT_FAILED:"Giao thất bại",REJECTED:"Từ chối",CANCELLED:"Đã hủy",REASSIGNED:"Đã phân công lại"};
  const number=new Intl.NumberFormat("vi-VN",{maximumFractionDigits:3});let active=null,unique=0;
  const alive=s=>active===s&&!s.abort.signal.aborted;
  const can=(s,code)=>s.permissions?.known===true&&s.permissions.codes.has(code);
  const write=s=>s.user.role==="ADMIN"&&can(s,"TAIKHOAN_QUANLY");
  const read=(s,path,signal)=>window.ApiClient.request(path,{signal:signal||s.abort.signal});
  const query=v=>new URLSearchParams(Object.entries(v).filter(([,value])=>value!==""&&value!=null)).toString();
  function actions(...nodes){const n=el("div","vehicle-actions");n.append(...nodes);return n;}
  function select(items,value){const n=el("select","form-select");for(const [id,label]of items){const o=el("option","",label);o.value=id;n.append(o);}n.value=value??"";return n;}
  function link(label,href){const n=el("a","btn btn-outline-orange btn-sm",label);n.href=href;return n;}
  function employeeLink(label,id){const n=el("a","vehicle-employee-link",label);n.href=Router.href("shipper-detail",{id});return n;}
  function alert(box,message,tone="danger"){box.replaceChildren();if(message){const n=el("div","alert alert-"+tone,message);n.setAttribute("role",tone==="success"?"status":"alert");box.append(n);}}
  function failure(s,box,error,retry){if(!alive(s)||error.name==="AbortError"||error.sessionExpired)return;alert(box,(error.status===403?"Không có quyền. ":error.status===404?"Không tìm thấy phương tiện trong phạm vi được phép. ":"Không thể tải dữ liệu. ")+error.message);if(retry&&![403,404].includes(error.status))box.append(button("Thử lại",retry,"btn btn-outline-orange"));}
  function badge(code){return el("span","badge "+(code==="AVAILABLE"?"text-bg-success":code==="INACTIVE"?"text-bg-secondary":code==="MAINTENANCE"?"text-bg-warning":"text-bg-primary"),states[code]||code);}
  function amount(value,unit){return value==null?"—":number.format(value)+" "+unit;}
  function field(form,fields,key,label,value,config={}){
    const box=el("div",config.full?"col-12":"col-md-6"),caption=el("label","form-label",label);let control;
    if(config.items)control=select(config.items,value);else{control=el("input","form-control");control.type=config.check?"checkbox":"text";if(config.check){control.className="form-check-input d-block";control.checked=!!value;}else control.value=value??"";}
    control.id="vehicle-field-"+(++unique);control.name=key;caption.htmlFor=control.id;if(config.max)control.maxLength=config.max;if(config.required)control.required=true;if(config.decimal)control.inputMode="decimal";
    const error=el("div","invalid-feedback");error.id=control.id+"-error";control.setAttribute("aria-describedby",error.id);box.append(caption,control,error);form.append(box);fields[key]={control,error,box,caption};return control;
  }
  function invalid(fields,key,message){const f=fields[key];if(!f)return;f.control.classList.add("is-invalid");f.control.setAttribute("aria-invalid","true");f.error.textContent=message;}
  function clear(fields){for(const f of Object.values(fields)){f.control.classList.remove("is-invalid");f.control.removeAttribute("aria-invalid");f.error.textContent="";}}
  function serverErrors(fields,error){for(const [key,messages]of Object.entries(error.data?.errors||{})){const actual=Object.keys(fields).find(f=>f.toLowerCase()===key.split(".").at(-1).toLowerCase());if(actual)invalid(fields,actual,[].concat(messages).join(" "));}
    const m=error.data?.message||"";if(error.data?.field)invalid(fields,error.data.field,m);else if(!Object.hasOwn(error.data||{},"field")&&/biển số.*(tồn tại|trùng)/i.test(m))invalid(fields,"licensePlate",m);
    if(/MaxWeightKg/.test(m))invalid(fields,"maxWeightKg",m);if(/MaxVolumeM3/.test(m))invalid(fields,"maxVolumeM3",m);
  }
  function showVersionConflict(s,d,box,id){
    d.versionConflict=true;
    box.append(el("p","text-secondary","Nội dung đang nhập được giữ lại. Hãy tải bản mới để đối chiếu, sau đó đóng và mở lại biểu mẫu nếu muốn sửa từ bản mới."));
    const review=el("div"),load=button("Tải bản mới để đối chiếu",async()=>{
      if(d.closed||load.disabled)return;load.disabled=true;alert(review,"");
      try{
        const latest=await read(s,"/api/v1/vehicles?id="+id,d.signal);if(!alive(s)||d.closed)return;
        if(latest.id!==id)throw new Error("Không đọc được phương tiện mới.");
        review.append(el("p","fw-semibold mt-2","Phương tiện hiện tại trên hệ thống"),summary([["Biển số",latest.licensePlate],["Loại",latest.vehicleType],["Tải trọng",amount(latest.maxWeightKg,"kg")],["Sức chứa",amount(latest.maxVolumeM3,"m³")],["Trạng thái",states[latest.status]],["Hoạt động",latest.isActive?"Đang hoạt động":"Ngừng hoạt động"]]));
      }catch(error){if(!d.closed)failure(s,review,error);}
      finally{if(!d.closed)load.disabled=false;}
    },"btn btn-outline-orange");
    box.append(load,review);
  }
  function dialog(s,title){if(s.dialog)return null;const node=el("dialog","vehicle-modal"),heading=el("h2","h5 mb-0",title),header=el("div","vehicle-modal-header"),body=el("div","vehicle-modal-body");heading.id="vehicle-dialog-"+(++unique);node.setAttribute("aria-labelledby",heading.id);const controller=new AbortController(),cancel=()=>controller.abort();s.abort.signal.addEventListener("abort",cancel,{once:true});const d={node,heading,body,signal:controller.signal,busy:false,closed:false};
    d.close=()=>{if(d.closed)return;d.closed=true;controller.abort();s.abort.signal.removeEventListener("abort",cancel);if(node.open)node.close();node.remove();if(s.dialog===d)s.dialog=null;};const close=button("Đóng",()=>{if(!d.busy)d.close();},"btn btn-outline-secondary btn-sm");d.setBusy=value=>{d.busy=value;close.disabled=value;};node.addEventListener("cancel",e=>{if(d.busy)e.preventDefault();else d.close();});node.addEventListener("close",d.close);header.append(heading,close);node.append(header,body);s.root.append(node);s.dialog=d;node.showModal();body.append(el("p","text-secondary","Đang tải…"));return d;
  }
  async function editor(s,id,statusOnly=false){if(!write(s))return;const d=dialog(s,id?(statusOnly?"Đổi trạng thái phương tiện":"Sửa phương tiện"):"Thêm phương tiện");if(!d)return;
    async function load(){try{const [c,catalog]=await Promise.all([id?read(s,"/api/v1/vehicles?id="+id,d.signal):null,read(s,"/api/v1/vehicles/types",d.signal)]);if(!alive(s)||d.closed)return;
      const openedVersion=c?.version;
      if(!Array.isArray(catalog.items)||!catalog.items.length||catalog.items.some(t=>!t.code||!t.name||!(t.maxCargoWeightKg>0)))throw new Error("Danh mục loại phương tiện không hợp lệ.");
      const form=el("form","row g-3"),fields={},types=catalog.items;
      if(statusOnly)form.append(el("p","col-12 fw-semibold",c.code+" · "+c.licensePlate));
      const plate=field(form,fields,"licensePlate","Biển số *",c?.licensePlate,{required:true,max:20});
      const typeItems=[["","Chọn loại phương tiện"],...types.map(t=>[t.code,t.name])];
      if(c&&!types.some(t=>t.code===c.vehicleType))typeItems.push([c.vehicleType,c.vehicleType+" (dữ liệu cũ, chưa có cấu hình)"]);
      const type=field(form,fields,"vehicleType","Loại phương tiện *",c?.vehicleType,{required:true,items:typeItems});
      const weight=field(form,fields,"maxWeightKg","Tải trọng hàng (kg)",c?.maxWeightKg);
      const volume=field(form,fields,"maxVolumeM3","Sức chứa (m³)",c?.maxVolumeM3);
      weight.readOnly=true;volume.readOnly=true;weight.placeholder=volume.placeholder="Tự hiển thị khi chọn loại xe";
      const weightHint=el("div","form-text"),volumeHint=el("div","form-text");weightHint.id=weight.id+"-hint";volumeHint.id=volume.id+"-hint";
      fields.maxWeightKg.box.append(weightHint);fields.maxVolumeM3.box.append(volumeHint);weight.setAttribute("aria-describedby",fields.maxWeightKg.error.id+" "+weightHint.id);volume.setAttribute("aria-describedby",fields.maxVolumeM3.error.id+" "+volumeHint.id);
      const definition=()=>types.find(t=>t.code===type.value);
      let useTypeCapacity=false;
      function capacityRules(submit=false){const t=definition(),preserve=c&&!useTypeCapacity&&type.value===c.vehicleType;
        for(const key of ["vehicleType","maxWeightKg","maxVolumeM3"]){fields[key].control.classList.remove("is-invalid");fields[key].control.removeAttribute("aria-invalid");fields[key].error.textContent="";}
        weightHint.textContent=type.value?"Khối lượng hàng có thể chở, không phải trọng lượng xe. ":"Chọn loại phương tiện để tự hiển thị tải trọng và sức chứa.";
        if(preserve)weightHint.textContent+="Đang hiển thị tải trọng đã lưu. Chọn loại xe để áp dụng cấu hình của loại đó.";
        else if(t?.requiresConfirmation)weightHint.textContent+=t.source;
        volumeHint.textContent=preserve?"Sức chứa đã lưu của xe; chỉ đổi khi chọn loại xe.":t?(t.maxCargoVolumeM3==null?"Loại xe chưa cấu hình sức chứa.":"Sức chứa tự động theo loại xe, không cần nhập."):"";
        if((type.value||submit)&&!t&&!preserve)invalid(fields,"vehicleType","Vui lòng chọn loại phương tiện có trong danh mục.");
      }
      type.addEventListener("change",()=>{const t=definition();useTypeCapacity=!!t;if(t){weight.value=t.maxCargoWeightKg;volume.value=t.maxCargoVolumeM3??"";}else if(c&&type.value===c.vehicleType){weight.value=c.maxWeightKg;volume.value=c.maxVolumeM3??"";}else{weight.value="";volume.value="";}capacityRules();});capacityRules();
      if(statusOnly){for(const n of [plate,weight,volume])n.readOnly=true;type.disabled=true;}
      const status=field(form,fields,"status","Trạng thái *",c?.status||"AVAILABLE",{required:true,items:[["","Chọn trạng thái"],...["AVAILABLE","MAINTENANCE","INACTIVE"].map(v=>[v,states[v]])]});
      form.append(el("p","col-12 small text-secondary mb-0",c?"Mã phương tiện: "+c.code:"Mã phương tiện được hệ thống sinh tự động."));
      if(c?.status==="IN_USE")form.append(el("p","col-12 text-secondary","Trạng thái Đang sử dụng do nghiệp vụ giao hàng cập nhật. Chọn trạng thái quản lý trước khi lưu; xe còn nhiệm vụ sẽ bị từ chối."));
      const confirm=field(form,fields,"confirmStatus","Xác nhận đổi trạng thái",false,{check:true,full:true});
      const important=()=>c?status.value!==c.status:status.value!=="AVAILABLE";
      function updateConfirmation(){confirm.checked=false;fields.confirmStatus.box.hidden=!important();fields.confirmStatus.caption.textContent="Tôi xác nhận "+(c?"đổi xe "+c.code+" · "+c.licensePlate+" từ "+states[c.status]+" sang ":"tạo phương tiện ở trạng thái ")+(states[status.value]||"trạng thái đã chọn")+".";}
      status.addEventListener("change",updateConfirmation);updateConfirmation();
      const feedback=el("div","col-12"),save=button("Lưu",null,"btn btn-orange");save.type="submit";form.append(feedback,actions(save));form.noValidate=true;
      form.addEventListener("submit",async e=>{e.preventDefault();if(d.busy||d.versionConflict||d.writeUnknown)return;clear(fields);alert(feedback,"");for(const [key,f]of Object.entries(fields)){if(f.control.required&&!f.control.value.trim())invalid(fields,key,"Vui lòng nhập trường này.");if(f.control.maxLength>0&&f.control.value.length>f.control.maxLength)invalid(fields,key,"Tối đa "+f.control.maxLength+" ký tự.");}
        capacityRules(true);const vtype=type.value,applyPreset=useTypeCapacity||!c||vtype!==c.vehicleType;
        if(applyPreset&&!definition())invalid(fields,"vehicleType","Vui lòng chọn loại phương tiện có trong danh mục.");
        if(important()&&!confirm.checked)invalid(fields,"confirmStatus","Vui lòng xác nhận trạng thái mới của phương tiện.");
        const first=Object.values(fields).find(f=>f.control.classList.contains("is-invalid"));if(first){first.control.focus();return;}
        const payload={id:c?.id||null,licensePlate:plate.value.trim(),vehicleType:vtype,status:status.value,isActive:status.value!=="INACTIVE",useTypeCapacity:applyPreset};
        if(c)payload.expectedVersion=openedVersion;
        if(!applyPreset){payload.maxWeightKg=c.maxWeightKg;payload.maxVolumeM3=c.maxVolumeM3;}
        const controls=[...form.querySelectorAll("input,select,button")].map(n=>[n,n.disabled]);for(const [n]of controls)n.disabled=true;d.setBusy(true);save.textContent="Đang lưu…";
        try{window.WriteOutcome.assertCanSend(d,{path:"/api/v1/vehicles",method:"POST",payload});const saved=await window.ApiClient.request("/api/v1/vehicles",{method:"POST",body:JSON.stringify(payload),signal:d.signal});if(!alive(s)||d.closed)return;d.close();s.message=saved.message||(id?"Đã cập nhật phương tiện.":"Đã thêm phương tiện.");await refresh(s);}
        catch(error){if(!alive(s)||d.closed)return;if(window.WriteOutcome.lock(d,feedback,error,{path:"/api/v1/vehicles",payload,scope:form}))return;if(error.name==="AbortError"||error.sessionExpired)return;serverErrors(fields,error);alert(feedback,error.message);if(error.status===409&&error.data?.code==="VERSION_CONFLICT")showVersionConflict(s,d,feedback,c.id);Object.values(fields).find(f=>f.control.classList.contains("is-invalid"))?.control.focus();}
        finally{if(!d.closed){d.setBusy(false);window.WriteOutcome.restore(controls,d);save.disabled=!!d.writeUnknown||!!d.versionConflict;save.textContent="Lưu";}}
      });d.body.replaceChildren(form);plate.focus();
    }catch(error){if(!d.closed)failure(s,d.body,error,load);}}await load();
  }
  function pagination(box,data,prev,next){const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize)),previous=button("‹ Trước",prev),following=button("Sau ›",next);previous.disabled=data.page<=1;following.disabled=data.page>=pages;box.replaceChildren(el("span","text-secondary",data.totalItems+" kết quả · Trang "+data.page+" / "+pages),previous,following);}
  async function linkEmployee(s,id){if(!window.VehicleLink.permitted(s))return;const d=dialog(s,"Liên kết nhân viên giao hàng");if(!d)return;
    async function load(){try{const v=await read(s,"/api/v1/vehicles?id="+id,d.signal);if(!alive(s)||d.closed)return;
      if(v.currentAssignment){d.close();return window.VehicleLink.openForShipper(s,v.currentAssignment.shipperId);}
      const panel=el("div"),searchForm=el("form","vehicle-link-search"),search=el("input","form-control");search.maxLength=150;search.placeholder="Tìm mã, họ tên hoặc điện thoại nhân viên";search.setAttribute("aria-label","Tìm nhân viên giao hàng");const find=button("Tìm",null,"btn btn-outline-orange");find.type="submit";searchForm.append(search,find);
      const picker=select([["","Đang tải nhân viên…"]]);picker.id="vehicle-employee-"+(++unique);picker.setAttribute("aria-describedby",picker.id+"-help");const label=el("label","form-label mt-3","Nhân viên giao hàng *");label.htmlFor=picker.id;
      const help=el("p","text-secondary mt-2","Chọn nhân viên đang hoạt động để xem phương tiện hiện tại và xác nhận liên kết. Điều kiện nhiệm vụ, bằng lái và xe được kiểm tra lại khi lưu.");help.id=picker.id+"-help";
      const feedback=el("div"),pager=el("div","vehicle-pagination"),next=button("Tiếp tục",()=>{if(!records.some(r=>String(r.id)===picker.value)){alert(feedback,"Hãy chọn nhân viên đã tải.");return;}const shipperId=Number(picker.value);d.close();window.VehicleLink.openForShipper(s,shipperId,v);},"btn btn-orange mt-3");next.disabled=true;
      panel.append(el("p","fw-semibold",v.code+" · "+v.licensePlate),searchForm,label,picker,help,feedback,pager,next);d.body.replaceChildren(panel);
      let page=1,pending,records=[];searchForm.addEventListener("submit",e=>{e.preventDefault();page=1;listEmployees();});
      async function listEmployees(){pending?.abort();pending=new AbortController();const signal=AbortSignal.any([d.signal,pending.signal]);picker.disabled=true;next.disabled=true;alert(feedback,"");pager.replaceChildren();
        try{const path="/api/v1/shippers?"+query({activeOnly:true,keyword:search.value.trim(),page,pageSize:10}),data=window.ApiClient.validatePage(await read(s,path,signal),path,["id"]);if(!alive(s)||d.closed||signal.aborted)return;records=data.items;const n=select([["",records.length?"Chọn nhân viên giao hàng":"Không có nhân viên phù hợp"],...records.map(r=>[r.id,r.employeeCode+" · "+r.fullName+" · "+r.branchName])]);picker.replaceChildren(...n.children);picker.value="";picker.disabled=!records.length;next.disabled=!records.length;pagination(pager,data,()=>{page--;listEmployees();},()=>{page++;listEmployees();});}
        catch(error){if(!signal.aborted&&!d.closed)failure(s,feedback,error,listEmployees);}}
      listEmployees();
    }catch(error){if(!d.closed)failure(s,d.body,error,load);}}await load();
  }
  function rowActions(s,v){const n=actions(link("Xem chi tiết",Router.href("vehicle-detail",{id:v.id},s.filters||s.route.query)));if(write(s))n.append(button("Sửa",()=>editor(s,v.id)),button("Đổi trạng thái",()=>editor(s,v.id,true)));return n;}
  async function list(s){s.listAbort?.abort();s.listAbort=new AbortController();const signal=AbortSignal.any([s.abort.signal,s.listAbort.signal]);Router.updateQuery(s.filters,s.route);s.route=Router.current()||s.route;s.results.replaceChildren(el("p","vehicle-empty","Đang tải phương tiện…"));s.pager.replaceChildren();alert(s.feedback,"");
    try{const path="/api/v1/vehicles?"+query({...s.filters,includeFilterOptions:true}),data=window.ApiClient.validatePage(await read(s,path,signal),path,["id"]);if(!alive(s)||signal.aborted)return;const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize));if(data.page>pages){s.filters.page=pages;return list(s);}
      if(!Array.isArray(data.filterOptions?.vehicleTypes)||!Array.isArray(data.filterOptions?.branches))throw new Error("API không trả danh mục bộ lọc phương tiện hợp lệ.");
      const type=select([["","Tất cả loại"],...data.filterOptions.vehicleTypes.map(t=>[t.value,t.value])],s.filters.vehicleType);if(s.filters.vehicleType&&!data.filterOptions.vehicleTypes.some(t=>t.value===s.filters.vehicleType)){const opt=el("option","",s.filters.vehicleType);opt.value=s.filters.vehicleType;type.append(opt);}s.type.replaceChildren(...type.children);s.type.value=s.filters.vehicleType;s.type.disabled=false;
      const branch=select([["","Tất cả bưu cục trong phạm vi"],...data.filterOptions.branches.map(b=>[b.id,b.name])],s.filters.branchId);s.branch.replaceChildren(...branch.children);s.branch.value=String(s.filters.branchId);s.branch.disabled=false;
      s.results.replaceChildren(data.items.length?table(["Mã phương tiện","Biển số","Loại","Tải trọng (kg)","Bưu cục nhân viên liên kết","Nhân viên đang liên kết","Trạng thái","Thao tác"],data.items.map(v=>[v.code,v.licensePlate,v.vehicleType,amount(v.maxWeightKg,"kg"),v.currentShipperBranchName,v.currentShipperId?(can(s,"TAIKHOAN_XEM")?employeeLink(v.currentShipperName||"Nhân viên #"+v.currentShipperId,v.currentShipperId):v.currentShipperName):"Chưa liên kết",badge(v.status),rowActions(s,v)])):el("p","vehicle-empty","Không có phương tiện phù hợp với bộ lọc."));
      pagination(s.pager,data,()=>{s.filters.page--;list(s);},()=>{s.filters.page++;list(s);});const size=select([...new Set([10,20,50,100,data.pageSize])].sort((a,b)=>a-b).map(v=>[v,v+" dòng"]),data.pageSize);size.setAttribute("aria-label","Số dòng mỗi trang");size.addEventListener("change",()=>{s.filters.pageSize=Number(size.value);s.filters.page=1;list(s);});s.pager.append(size);if(s.message){alert(s.feedback,s.message,"success");s.message="";}
    }catch(error){if(!signal.aborted){s.results.replaceChildren();failure(s,s.feedback,error,()=>list(s));}}
  }
  function mountList(s){const q=s.route.query;s.filters={page:q.page||1,pageSize:q.pageSize||10,keyword:q.keyword||"",vehicleType:q.vehicleType||"",branchId:q.branchId||"",status:q.status||""};
    const toolbar=actions();toolbar.classList.add("vehicle-toolbar");if(write(s))toolbar.append(button("Thêm phương tiện",()=>editor(s),"btn btn-orange"));toolbar.append(button("Làm mới",()=>list(s),"btn btn-outline-orange"));
    const form=el("form","row g-3 vehicle-filters"),fields={};field(form,fields,"keyword","Tìm biển số hoặc mã phương tiện",s.filters.keyword,{max:100});s.type=field(form,fields,"vehicleType","Loại phương tiện",s.filters.vehicleType,{items:[["","Đang tải loại xe…"]]});s.type.disabled=true;s.branch=field(form,fields,"branchId","Bưu cục nhân viên liên kết",s.filters.branchId,{items:[["","Đang tải bưu cục…"]]});s.branch.disabled=true;field(form,fields,"status","Trạng thái",s.filters.status,{items:[["","Tất cả trạng thái"],...Object.entries(states)]});const search=button("Tìm kiếm",null,"btn btn-outline-orange");search.type="submit";form.append(actions(search));form.addEventListener("submit",e=>{e.preventDefault();for(const [key,f]of Object.entries(fields))s.filters[key]=f.control.value.trim();s.filters.page=1;list(s);});for(const key of ["vehicleType","branchId","status"])fields[key].control.addEventListener("change",()=>form.requestSubmit());
    s.feedback=el("div");s.results=el("div","vehicle-results");s.pager=el("div","vehicle-pagination");s.root.append(toolbar,form,s.feedback,s.results,s.pager);list(s);
  }
  function related(s,v,isTrips){const panel=el("section","vehicle-related");panel.append(el("h3","h6",isTrips?"Chuyến giao sử dụng xe":"Phân công đang sử dụng xe"));const body=el("div"),pager=el("div","vehicle-pagination");let page=1,status=isTrips?"IN_PROGRESS":"",pending;
    if(isTrips){const filter=select([["","Tất cả chuyến"],...Object.entries(tripStates)],status);filter.setAttribute("aria-label","Trạng thái chuyến giao");filter.addEventListener("change",()=>{status=filter.value;page=1;load();});panel.append(filter);}panel.append(body,pager);
    async function load(){pending?.abort();pending=new AbortController();const signal=AbortSignal.any([s.abort.signal,pending.signal]);body.replaceChildren(el("p","text-secondary","Đang tải…"));pager.replaceChildren();try{const path=(isTrips?"/api/v1/trips":"/api/v1/dispatch/assignments")+"?"+query({vehicleId:v.id,activeOnly:isTrips?undefined:true,status,page,pageSize:10}),data=window.ApiClient.validatePage(await read(s,path,signal),path,["id"]);if(!alive(s)||signal.aborted||!panel.isConnected)return;
      body.replaceChildren(data.items.length?table(isTrips?["Mã chuyến","Nhân viên sử dụng","Bưu cục","Trạng thái","Số đơn"]:["Mã đơn","Mã vận đơn","Nhân viên sử dụng","Bưu cục","Trạng thái","Chuyến"],data.items.map(r=>isTrips?[r.tripCode,r.shipperName,r.branchName,tripStates[r.status]||r.status,r.orderCount]:[r.orderCode,r.trackingNumber,r.shipperName,r.branchName,assignmentStates[r.assignmentStatus]||r.assignmentStatus,r.tripId])):el("p","vehicle-empty",isTrips?"Không có chuyến phù hợp.":"Không có phân công đang sử dụng xe."));pagination(pager,data,()=>{page--;load();},()=>{page++;load();});
    }catch(error){if(!signal.aborted&&panel.isConnected)failure(s,body,error,load);}}queueMicrotask(load);return panel;
  }
  function capacityCheck(s,v){const panel=el("section","vehicle-related vehicle-capacity"),body=el("div"),result=el("div","mt-2"),pager=el("div","vehicle-pagination");let page=1,request;
    panel.append(el("h3","h6","Kiểm tra tải khi điều phối"),el("p","small text-secondary","Chọn đơn đang chờ điều phối. Kết quả tính tổng hàng trên xe và đơn mới; backend kiểm tra lại khi phân công."),body,result,pager);
    async function load(){request?.abort();request=new AbortController();const signal=AbortSignal.any([s.abort.signal,request.signal]);body.replaceChildren(el("p","text-secondary","Đang tải đơn chờ điều phối…"));result.replaceChildren();pager.replaceChildren();
      try{const data=await read(s,"/api/v1/dispatch/orders?"+query({page,pageSize:10}),signal);if(!alive(s)||signal.aborted||!panel.isConnected)return;
        if(!data.items.length){body.replaceChildren(el("p","text-secondary","Không có đơn chờ điều phối trong phạm vi."));return;}
        const order=select([["","Chọn đơn hàng"],...data.items.map(o=>[o.id,o.orderCode+" · "+amount(o.weightKg,"kg")])],"");order.setAttribute("aria-label","Đơn hàng kiểm tra tải");body.replaceChildren(order);
        let checkRequest;order.addEventListener("change",async()=>{checkRequest?.abort();result.replaceChildren();if(!order.value)return;checkRequest=new AbortController();const checkSignal=AbortSignal.any([signal,checkRequest.signal]);result.append(el("p","text-secondary","Đang kiểm tra…"));
          try{const data=await read(s,"/api/v1/dispatch/shippers?"+query({orderId:order.value,vehicleId:v.id}),checkSignal);if(!alive(s)||checkSignal.aborted||!panel.isConnected)return;
            const candidate=data.items[0]||data.excludedVehicles?.[0];
            if(!candidate){alert(result,"Xe chưa có nhân viên đủ điều kiện trong bưu cục/khu vực của đơn. Kiểm tra liên kết, trạng thái nhân viên và khu vực phụ trách.","warning");return;}
            alert(result,(candidate.eligibilityReason||"Xe đủ tải cho đơn đã chọn.")+" Tải trọng thực tế: "+amount(candidate.maxWeightKg,"kg")+"; hàng đã phân công: "+amount(candidate.assignedWeightKg,"kg")+"; đơn mới: "+amount(data.orderWeightKg,"kg")+".",candidate.eligibilityReason?"warning":"success");
          }catch(error){if(!checkSignal.aborted&&panel.isConnected)failure(s,result,error);}});
        pagination(pager,data,()=>{page--;load();},()=>{page++;load();});
      }catch(error){if(!signal.aborted&&panel.isConnected)failure(s,body,error,load);}}
    queueMicrotask(load);return panel;
  }
  async function detail(s){const epoch=++s.detailEpoch;s.root.replaceChildren(el("p","vehicle-empty","Đang tải phương tiện…"));const back=link("‹ Quay về danh sách",Router.href("vehicles",{},s.route.query));
    try{const v=await read(s,"/api/v1/vehicles?id="+s.route.params.id);if(!alive(s)||epoch!==s.detailEpoch)return;if(v.id!==s.route.params.id||!Array.isArray(v.assignmentHistory))throw new Error("API chi tiết phương tiện trả dữ liệu không hợp lệ.");const tools=actions(back,button("Làm mới",()=>detail(s),"btn btn-outline-orange"));if(write(s))tools.append(button("Sửa",()=>editor(s,v.id)),button("Đổi trạng thái",()=>editor(s,v.id,true)));if(window.VehicleLink.permitted(s)){const manage=button(v.currentAssignment?"Quản lý liên kết":"Liên kết nhân viên",()=>linkEmployee(s,v.id),"btn btn-orange");if(!v.currentAssignment&&(!v.isActive||v.status!=="AVAILABLE"||v.activeAssignmentCount>0||v.activeTripCount>0)){manage.disabled=true;manage.title="Xe phải hoạt động, sẵn sàng và không có nhiệm vụ/chuyến đang mở để liên kết.";}tools.append(manage);}s.root.replaceChildren(tools);const feedback=el("div");s.root.append(feedback);if(s.message){alert(feedback,s.message,"success");s.message="";}
      s.root.append(summary([["Mã phương tiện",v.code],["Biển số",v.licensePlate],["Loại phương tiện",v.vehicleType],["Tải trọng tối đa",amount(v.maxWeightKg,"kg")],["Sức chứa tối đa",amount(v.maxVolumeM3,"m³")],["Trạng thái",states[v.status]],["Hoạt động",v.isActive?"Đang hoạt động":"Ngừng hoạt động"],["Nhân viên liên kết thường xuyên",v.currentAssignment?.shipperName],["Bưu cục của nhân viên liên kết",v.currentAssignment?.branchName],["Thời điểm liên kết",date(v.currentAssignment?.assignedAt)],["Phân công đang sử dụng xe",v.activeAssignmentCount],["Chuyến chưa kết thúc",v.activeTripCount]]));
      if(v.currentAssignment&&can(s,"TAIKHOAN_XEM"))s.root.append(link("Xem nhân viên giao hàng",Router.href("shipper-detail",{id:v.currentAssignment.shipperId})));
      s.root.append(el("p","small text-secondary mt-3","Xe không có bưu cục riêng. Nhân viên liên kết thường xuyên có thể khác nhân viên sử dụng xe trong từng phân công/chuyến giao."));
      const history=el("section","vehicle-related");history.append(el("h3","h6","Lịch sử liên kết nhân viên"),el("p","small text-secondary","Hiển thị tối đa 10 lần liên kết gần nhất trong phạm vi được phép."));history.append(v.assignmentHistory.length?table(["Nhân viên","Bắt đầu","Kết thúc","Ghi chú"],v.assignmentHistory.map(h=>[h.shipperName,date(h.assignedAt),h.endedAt?date(h.endedAt):"Đang liên kết",h.notes])):el("p","text-secondary","Chưa có lịch sử liên kết."));s.root.append(history,related(s,v,false),related(s,v,true));if(can(s,"DIEUPHOI_PHANCONG"))s.root.append(capacityCheck(s,v));
    }catch(error){if(alive(s)&&epoch===s.detailEpoch){s.root.replaceChildren(back);const box=el("div");s.root.append(box);failure(s,box,error,()=>detail(s));}}
  }
  function refresh(s){if(!alive(s))return;return s.route.mode==="detail"?detail(s):list(s);}
  function destroy(){if(!active)return;active.dialog?.close();active.abort.abort();active.listAbort?.abort();active=null;}
  function mount(container,user,route,context){destroy();const root=el("div","vehicles-page");container.replaceChildren(root);const s={root,user,route,permissions:context.permissions,abort:new AbortController(),detailEpoch:0};s.externalActive=()=>alive(s);s.externalRefresh=()=>refresh(s);active=s;context.signal?.addEventListener("abort",()=>{s.abort.abort();s.dialog?.close();},{once:true,signal:s.abort.signal});if(!can(s,"DIEUPHOI_GIAMSAT")){alert(root,"Bạn không có quyền xem phương tiện.");return;}if(route.mode==="detail")detail(s);else mountList(s);}
  window.VehiclesPage=Object.freeze({mount,destroy});
}());

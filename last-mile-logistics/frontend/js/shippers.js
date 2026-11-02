"use strict";
(function () {
  const UI = window.LogisticsUI, Router = window.Router;
  const {el, button, table, summary, date} = UI;
  const availability = {AVAILABLE: "Sẵn sàng nhận đơn", DELIVERING: "Đang giao hàng", BREAK: "Tạm nghỉ", OFFLINE: "Ngoại tuyến"};
  const accountStates = {ACTIVE: "Đang hoạt động", LOCKED: "Bị khóa", INACTIVE: "Ngừng hoạt động"};
  const vehicleStates = {AVAILABLE: "Sẵn sàng", IN_USE: "Đang sử dụng", MAINTENANCE: "Bảo trì", INACTIVE: "Ngừng sử dụng"};
  const assignmentStates = {PENDING: "Chờ nhận", ACCEPTED: "Đã nhận", IN_PROGRESS: "Đang thực hiện", COMPLETED: "Hoàn tất", ATTEMPT_FAILED: "Giao thất bại", REJECTED: "Từ chối", CANCELLED: "Đã hủy", REASSIGNED: "Đã phân công lại"};
  const tripStates = {PLANNED: "Đã lập kế hoạch", ASSIGNED: "Đã phân công", ACCEPTED: "Đã nhận", IN_PROGRESS: "Đang thực hiện", COMPLETED: "Hoàn tất", CANCELLED: "Đã hủy"};
  let active = null, unique = 0;
  const alive = s => (s.externalActive ? s.externalActive() : active === s) && !s.abort.signal.aborted;
  const can = (s, code) => s.permissions?.known === true && s.permissions.codes.has(code);
  const manageVehicle = s => s.user.role === "ADMIN" && can(s, "TAIKHOAN_QUANLY") && can(s, "DIEUPHOI_GIAMSAT") && can(s, "TAIKHOAN_XEM");
  const read = (s, path, signal) => window.ApiClient.request(path, {signal: signal || s.abort.signal});
  function query(values) {return new URLSearchParams(Object.entries(values).filter(([,v]) => v !== "" && v != null)).toString();}
  function select(items, value) {const n=el("select","form-select"); for(const [v,label] of items){const o=el("option","",label);o.value=v;n.append(o);}n.value=value??"";return n;}
  function actions(...nodes){const n=el("div","shipper-actions");n.append(...nodes);return n;}
  function link(label,href){const n=el("a","btn btn-outline-orange btn-sm",label);n.href=href;return n;}
  function alert(box,message,tone="danger"){box.replaceChildren();if(message){const n=el("div","alert alert-"+tone,message);n.setAttribute("role",tone==="success"?"status":"alert");box.append(n);}}
  function failure(s,box,error,retry){if(!alive(s)||error.name==="AbortError"||error.sessionExpired)return;alert(box,(error.status===403?"Không có quyền. ":error.status===404?"Không tìm thấy nhân viên trong phạm vi được phép. ":"Không thể tải dữ liệu. ")+error.message);if(retry&&![403,404].includes(error.status))box.append(button("Thử lại",retry,"btn btn-outline-orange"));}
  function badge(value,label){return el("span","badge "+(value?"text-bg-success":"text-bg-secondary"),label);}
  function working(code){return badge(code==="AVAILABLE",availability[code]||code);}
  function vehicleText(v){return v?v.licensePlate+" · "+v.code:"Chưa có phương tiện";}
  function field(form,fields,key,label,value,config={}){
    const wrap=el("div",config.full?"col-12":"col-md-6"),cap=el("label","form-label",label);let control;
    if(config.items)control=select(config.items,value);
    else {control=el(config.multiline?"textarea":"input","form-control");if(!config.multiline)control.type=config.type||"text";control.value=value??"";}
    control.id="shipper-field-"+(++unique);control.name=key;cap.htmlFor=control.id;
    if(config.max)control.maxLength=config.max;if(config.required)control.required=true;
    const error=el("div","invalid-feedback");error.id=control.id+"-error";control.setAttribute("aria-describedby",error.id);wrap.append(cap,control,error);form.append(wrap);fields[key]={control,error};return control;
  }
  function invalid(fields,key,message){const f=fields[key];if(!f)return;f.control.classList.add("is-invalid");f.control.setAttribute("aria-invalid","true");f.error.textContent=message;}
  function clearErrors(fields){for(const f of Object.values(fields)){f.control.classList.remove("is-invalid");f.control.removeAttribute("aria-invalid");f.error.textContent="";}}
  function invalidLicenseUpdate(record,licenseNumber,licenseExpiresAt,isActive){
    if(!window.VietnamDate.isLicenseExpired(licenseExpiresAt))return false;
    // A past date can be retained as history, but cannot be newly entered,
    // attached to a different licence or used to reactivate an inactive shipper.
    return !record||(!record.isActive&&isActive)||
      (record.licenseNumber||"").trim()!==licenseNumber.trim()||
      (record.licenseExpiresAt?.slice(0,10)||null)!==(licenseExpiresAt||null);
  }
  function serverErrors(fields,error){
    for(const [key,messages] of Object.entries(error.data?.errors||{})){const name=key.split(".").at(-1);const actual=key.toLowerCase().startsWith("areas")?"areas":Object.keys(fields).find(k=>k.toLowerCase()===name.toLowerCase());if(actual)invalid(fields,actual,[].concat(messages).join(" "));}
    const m=error.data?.message||"";
    if(/khu vực/i.test(m))invalid(fields,"areas",m);
    if(/CCCD/i.test(m))invalid(fields,"identityNumber",m);
    if(/tài khoản.*(hồ sơ|hợp lệ|SHIPPER)/i.test(m))invalid(fields,"accountId",m);
    if(/bằng lái.*(hết hạn|quá khứ)/i.test(m))invalid(fields,"licenseExpiresAt",m);
  }
  function dialog(s,title){
    if(s.dialog)return null;const node=el("dialog","shipper-modal"),heading=el("h2","h5 mb-0",title),header=el("div","shipper-modal-header"),body=el("div","shipper-modal-body");
    heading.id="shipper-dialog-"+(++unique);node.setAttribute("aria-labelledby",heading.id);const abort=new AbortController();const cancel=()=>abort.abort();s.abort.signal.addEventListener("abort",cancel,{once:true});
    const d={node,heading,body,signal:abort.signal,busy:false,closed:false};
    d.close=()=>{if(d.closed)return;d.closed=true;abort.abort();s.abort.signal.removeEventListener("abort",cancel);if(node.open)node.close();node.remove();if(s.dialog===d)s.dialog=null;};
    const close=button("Đóng",()=>{if(!d.busy)d.close();},"btn btn-outline-secondary btn-sm");d.setBusy=b=>{d.busy=b;close.disabled=b;};
    header.append(heading,close);node.append(header,body);node.addEventListener("cancel",e=>{if(d.busy)e.preventDefault();else d.close();});node.addEventListener("close",d.close);s.root.append(node);s.dialog=d;node.showModal();body.append(el("p","text-secondary","Đang tải…"));return d;
  }
  function save(s,d,form,fields,path,method,build,label="Lưu"){
    const box=el("div","col-12"),submit=button(label,null,"btn btn-orange");submit.type="submit";form.append(box,actions(submit));form.noValidate=true;
    form.addEventListener("submit",async e=>{
      e.preventDefault();if(d.busy||d.writeUnknown||d.versionConflict)return;clearErrors(fields);alert(box,"");
      for(const [key,f]of Object.entries(fields)){if(f.control.required&&!f.control.value.trim())invalid(fields,key,"Vui lòng nhập trường này.");if(f.control.maxLength>0&&f.control.value.length>f.control.maxLength)invalid(fields,key,"Tối đa "+f.control.maxLength+" ký tự.");}
      const payload=build();const first=Object.values(fields).find(f=>f.control.classList.contains("is-invalid"));if(!payload||first){first?.control.focus();return;}
      const controls=[...form.querySelectorAll("input,select,textarea,button")].map(c=>[c,c.disabled]);let writeError;for(const [c]of controls)c.disabled=true;d.setBusy(true);submit.textContent="Đang lưu…";
      try{window.WriteOutcome.assertCanSend(d,{path,payload,method});await window.ApiClient.request(path,{method,body:JSON.stringify(payload),signal:d.signal});if(!alive(s)||d.closed)return;d.close();s.message="Đã lưu thay đổi.";await refresh(s);}
      catch(error){if(!alive(s)||d.closed)return;if(window.WriteOutcome.lock(d,box,error,{path,payload,scope:form}))return;if(error.name==="AbortError"||error.sessionExpired)return;writeError=error;serverErrors(fields,error);alert(box,error.message);if(error.status===409&&error.data?.code==="VERSION_CONFLICT")showVersionConflict(s,d,box,Number(path.split("/").at(-1)));Object.values(fields).find(f=>f.control.classList.contains("is-invalid"))?.control.focus();}
      finally{if(!d.closed){d.setBusy(false);window.WriteOutcome.restore(controls,d);submit.disabled=!!d.writeUnknown||!!d.versionConflict;submit.textContent=label;if(!d.writeUnknown&&!d.versionConflict){if(writeError)d.onSaveError?.(writeError);d.onIdle?.();}}}
    });
  }
  function showVersionConflict(s,d,box,id){
    d.versionConflict=true;
    box.append(el("p","text-secondary","Nội dung đang nhập được giữ lại. Hãy tải bản mới để đối chiếu, sau đó đóng và mở lại biểu mẫu nếu muốn sửa từ bản mới."));
    const review=el("div"),load=button("Tải bản mới để đối chiếu",async()=>{
      if(d.closed||load.disabled)return;load.disabled=true;alert(review,"");
      try{
        const latest=await read(s,"/api/v1/shippers?id="+id,d.signal);if(!alive(s)||d.closed)return;
        if(latest.id!==id)throw new Error("Không đọc được hồ sơ shipper mới.");
        review.append(el("p","fw-semibold mt-2","Hồ sơ hiện tại trên hệ thống"),summary([["CCCD",latest.identityNumber],["Số bằng lái",latest.licenseNumber],["Ngày hết hạn",latest.licenseExpiresAt?.slice(0,10)],["Hoạt động",latest.isActive?"Đang hoạt động":"Ngừng hoạt động"],["Khu vực",latest.areas?.map(a=>(a.name||a.id)+(a.isPrimary?" (chính)":"")).join(", ")]]));
      }catch(error){if(!d.closed)failure(s,review,error);}
      finally{if(!d.closed)load.disabled=false;}
    },"btn btn-outline-orange");
    box.append(load,review);
  }
  function areasForm(form,fields,areas,existing){
    const group=el("fieldset","col-12 shipper-area-fields"),legend=el("legend","form-label","Khu vực phụ trách"),rows=el("div","shipper-area-rows"),error=el("div","invalid-feedback d-block");
    group.tabIndex=-1;const radioName="shipper-primary-"+(++unique);fields.areas={control:group,error};group.append(legend,rows);const add=button("Thêm khu vực",()=>addRow({}),"btn btn-outline-orange btn-sm");group.append(add,error);form.append(group);
    function addRow(a){if(rows.children.length>=100)return;const row=el("div","shipper-area-row"),area=select([["","Chọn khu vực"],...areas.map(k=>[k.id,k.name])],a.id);
      if(a.id&&!areas.some(k=>k.id===a.id)){const o=el("option","",(a.name||"Khu vực #"+a.id)+" (đã ngừng hoạt động)");o.value=a.id;area.append(o);area.value=a.id;}
      area.setAttribute("aria-label","Khu vực phụ trách");const radio=el("input","form-check-input");radio.type="radio";radio.name=radioName;radio.checked=!!a.isPrimary;radio.id="shipper-primary-"+(++unique);const cap=el("label","form-check-label","Khu vực chính");cap.htmlFor=radio.id;
      const remove=button("Bỏ",()=>{row.remove();add.disabled=rows.children.length>=100;},"btn btn-outline-secondary btn-sm");row.append(area,actions(radio,cap),remove);rows.append(row);add.disabled=rows.children.length>=100;
    }
    for(const a of existing||[])addRow(a);
    return()=>{const picked=[...rows.children].map(row=>({areaId:Number(row.querySelector("select").value),isPrimary:row.querySelector("input").checked}));if(picked.some(a=>!Number.isSafeInteger(a.areaId)||a.areaId<=0))invalid(fields,"areas","Hãy chọn khu vực cho mỗi dòng hoặc bỏ dòng trống.");if(new Set(picked.map(a=>a.areaId)).size!==picked.length)invalid(fields,"areas","Không được nhập trùng khu vực.");return picked;};
  }
  async function catalog(s,type,signal){const data=await read(s,"/api/v1/catalogs?"+query({type,activeOnly:type==="AREAS"?"true":"false"}),signal);const key=type.toLowerCase();if(!Array.isArray(data[key]))throw new Error("Không đọc được danh mục "+key+".");return data[key];}
  function picker(s,d,form,fields,key,title,path,base,branches,preferred){
    const panel=el("div","col-12 shipper-picker"),tools=el("div","shipper-picker-filters"),search=el("input","form-control");search.placeholder="Tìm kiếm";search.maxLength=key==="accountId"?150:100;search.setAttribute("aria-label","Tìm "+title.toLowerCase());
    if(preferred)search.value=preferred.code;
    const apply=button("Tìm",()=>{page=1;load();},"btn btn-outline-orange");tools.append(search);let branch;
    if(branches){branch=select([["","Tất cả bưu cục"],...branches.filter(b=>b.isActive).map(b=>[b.id,b.name])],s.filters?.branchId||"");branch.setAttribute("aria-label","Bưu cục của tài khoản");tools.append(branch);branch.addEventListener("change",()=>{page=1;load();});}
    tools.append(apply);const list=select([["","Đang tải…"]]);list.disabled=true;const label=el("label","form-label",title+" *");list.id="shipper-picker-"+(++unique);list.name=key;label.htmlFor=list.id;
    const error=el("div","invalid-feedback"),feedback=el("div"),pager=el("div","shipper-pagination"),preview=el("p","text-secondary mt-2 mb-0");list.required=true;error.id=list.id+"-error";list.setAttribute("aria-describedby",error.id);fields[key]={control:list,error};
    panel.append(tools,label,list,error,preview,feedback,pager);form.append(panel);
    let page=1,epoch=0,records=[],pending=null;
    panel.prepend(el("p","small text-secondary",key==="accountId"?"Chỉ tài khoản SHIPPER còn hoạt động, có bưu cục hợp lệ và chưa có hồ sơ được chọn.":"Chỉ xe đang hoạt động, sẵn sàng và không có phân công/nhiệm vụ được chọn."));
    search.addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();page=1;load();}});list.addEventListener("change",()=>{const record=records.find(r=>String(r.id)===list.value);preview.textContent=record?(key==="accountId"?record.fullName+" · "+(record.phone||"—")+" · "+record.branchName:record.licensePlate+" · "+record.vehicleType+" · "+record.maxWeightKg+" kg"):"";});
    async function load(){pending?.abort();pending=new AbortController();const seq=++epoch,signal=AbortSignal.any([d.signal,pending.signal]);list.disabled=true;list.replaceChildren();const loading=el("option","","Đang tải…");loading.value="";list.append(loading);preview.textContent="";alert(feedback,"");pager.replaceChildren();
      try{const url=path+"?"+query({...base,page,pageSize:10,keyword:search.value.trim(),branchId:branch?.value});const data=window.ApiClient.validatePage(await read(s,url,signal),url,["id"]);if(!alive(s)||d.closed||d.busy||d.writeUnknown||signal.aborted||seq!==epoch)return;records=data.items;list.replaceChildren();const none=el("option","",records.length?"Chọn "+title.toLowerCase():"Không có kết quả đủ điều kiện");none.value="";list.append(none);for(const r of records){const opt=el("option","",key==="accountId"?r.username+" · "+r.fullName+" · "+r.branchName:r.licensePlate+" · "+r.code);opt.value=r.id;list.append(opt);}list.disabled=!records.length;if(preferred&&records.some(r=>r.id===preferred.id)){list.value=String(preferred.id);list.dispatchEvent(new Event("change"));preferred=null;}pagination(pager,data,()=>{page--;load();},()=>{page++;load();});}
      catch(error){if(!signal.aborted&&seq===epoch&&!d.closed)failure(s,feedback,error,load);}
    }
    load();return()=>{if(list.disabled||!records.some(r=>String(r.id)===list.value)){invalid(fields,key,"Hãy chọn một kết quả đủ điều kiện đã tải.");return null;}return Number(list.value);};
  }
  async function editor(s,id){
    if(!can(s,"TAIKHOAN_QUANLY"))return;const d=dialog(s,id?"Sửa nhân viên":"Thêm nhân viên");if(!d)return;
    async function load(){try{
      const [record,areas,branches]=await Promise.all([id?read(s,"/api/v1/shippers?id="+id,d.signal):Promise.resolve(null),catalog(s,"AREAS",d.signal),id?Promise.resolve([]):catalog(s,"BRANCHES",d.signal)]);if(!alive(s)||d.closed)return;
      const openedVersion=record?.version;
      d.body.replaceChildren();const form=el("form","row g-3"),fields={};d.body.append(form);let getAccount;
      if(record)form.append(el("p","col-12 text-secondary",record.employeeCode+" · "+record.fullName+" · "+record.username+" · "+record.branchName));
      else getAccount=picker(s,d,form,fields,"accountId","Tài khoản SHIPPER","/api/v1/accounts",{eligibleForShipper:true},branches);
      field(form,fields,"identityNumber","CCCD (12 chữ số)",record?.identityNumber,{max:12});
      field(form,fields,"licenseNumber","Số bằng lái",record?.licenseNumber,{max:50});
      field(form,fields,"licenseExpiresAt","Ngày hết hạn bằng lái",record?.licenseExpiresAt?.slice(0,10),{type:"date"});
      const getAreas=areasForm(form,fields,areas,record?.areas);
      form.append(el("p","col-12 small text-secondary mb-0",record?"Tài khoản và bưu cục được quản lý ở trang Tài khoản. Trạng thái làm việc do tài khoản nhân viên cập nhật.":"Mã nhân viên được hệ thống sinh tự động. Bưu cục, họ tên và điện thoại lấy từ tài khoản đã chọn."));
      if(s.user.role==="ADMIN")form.append(link("Quản lý tài khoản",Router.href("accounts")));
      save(s,d,form,fields,"/api/v1/shippers"+(id?"/"+id:""),id?"PUT":"POST",()=>{
        const identityNumber=fields.identityNumber.control.value.trim(),licenseNumber=fields.licenseNumber.control.value.trim(),licenseExpiresAt=fields.licenseExpiresAt.control.value;
        if(identityNumber&&!/^[0-9]{12}$/.test(identityNumber))invalid(fields,"identityNumber","CCCD phải có 12 chữ số.");
        if(licenseNumber&&!/^[A-Za-z0-9 -]+$/.test(licenseNumber))invalid(fields,"licenseNumber","Số bằng lái chỉ gồm chữ Latin, số, khoảng trắng hoặc dấu gạch ngang.");
        if(licenseExpiresAt&&!licenseNumber)invalid(fields,"licenseNumber","Phải nhập số bằng lái khi nhập ngày hết hạn.");
        if(invalidLicenseUpdate(record,licenseNumber,licenseExpiresAt,record?.isActive))invalid(fields,"licenseExpiresAt","Bằng lái mới hoặc thay đổi không được có ngày hết hạn trong quá khứ (theo ngày Việt Nam).");
        const payload={identityNumber:identityNumber||null,licenseNumber:licenseNumber||null,licenseExpiresAt:licenseExpiresAt||null,areas:getAreas()};
        if(record){payload.isActive=record.isActive;payload.expectedVersion=openedVersion;}else payload.accountId=getAccount();return payload;
      });
    }catch(error){if(!d.closed)failure(s,d.body,error,load);}}await load();
  }
  async function toggle(s,id){
    if(!can(s,"TAIKHOAN_QUANLY"))return;const d=dialog(s,"Trạng thái nhân viên");if(!d)return;
    async function load(){try{
      const c=await read(s,"/api/v1/shippers?id="+id,d.signal);if(!alive(s)||d.closed)return;
      const openedVersion=c.version;
      const action=c.isActive?"Ngừng hoạt động":"Kích hoạt lại";d.heading.textContent=action+" nhân viên";
      const form=el("form","row g-3"),feedback=el("div","col-12");
      form.append(el("p","col-12 fw-semibold",c.employeeCode+" · "+c.fullName+" · "+c.username),el("p","col-12 text-secondary",c.isActive?"Xác nhận ngừng hoạt động hồ sơ nhân viên này. Trạng thái làm việc sẽ chuyển về Ngoại tuyến; tài khoản liên kết giữ nguyên. Nhân viên còn nhiệm vụ sẽ bị từ chối.":"Xác nhận kích hoạt lại hồ sơ nhân viên này. Tài khoản, bưu cục và bằng lái phải đủ điều kiện."),feedback);
      save(s,d,form,{},"/api/v1/shippers/"+id,"PUT",()=>{
        alert(feedback,"");
        const payload={expectedVersion:openedVersion,identityNumber:c.identityNumber,licenseNumber:c.licenseNumber,licenseExpiresAt:c.licenseExpiresAt?.slice(0,10)||null,isActive:!c.isActive,areas:c.areas.map(a=>({areaId:a.id,isPrimary:a.isPrimary}))};
        if(invalidLicenseUpdate(c,payload.licenseNumber||"",payload.licenseExpiresAt,payload.isActive)){
          alert(feedback,"Bằng lái đã hết hạn theo ngày Việt Nam. Hãy cập nhật thông tin bằng lái hợp lệ trước khi kích hoạt lại.");return null;
        }
        return payload;
      },"Xác nhận "+action.toLowerCase());d.body.replaceChildren(form);
    }catch(error){if(!d.closed)failure(s,d.body,error,load);}}await load();
  }
  async function vehicleEditor(s,id,preferredVehicle){
    if(!manageVehicle(s))return;const d=dialog(s,"Quản lý phương tiện");if(!d)return;
    d.node.classList.add("vehicle-assignment-dialog");
    async function load(){try{const [c,typeCatalog]=await Promise.all([read(s,"/api/v1/shippers?id="+id,d.signal),read(s,"/api/v1/vehicles/types",d.signal)]);if(!alive(s)||d.closed)return;
      if(!Array.isArray(typeCatalog.items)||typeCatalog.items.some(t=>!t.code||!t.name))throw new Error("Không đọc được danh mục loại phương tiện.");
      d.body.replaceChildren();const form=el("form","row g-3"),fields={};d.body.append(form);form.append(el("p","col-12 fw-semibold",c.employeeCode+" · "+c.fullName),el("p","col-12 text-secondary","Phương tiện hiện tại: "+vehicleText(c.currentVehicle)));
      const mode=field(form,fields,"mode","Thao tác","assign",{items:[["assign",c.currentVehicle?"Đổi phương tiện":"Gán phương tiện"],...(c.currentVehicle?[["remove","Gỡ phương tiện hiện tại"]]:[])]});
      const getVehicle=vehiclePicker(s,d,form,fields,c,typeCatalog.items,preferredVehicle);
      field(form,fields,"notes","Ghi chú *","",{required:true,max:500,multiline:true,full:true});
      form.append(link("Trang Phương tiện",Router.href("vehicles")),el("p","col-12 small text-secondary","Nhân viên hoặc xe còn nhiệm vụ/chuyến chưa kết thúc sẽ không được đổi hoặc gỡ xe."));
      mode.addEventListener("change",()=>{fields.vehicleId.control.required=mode.value!=="remove";fields.vehicleId.control.closest(".shipper-picker").hidden=mode.value==="remove";});
      save(s,d,form,fields,"/api/v1/shippers/"+id+"/vehicle","PUT",()=>({vehicleId:mode.value==="remove"?null:getVehicle(),expectedAssignmentId:c.currentVehicle?.assignmentId??null,notes:fields.notes.control.value.trim()}),"Xác nhận");
    }catch(error){if(!d.closed)failure(s,d.body,error,load);}}await load();
  }
  function vehiclePicker(s,d,form,fields,shipper,types,preferred){
    const panel=el("section","col-12 shipper-picker vehicle-choice");
    panel.tabIndex=-1;
    const heading=el("h3","h6","Chọn phương tiện");
    const scope=el("p","small text-secondary","Bưu cục nhận xe: "+shipper.branchName+". Danh sách gồm xe đang gán tại bưu cục và nguồn xe chưa gán dùng chung. Chỉ chọn được xe đủ điều kiện.");
    const selection=el("div","vehicle-choice-selected");selection.hidden=true;selection.setAttribute("aria-live","polite");
    const value=el("input");value.type="hidden";value.name="vehicleId";value.required=true;
    const error=el("div","invalid-feedback d-block");fields.vehicleId={control:value,error};
    const tools=el("div","vehicle-choice-filters"),filterFields={};
    const type=field(tools,filterFields,"vehicleType","Loại phương tiện","",{items:[["","Tất cả"],...types.map(t=>[t.code,t.name])]});
    const keyword=field(tools,filterFields,"vehicleKeyword","Biển số hoặc mã phương tiện","",{max:100});keyword.placeholder="Nhập biển số hoặc mã phương tiện";
    const apply=button("Tìm kiếm",()=>applyFilters(),"btn btn-orange");
    const reset=button("Xóa bộ lọc",()=>{type.value="";keyword.value="";applyFilters();},"btn btn-outline-orange");
    tools.append(actions(apply,reset));
    const feedback=el("div","vehicle-choice-feedback"),results=el("div","vehicle-choice-results"),pager=el("div","shipper-pagination vehicle-choice-pagination");
    panel.append(heading,scope,selection,value,error,tools,feedback,results,pager);form.append(panel);
    let page=1,sequence=0,pending,selected=null,selectionRevision=0,contextInvalid=false,reloadWhenIdle=false;
    let applied={keyword:"",vehicleType:""};
    const names=new Map(types.map(t=>[t.code,t.name]));
    const typeName=row=>names.get(row.vehicleType)||"Loại xe khác ("+row.vehicleType+")";
    const weightText=row=>new Intl.NumberFormat("vi-VN").format(row.maxWeightKg)+" kg";
    function setSelected(row){
      if(row?.canSelect!==true&&row)return;
      selected=row;selectionRevision++;value.value=row?String(row.id):"";
      value.classList.remove("is-invalid");value.removeAttribute("aria-invalid");error.textContent="";
      selection.hidden=!row;selection.replaceChildren();
      if(row){
        const details=el("div");details.append(el("strong","d-block","Xe đã chọn"),el("p","mb-0",row.code+" · "+row.licensePlate+" · "+typeName(row)+" · "+weightText(row)));
        selection.append(details,button("Đổi lựa chọn",()=>{setSelected(null);keyword.focus();},"btn btn-outline-orange btn-sm"));
      }
      for(const node of results.querySelectorAll("[data-choose-vehicle]")){
        const chosen=String(row?.id)===node.dataset.chooseVehicle;node.disabled=chosen||node.dataset.selectable!=="true";node.textContent=chosen?"Đã chọn":"Chọn";
        node.closest(".vehicle-choice-row").classList.toggle("is-selected",chosen);
      }
    }
    function applyFilters(){
      if(d.busy||d.closed||d.writeUnknown)return;
      if(!keyword.checkValidity()){keyword.reportValidity();return;}
      applied={keyword:keyword.value.trim(),vehicleType:type.value};page=1;load();
    }
    type.addEventListener("change",applyFilters);
    keyword.addEventListener("keydown",event=>{if(event.key==="Enter"){event.preventDefault();applyFilters();}});
    function checkScope(data){
      if(data.selectionShipperId!==shipper.id||data.selectionBranchId!==shipper.branchId){
        contextInvalid=true;setSelected(null);
        throw new Error("Shipper hoặc bưu cục đã thay đổi. Hãy đóng và mở lại form để chọn xe phù hợp.");
      }
    }
    async function requestPage(params,signal){
      const url="/api/v1/vehicles?"+query({assignableOnly:true,includeUnavailable:true,forShipperId:shipper.id,branchId:shipper.branchId,pageSize:10,...params});
      const data=window.ApiClient.validatePage(await read(s,url,signal),url,["id"]);
      if(!Number.isSafeInteger(data.eligibleTotalItems)||data.eligibleTotalItems<0||!Number.isSafeInteger(data.scopedTotalItems)||data.scopedTotalItems<data.totalItems||data.eligibleTotalItems>data.scopedTotalItems||data.items.some(row=>typeof row.canSelect!=="boolean"||(!row.canSelect&&(typeof row.unavailableReason!=="string"||!row.unavailableReason.trim()))))throw new Error("API chưa trả đủ thông tin xe có thể gán.");
      return data;
    }
    async function load(){
      if(d.busy||d.closed||d.writeUnknown)return;
      reloadWhenIdle=false;
      pending?.abort();pending=new AbortController();const signal=AbortSignal.any([d.signal,pending.signal]),seq=++sequence;
      results.setAttribute("aria-busy","true");results.replaceChildren(el("p","shipper-empty","Đang tải danh sách phương tiện…"));pager.replaceChildren();alert(feedback,"");
      try{
        const data=await requestPage({page,...applied},signal);
        if(!alive(s)||d.closed||d.writeUnknown||signal.aborted||seq!==sequence)return;
        if(d.busy){reloadWhenIdle=true;return;}
        checkScope(data);
        if(selected&&(data.eligibleTotalItems===0||data.items.some(row=>row.id===selected.id&&!row.canSelect)))setSelected(null);
        if(data.scopedTotalItems>0&&data.eligibleTotalItems===0)alert(feedback,"Có phương tiện nhưng không có xe đủ điều kiện để gán. Xem lý do tại từng xe.","warning");
        const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize));if(page>pages){page=pages;return load();}
        if(!data.items.length){
          results.replaceChildren(el("p","shipper-empty",data.scopedTotalItems===0?"Không có phương tiện trong bưu cục và nguồn xe chưa gán dùng chung.":"Không có xe khớp bộ lọc. Hãy đổi loại xe, biển số hoặc mã phương tiện."));
        }else{
          const list=el("ul","vehicle-choice-list");
          for(const row of data.items){
            const item=el("li","vehicle-choice-row"),details=el("dl","vehicle-choice-specs");
            item.classList.toggle("is-unavailable",!row.canSelect);item.classList.toggle("is-selected",row.id===selected?.id);
            for(const [label,content] of [["Mã phương tiện",row.code],["Biển số",row.licensePlate],["Loại xe",typeName(row)],["Tải trọng",weightText(row)],["Tình trạng",(vehicleStates[row.status]||row.status)+(row.isActive?"":" · Ngừng hoạt động")],["Khả năng sử dụng",row.canSelect?"Có thể gán":row.unavailableReason]]){
              const pair=el("div");pair.append(el("dt","",label),el("dd","",content));details.append(pair);
            }
            const choose=button("Chọn",()=>{if(!d.busy&&row.canSelect)setSelected(row);},"btn btn-outline-orange btn-sm");choose.dataset.chooseVehicle=String(row.id);choose.dataset.selectable=String(row.canSelect);choose.disabled=!row.canSelect;
            if(!row.canSelect)choose.title=row.unavailableReason;
            choose.setAttribute("aria-label","Chọn xe "+row.licensePlate+", mã "+row.code);
            if(row.id===selected?.id){choose.disabled=true;choose.textContent="Đã chọn";}
            item.append(details,choose);list.append(item);
          }
          results.replaceChildren(list);
        }
        pagination(pager,data,()=>{page--;load();},()=>{page++;load();});
      }catch(error){
        if(!signal.aborted&&seq===sequence&&!d.closed&&alive(s)&&!error.sessionExpired){
          if([403,404,409].includes(error.status)){setSelected(null);contextInvalid=true;}
          results.replaceChildren();alert(feedback,"Không tải được danh sách xe. "+error.message);
          if(!contextInvalid&&!error.sessionExpired&&![403,404].includes(error.status))feedback.append(button("Thử lại",load,"btn btn-outline-orange"));
        }
      }finally{if(seq===sequence)results.setAttribute("aria-busy","false");}
    }
    async function initialize(){
      await load();
      if(!preferred||d.closed||d.busy||d.writeUnknown||contextInvalid)return;
      const revision=selectionRevision;
      try{
        const data=await requestPage({page:1,keyword:preferred.code},d.signal);
        if(!alive(s)||d.closed||d.busy||d.writeUnknown||revision!==selectionRevision)return;
        checkScope(data);const row=data.items.find(item=>item.id===preferred.id);
        if(row?.canSelect)setSelected(row);else alert(feedback,"Xe vừa chọn không còn đủ điều kiện. "+(row?.unavailableReason||"Hãy chọn xe khác."),"warning");
      }catch(error){if(!d.closed&&error.name!=="AbortError"&&!error.sessionExpired)alert(feedback,"Chưa xác minh được xe vừa chọn. "+error.message);}
    }
    initialize();
    d.onSaveError=error=>{if([409,422].includes(error.status)){setSelected(null);load();}};
    d.onIdle=()=>{if(reloadWhenIdle)load();};
    return()=>{
      if(!selected||contextInvalid){invalid(fields,"vehicleId","Hãy chọn một xe đủ điều kiện trong danh sách.");panel.focus();return null;}
      return selected.id;
    };
  }
  function pagination(box,data,previous,next){const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize));const prev=button("‹ Trước",previous),nxt=button("Sau ›",next);prev.disabled=data.page<=1;nxt.disabled=data.page>=pages;box.replaceChildren(el("span","text-secondary",data.totalItems+" kết quả · Trang "+data.page+" / "+pages),prev,nxt);}
  function rowActions(s,c){const n=actions(link("Xem chi tiết",Router.href("shipper-detail",{id:c.id},s.filters||s.route.query)));if(can(s,"TAIKHOAN_QUANLY"))n.append(button("Sửa",()=>editor(s,c.id)),button(c.isActive?"Ngừng hoạt động":"Kích hoạt lại",()=>toggle(s,c.id)));if(manageVehicle(s))n.append(button("Quản lý phương tiện",()=>vehicleEditor(s,c.id)));return n;}
  async function list(s){
    s.listAbort?.abort();s.listAbort=new AbortController();const signal=AbortSignal.any([s.abort.signal,s.listAbort.signal]);Router.updateQuery(s.filters,s.route);s.route=Router.current()||s.route;
    s.results.replaceChildren(el("p","shipper-empty","Đang tải nhân viên…"));s.pager.replaceChildren();alert(s.feedback,"");
    try{const path="/api/v1/shippers?"+query(s.filters),data=window.ApiClient.validatePage(await read(s,path,signal),path,["id"]);if(!alive(s)||signal.aborted)return;const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize));if(data.page>pages){s.filters.page=pages;return list(s);}
      s.results.replaceChildren(data.items.length?table(["Mã nhân viên","Họ tên","Điện thoại","Bưu cục","Phương tiện hiện tại","Trạng thái làm việc","Hoạt động nhân viên","Trạng thái tài khoản","Thao tác"],data.items.map(c=>[c.employeeCode,c.fullName,c.phone,c.branchName,vehicleText(c.currentVehicle),working(c.availability),badge(c.isActive,c.isActive?"Đang hoạt động":"Ngừng hoạt động"),accountStates[c.accountStatus]||c.accountStatus,rowActions(s,c)])):el("p","shipper-empty","Không có nhân viên phù hợp với bộ lọc."));
      pagination(s.pager,data,()=>{s.filters.page--;list(s);},()=>{s.filters.page++;list(s);});const size=select([...new Set([10,20,50,100,data.pageSize])].sort((a,b)=>a-b).map(n=>[n,n+" dòng"]),data.pageSize);size.setAttribute("aria-label","Số dòng mỗi trang");size.addEventListener("change",()=>{s.filters.pageSize=Number(size.value);s.filters.page=1;list(s);});s.pager.append(size);if(s.message){alert(s.feedback,s.message,"success");s.message="";}
    }catch(error){if(!signal.aborted){s.results.replaceChildren();failure(s,s.feedback,error,()=>list(s));}}
  }
  async function mountList(s){
    const q=s.route.query;s.filters={page:q.page||1,pageSize:q.pageSize||10,keyword:q.keyword||"",branchId:q.branchId||"",isActive:q.isActive||"",availability:q.availability||""};
    const toolbar=actions();toolbar.classList.add("shipper-toolbar");if(can(s,"TAIKHOAN_QUANLY"))toolbar.append(button("Thêm nhân viên",()=>editor(s),"btn btn-orange"));toolbar.append(button("Làm mới",()=>list(s),"btn btn-outline-orange"));
    const filter=el("form","row g-3 shipper-filters"),fields={};field(filter,fields,"keyword","Tìm mã, họ tên hoặc điện thoại",s.filters.keyword,{max:150});const branch=field(filter,fields,"branchId","Bưu cục",s.filters.branchId,{items:[["","Đang tải bưu cục…"]]});branch.disabled=true;
    field(filter,fields,"isActive","Hoạt động nhân viên",s.filters.isActive,{items:[["","Tất cả trạng thái"],["true","Đang hoạt động"],["false","Ngừng hoạt động"]]});field(filter,fields,"availability","Trạng thái làm việc",s.filters.availability,{items:[["","Tất cả trạng thái"],...Object.entries(availability)]});
    const submit=button("Tìm kiếm",null,"btn btn-outline-orange");submit.type="submit";filter.append(actions(submit));filter.addEventListener("submit",e=>{e.preventDefault();for(const [key,f]of Object.entries(fields))s.filters[key]=f.control.value.trim();s.filters.page=1;list(s);});for(const key of ["branchId","isActive","availability"])fields[key].control.addEventListener("change",()=>filter.requestSubmit());
    s.feedback=el("div");s.results=el("div","shipper-results");s.pager=el("div","shipper-pagination");s.root.append(toolbar,filter,s.feedback,s.results,s.pager);list(s);
    const catalogBox=el("div");filter.append(catalogBox);
    async function loadBranches(){try{const branches=await catalog(s,"BRANCHES");if(!alive(s))return;const n=select([["","Tất cả bưu cục trong phạm vi"],...branches.map(b=>[b.id,b.name+(b.isActive?"":" (ngừng hoạt động)")])],s.filters.branchId);branch.replaceChildren(...n.children);branch.value=String(s.filters.branchId);branch.disabled=false;alert(catalogBox,"");}catch(error){failure(s,catalogBox,error,loadBranches);}}loadBranches();
  }
  function related(s,c,kind){
    const panel=el("section","shipper-related"),isTrips=kind==="trips",heading=el("h3","h6",isTrips?"Chuyến giao":"Phân công đang hoạt động");panel.append(heading);
    const body=el("div"),pager=el("div","shipper-pagination");let page=1,status=isTrips?"IN_PROGRESS":"",pending;
    if(isTrips){const dropdown=select([["","Tất cả chuyến"],...Object.entries(tripStates)],status);dropdown.setAttribute("aria-label","Trạng thái chuyến giao");dropdown.addEventListener("change",()=>{status=dropdown.value;page=1;load();});panel.append(dropdown);}
    panel.append(body,pager);
    async function load(){pending?.abort();pending=new AbortController();const signal=AbortSignal.any([s.abort.signal,pending.signal]);body.replaceChildren(el("p","text-secondary","Đang tải…"));pager.replaceChildren();
      try{const path=(isTrips?"/api/v1/trips":"/api/v1/dispatch/assignments")+"?"+query({shipperId:c.id,status,page,pageSize:10,activeOnly:isTrips?undefined:true});const data=window.ApiClient.validatePage(await read(s,path,signal),path,["id"]);if(!alive(s)||signal.aborted||!panel.isConnected)return;
        body.replaceChildren(data.items.length?table(isTrips?["Mã chuyến","Bưu cục","Xe","Trạng thái","Số đơn"]:["Mã đơn","Mã vận đơn","Bưu cục","Xe","Trạng thái","Chuyến"],data.items.map(r=>isTrips?[r.tripCode,r.branchName,r.licensePlate,tripStates[r.status]||r.status,r.orderCount]:[r.orderCode,r.trackingNumber,r.branchName,r.licensePlate,assignmentStates[r.assignmentStatus]||r.assignmentStatus,r.tripId])):el("p","shipper-empty",isTrips?"Không có chuyến phù hợp.":"Không có phân công đang hoạt động."));pagination(pager,data,()=>{page--;load();},()=>{page++;load();});
      }catch(error){if(!signal.aborted&&panel.isConnected)failure(s,body,error,load);}}
    queueMicrotask(load);return panel;
  }
  async function detail(s){
    const epoch=++s.detailEpoch;s.root.replaceChildren(el("p","shipper-empty","Đang tải nhân viên…"));const back=link("‹ Quay về danh sách",Router.href("couriers",{},s.route.query));
    try{const c=await read(s,"/api/v1/shippers?id="+s.route.params.id);if(!alive(s)||epoch!==s.detailEpoch)return;if(c.id!==s.route.params.id||!Array.isArray(c.areas))throw new Error("API hồ sơ nhân viên trả dữ liệu không hợp lệ.");const tools=actions(back,button("Làm mới",()=>detail(s),"btn btn-outline-orange"));if(can(s,"TAIKHOAN_QUANLY"))tools.append(button("Sửa",()=>editor(s,c.id)),button(c.isActive?"Ngừng hoạt động":"Kích hoạt lại",()=>toggle(s,c.id)));if(manageVehicle(s))tools.append(button("Quản lý phương tiện",()=>vehicleEditor(s,c.id),"btn btn-orange"));s.root.replaceChildren(tools);const box=el("div");s.root.append(box);if(s.message){alert(box,s.message,"success");s.message="";}
      s.root.append(summary([["Mã nhân viên",c.employeeCode],["Họ tên",c.fullName],["Điện thoại",c.phone],["Email",c.email],["Bưu cục",c.branchName],["Tài khoản liên kết",c.username+" · #"+c.accountId],["Vai trò tài khoản",c.accountRole],["Trạng thái tài khoản",accountStates[c.accountStatus]||c.accountStatus],["Hoạt động nhân viên",c.isActive?"Đang hoạt động":"Ngừng hoạt động"],["Trạng thái làm việc",availability[c.availability]||c.availability],["CCCD",c.identityNumber],["Số bằng lái",c.licenseNumber],["Ngày hết hạn bằng lái",c.licenseExpiresAt?.slice(0,10)],["Phương tiện hiện tại",vehicleText(c.currentVehicle)],["Trạng thái phương tiện",c.currentVehicle?vehicleStates[c.currentVehicle.status]:null],["Cập nhật vị trí",date(c.locationUpdatedAt)],["Vị trí gần nhất",c.latitude==null?null:c.latitude+", "+c.longitude],["Số phân công đang hoạt động",c.activeAssignmentCount]]));
      const regions=el("section","shipper-related");regions.append(el("h3","h6","Khu vực phụ trách"));regions.append(c.areas.length?table(["Mã khu vực","Tên khu vực","Khu vực chính","Hoạt động"],c.areas.map(a=>[a.code,a.name,a.isPrimary?"Chính":"—",a.isActive?"Đang hoạt động":"Ngừng hoạt động"])):el("p","text-secondary","Chưa có khu vực phụ trách."));s.root.append(regions);
      if(can(s,"DIEUPHOI_GIAMSAT"))s.root.append(related(s,c,"assignments"),related(s,c,"trips"));
    }catch(error){if(alive(s)&&epoch===s.detailEpoch){s.root.replaceChildren(back);const box=el("div");s.root.append(box);failure(s,box,error,()=>detail(s));}}
  }
  function refresh(s){if(!alive(s))return;if(s.externalRefresh)return s.externalRefresh();return s.route.mode==="detail"?detail(s):list(s);}
  function destroy(){if(!active)return;active.dialog?.close();active.abort.abort();active.listAbort?.abort();active=null;}
  function mount(container,user,route,context){destroy();const root=el("div","shippers-page");container.replaceChildren(root);const s={root,user,route,permissions:context.permissions,abort:new AbortController(),detailEpoch:0};active=s;context.signal?.addEventListener("abort",()=>{s.abort.abort();s.dialog?.close();},{once:true,signal:s.abort.signal});if(!can(s,"TAIKHOAN_XEM")){alert(root,"Bạn không có quyền xem nhân viên giao hàng.");return;}if(route.mode==="detail")detail(s);else mountList(s);}
  window.ShippersPage=Object.freeze({mount,destroy});
  // Both fleet pages use this single editor and PUT workflow. External callers
  // supply their page state, lifetime predicate and refresh callback.
  window.VehicleLink=Object.freeze({permitted:manageVehicle,openForShipper:vehicleEditor});
}());

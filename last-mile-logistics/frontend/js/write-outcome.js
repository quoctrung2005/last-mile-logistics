"use strict";
(function () {
  const message="Chưa xác định được kết quả lưu. Hãy kiểm tra dữ liệu trước khi thực hiện lại.";
  const storageKey="tvd.unknownWrites";
  let pending;
  try{const saved=JSON.parse(sessionStorage.getItem(storageKey));pending=new Set(Array.isArray(saved)?saved.filter(x=>typeof x==="string"):[]);}catch{pending=new Set();}
  function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==="object")return Object.fromEntries(Object.keys(value).sort().map(k=>[k,/password|token|secret|authorization/i.test(k)?"[private]":canonical(value[k])]));return value;}
  function assertCanSend(owner,{path,payload,body,method="POST"}){
    // A tab-local replay guard, not a backend idempotency key. Store only a
    // fingerprint; passwords, notes and payment payloads never enter storage.
    const text=JSON.stringify([window.ApiClient.getSession?.()?.user?.accountId||0,method,path,body??canonical(payload)]);
    let a=2166136261,b=5381;for(let i=0;i<text.length;i++){a=Math.imul(a^text.charCodeAt(i),16777619);b=Math.imul(b,33)^text.charCodeAt(i);}
    owner.writeAttempt=(a>>>0).toString(16)+":"+(b>>>0).toString(16);
    if(owner.writeUnknown||pending.has(owner.writeAttempt))throw Object.assign(new Error(message),{resultUnknown:true});
  }
  const query=values=>new URLSearchParams(Object.entries(values).filter(([,v])=>v!=null&&v!=="")).toString();
  // Only existing read endpoints. These are evidence for review, never a claim
  // that an in-flight/committed write failed or permission to replay it.
  function reviewPaths(path,p={}) {
    let m;
    if((m=path.match(/^\/api\/v1\/customers(?:\/(\d+))?/)))return [m[1]?`/api/v1/customers/${m[1]}?includeInactiveAddresses=true`:"/api/v1/customers?"+query({keyword:p.phone||p.fullName,status:"ALL",pageSize:100})];
    if((m=path.match(/^\/api\/v1\/(accounts|shippers)(?:\/(\d+))?/)))return [`/api/v1/${m[1]}?`+query(m[2]?{id:m[2]}:{keyword:p.username,activeOnly:false,pageSize:100})];
    if(path==="/api/v1/vehicles")return [path+"?"+query(p.id?{id:p.id}:{keyword:p.licensePlate,pageSize:100})];
    if((m=path.match(/^\/api\/v1\/cod\/(deposits|reconciliations)(?:\/(\d+))?/)))return [m[2]?(m[1]==="deposits"?`/api/v1/cod/deposits/${m[2]}`:`/api/v1/cod/reconciliations?id=${m[2]}`):`/api/v1/cod/${m[1]}?`+query({branchId:p.branchId,shipperId:p.shipperId,pageSize:100})];
    if(path==="/api/v1/catalogs")return [path+"?"+query({type:p.type})];
    if(path==="/api/v1/roles")return [path+"?"+query(p.id?{id:p.id}:{keyword:p.code})];
    if(path==="/api/v1/shipping-fees/rules")return [path+"?"+query({id:p.id,pageSize:100})];
    if((m=path.match(/^\/api\/v1\/trips(?:\/(\d+))?/)))return ["/api/v1/trips?"+query(m[1]?{id:m[1]}:{branchId:p.branchId,pageSize:100})];
    if(path.startsWith("/api/v1/dispatch/assignments"))return ["/api/v1/dispatch/assignments?"+query({orderId:p.orderId,pageSize:100})];
    if(path.startsWith("/api/v1/dispatch/plans"))return p.orderIds?.length?["/api/v1/dispatch/orders?"+query({ids:p.orderIds.join(","),pageSize:100})]:["/api/v1/trips?pageSize=100"];
    return [];
  }
  const labels={accountId:"ID t?i kho?n",linkedShipperId:"ID h? s? shipper",branchId:"ID b?u c?c",warehouseId:"ID kho",areaId:"ID khu v?c",roleId:"ID vai tr?",allocatedAmount:"Ti?n ph?n b?",collectedAmount:"Th?c thu",depositedAmount:"?? n?p",pendingDepositAmount:"Ch? x?c nh?n",remainingAmount:"C?n ph?i n?p",availableForDeposit:"C?n c? th? n?p",collectionStatus:"Tr?ng th?i kho?n thu",id:"ID",customerCode:"Mã khách hàng",fullName:"Họ tên",phone:"Điện thoại",email:"Email",type:"Loại",isActive:"Đang sử dụng",address:"Địa chỉ",label:"Nhãn",contactName:"Người liên hệ",isDefault:"Mặc định",latitude:"Vĩ độ",longitude:"Kinh độ",areaName:"Khu vực",username:"Tên đăng nhập",roleName:"Vai trò",branchName:"Bưu cục",status:"Trạng thái",employeeCode:"Mã nhân viên",identityNumber:"CCCD",licenseNumber:"Số bằng lái",licenseExpiresAt:"Hết hạn bằng lái",licensePlate:"Biển số",vehicleId:"ID xe",assignmentId:"ID phân công",depositCode:"Mã phiếu nộp",shipperName:"Shipper",amount:"Số tiền",amountExact:"Số tiền",method:"Phương thức",externalReference:"Tham chiếu",notes:"Ghi chú",submittedAt:"Ngày nộp",confirmedAt:"Ngày xác nhận",confirmedByName:"Người xác nhận",reconciliationCode:"Mã đối soát",periodFrom:"Từ",periodTo:"Đến",orderCount:"Số đơn",totalExpected:"Tổng phải thu",totalCollected:"Tổng đã thu",totalDeposited:"Tổng đã nộp",orderCode:"Mã đơn",trackingNumber:"Vận đơn",orderId:"ID đơn",tripId:"ID chuyến",tripCode:"Mã chuyến",assignmentStatus:"Trạng thái phân công",orderStatus:"Trạng thái đơn",plannedStartAt:"Xuất phát",code:"Mã",name:"Tên",description:"Mô tả",serviceName:"Dịch vụ",baseFee:"Phí cơ bản",feePerKm:"Phí mỗi km",feePerKg:"Phí mỗi kg",effectiveFrom:"Hiệu lực từ",effectiveTo:"Hiệu lực đến"};
  const groups={locations:"V? tr? kho",items:"Bản ghi",addresses:"Địa chỉ",areas:"Khu vực",currentVehicle:"Xe hiện tại",details:"Chi tiết",allocations:"Phân bổ",orders:"Đơn hàng",branches:"Bưu cục",warehouses:"Kho",services:"Dịch vụ",routes:"Tuyến"};
  function show(host,data,el,depth=0){
    if(!data||typeof data!=="object"||depth>3)return;
    if(Array.isArray(data)){for(const row of data){const card=el("div","border rounded p-2 mb-2");show(card,row,el,depth+1);host.append(card);}return;}
    const list=el("dl");for(const [key,label]of Object.entries(labels))if(Object.hasOwn(data,key)&&data[key]!=null&&typeof data[key]!=="object")list.append(el("dt","",label),el("dd","",typeof data[key]==="boolean"?(data[key]?"Có":"Không"):String(data[key])));host.append(list);
    for(const [key,label]of Object.entries(groups))if(data[key]&&typeof data[key]==="object"){const section=el("details");section.append(el("summary","",label));show(section,data[key],el,depth+1);host.append(section);}
  }
  function freeze(scope){
    scope?.querySelectorAll("input,select,textarea,button").forEach(n=>{
      if(n.dataset.writeReview)return;
      if(n.tagName==="TEXTAREA"||(n.tagName==="INPUT"&&!["checkbox","radio","button","submit"].includes(n.type))){n.disabled=false;n.readOnly=true;}
      else n.disabled=true;
    });
  }
  function restore(states,owner){for(const [n,disabled]of states)n.disabled=disabled;if(owner.writeUnknown)freeze(owner.writeScope||owner.body);}
  function lock(owner,box,error,{path,payload={},scope=owner.body,signal=owner.signal}={}){
    if(error.resultUnknown!==true)return false;
    owner.writeUnknown=true;owner.writeScope=scope;
    if(owner.writeAttempt){pending.add(owner.writeAttempt);try{sessionStorage.setItem(storageKey,JSON.stringify([...pending]));}catch{/* Keep the in-memory guard if browser storage is unavailable. */}}
    const {el,button}=window.LogisticsUI;
    box.replaceChildren(el("p","alert alert-warning",message),el("p","text-secondary","Nội dung nhập được giữ để đối chiếu. Đọc dữ liệu thành công hoặc không tìm thấy bản ghi chưa chứng minh lần lưu trước đã thất bại; thao tác này vẫn bị khóa."));
    const paths=reviewPaths(path,payload),out=el("div");
    if(paths.length){const check=button("Tải lại để kiểm tra",async()=>{
      if(check.disabled||owner.closed||signal?.aborted)return;check.disabled=true;out.replaceChildren();
      try{for(const url of paths){const data=await window.ApiClient.request(url,{signal});if(owner.closed||signal?.aborted)return;show(out,data,el);if(data?.totalItems!=null){out.append(el("p","text-secondary",`Trang ${data.page||1} · ${data.totalItems} bản ghi. Hãy kiểm tra cả các trang còn lại.`));const pages=Math.ceil(data.totalItems/data.pageSize);for(const [label,page]of [["Trang trước",data.page-1],["Trang sau",data.page+1]])if(page>=1&&page<=pages){const nav=button(label,()=>{const u=new URL(url,"http://localhost");u.searchParams.set("page",page);paths[paths.indexOf(url)]=u.pathname+u.search;return check.click();},"btn btn-outline-secondary btn-sm");nav.dataset.writeReview="true";out.append(nav);}}}out.append(el("p","text-secondary","Đã đọc dữ liệu hiện tại để đối chiếu. Kết quả lần lưu trước vẫn cần được xác minh; nút lưu không được mở lại."));}
      catch(next){if(!owner.closed&&!signal?.aborted)out.replaceChildren(el("p","text-danger","Chưa kiểm tra được dữ liệu. "+next.message));}
      finally{check.disabled=false;}
    },"btn btn-outline-orange");check.dataset.writeReview="true";box.append(check);}
    else box.append(el("p","text-secondary","Chưa có API đọc để tra cứu kết quả thao tác này."));
    if(/reset-password|dispatch\/plans/.test(path))box.append(el("p","text-secondary","API đọc hiện có chưa trả kết quả của lần ghi này; cần đối chiếu với quản trị viên trước khi thực hiện lại."));
    box.append(out);freeze(scope);return true;
  }
  window.WriteOutcome=Object.freeze({lock,restore,freeze,reviewPaths,assertCanSend,message});
}());

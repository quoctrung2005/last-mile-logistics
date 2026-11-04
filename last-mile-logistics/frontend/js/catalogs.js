"use strict";
(function () {
  const U=window.AdminUI,R=window.Router,types={AREAS:"Khu vực",SERVICES:"Dịch vụ giao hàng",BRANCHES:"Bưu cục",WAREHOUSES:"Kho",LOCATIONS:"Vị trí lưu kho"};let active=null;
  function destroy(){if(active?.locationChild)window.LocationsPage.destroy();active?.destroy();active=null;}
  const name=(rows,id)=>id==null?"—":rows.find(r=>r.id===id)?.name||"#"+id;
  function editable(s,type){return s.can(type==="SERVICES"?"BANGGIA_QUANLY":"BUUCUC_QUANLY");}
  async function editor(s,type,id){if(!editable(s,type))return;const d=U.dialog(s,(id?"Sửa ":"Thêm ")+types[type].toLocaleLowerCase("vi"));if(!d)return;
    async function load(){try{const data=await s.read("/api/v1/catalogs",d.signal),c=id?data[type.toLowerCase()].find(r=>r.id===id):null;if(id&&!c)throw Error("Danh mục không còn tồn tại. Hãy tải lại.");if(!s.alive()||d.closed)return;const form=U.el("form","row g-3"),f={};U.field(form,f,"code","Mã *",c?.code,{required:true,maxLength:30,pattern:"[A-Z0-9][A-Z0-9_-]*",readonly:!!c});U.field(form,f,"name","Tên *",c?.name,{required:true,maxLength:type==="SERVICES"?100:150});
      function relationship(key,label,rows,current,required=false,disabled=false){return U.field(form,f,key,label,current,{required,disabled,items:[["",required?"Chọn "+label.toLowerCase():"Không có"],...rows.filter(r=>r.id!==id||key!=="parentId").map(r=>[r.id,r.name+(r.isActive?"":" (ngừng sử dụng)"),!r.isActive&&r.id!==current])]});}
      if(type==="AREAS"){relationship("parentId","Khu vực cha",data.areas,c?.parentId);U.field(form,f,"areaType","Loại khu vực *",c?.areaType||"SERVICE_ZONE",{required:true,items:[["CITY","Tỉnh / Thành phố"],["DISTRICT","Quận / Huyện"],["WARD","Phường / Xã"],["SERVICE_ZONE","Vùng phục vụ"]]});}
      if(type==="BRANCHES"){
        relationship("areaId","Khu vực *",data.areas,c?.areaId,true);
        U.field(form,f,"phone","Điện thoại",c?.phone,{maxLength:16,pattern:"\\+?[0-9]{9,15}",type:"tel"});
        U.field(form,f,"email","Email",c?.email,{maxLength:150,type:"email"});
        for(const [key,label,min,max]of [["latitude","Vĩ độ",-90,90],["longitude","Kinh độ",-180,180]])U.field(form,f,key,label,c?.[key],{type:"number",min,max,step:"0.000001"});
        const mapCol=U.el("div","col-12 mt-2");
        mapCol.innerHTML=`<div class="d-flex justify-content-between align-items-center mb-1"><label class="form-label mb-0 fw-semibold" style="font-size:13px;">📍 Chọn vị trí trên bản đồ</label><span class="text-secondary small" style="font-size:11.5px;">Click bản đồ hoặc kéo ghim để tự điền tọa độ</span></div><div class="catalog-map-box" style="height:220px;width:100%;border-radius:8px;border:1.5px solid #CBD5E1;position:relative;"></div>`;
        form.append(mapCol);
        setTimeout(()=>{
          if(d.closed||!window.L)return;
          const box=mapCol.querySelector(".catalog-map-box");
          if(!box)return;
          const initLat=Number(f.latitude?.control?.value)||10.7769;
          const initLng=Number(f.longitude?.control?.value)||106.7009;
          const hasCoord=!!(f.latitude?.control?.value&&f.longitude?.control?.value);
          const map=window.L.map(box).setView([initLat,initLng],hasCoord?15:12);
          window.L.tileLayer("https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&hl=vi",{maxZoom:20,subdomains:["0","1","2","3"],attribution:"&copy; Google Maps"}).addTo(map);
          let marker=hasCoord?window.L.marker([initLat,initLng],{draggable:true}).addTo(map):null;
          const updateInputs=(lat,lng)=>{if(f.latitude?.control)f.latitude.control.value=lat.toFixed(6);if(f.longitude?.control)f.longitude.control.value=lng.toFixed(6);};
          const bindDrag=m=>m.on("dragend",ev=>{const pos=ev.target.getLatLng();updateInputs(pos.lat,pos.lng);});
          if(marker)bindDrag(marker);
          map.on("click",e=>{const {lat,lng}=e.latlng;if(!marker){marker=window.L.marker([lat,lng],{draggable:true}).addTo(map);bindDrag(marker);}else{marker.setLatLng([lat,lng]);}updateInputs(lat,lng);});
          const onCoordChange=()=>{const lat=parseFloat(f.latitude?.control?.value),lng=parseFloat(f.longitude?.control?.value);if(!isNaN(lat)&&!isNaN(lng)&&lat>=-90&&lat<=90&&lng>=-180&&lng<=180){if(!marker){marker=window.L.marker([lat,lng],{draggable:true}).addTo(map);bindDrag(marker);}else{marker.setLatLng([lat,lng]);}map.setView([lat,lng],Math.max(map.getZoom(),14));}};
          f.latitude?.control?.addEventListener("change",onCoordChange);
          f.longitude?.control?.addEventListener("change",onCoordChange);
          setTimeout(()=>map.invalidateSize(),250);
          const origClose=d.close;
          d.close=()=>{try{map.remove();}catch{}origClose();};
        },50);
      }
      if(type==="WAREHOUSES")relationship("branchId","Bưu cục *",data.branches,c?.branchId,true,!!c);
      if(["BRANCHES","WAREHOUSES"].includes(type))U.field(form,f,"address","Địa chỉ"+(type==="BRANCHES"?" *":""),c?.address,{required:type==="BRANCHES",full:true,maxLength:300});
      U.field(form,f,"isActive","Trạng thái",String(c?.isActive??true),{items:[["true","Đang sử dụng"],["false","Ngừng sử dụng"]]});form.append(U.el("p","col-12 small text-secondary","Mã đã tạo được giữ cố định. Ngừng sử dụng giữ lại lịch sử; backend kiểm tra quan hệ và công việc còn hoạt động trước khi lưu."));
      U.save(s,d,form,f,"/api/v1/catalogs","POST",()=>{const p={type,id:c?.id??null,code:f.code.control.value,name:f.name.control.value.trim(),isActive:f.isActive.control.value==="true"};for(const key of ["parentId","areaId","branchId"])if(f[key])p[key]=f[key].control.value?Number(f[key].control.value):null;for(const key of ["areaType","address","phone","email"])if(f[key])p[key]=f[key].control.value.trim()||null;if(f.latitude){const lat=f.latitude.control.value,lon=f.longitude.control.value;if(!!lat!==!!lon){U.invalid(f,"latitude","Phải nhập đồng thời vĩ độ và kinh độ.");U.invalid(f,"longitude","Phải nhập đồng thời vĩ độ và kinh độ.");}p.latitude=lat?Number(lat):null;p.longitude=lon?Number(lon):null;}return p;},async()=>{s.message="Đã lưu danh mục.";await render(s);});d.body.replaceChildren(form);
    }catch(error){U.failure(s,d.body,error,load);}}await load();}
  async function toggle(s,type,c){const d=U.dialog(s,c.isActive?"Ngừng sử dụng":"Kích hoạt lại");if(!d)return;try{const data=await s.read("/api/v1/catalogs?type="+type,d.signal),current=data[type.toLowerCase()].find(r=>r.id===c.id);if(!s.alive()||d.closed)return;if(!current)throw Error("Danh mục không tồn tại.");const form=U.el("form","row g-3");form.append(U.el("p","col-12 fw-semibold",current.code+" · "+current.name),U.el("p","col-12 text-secondary",(current.isActive?"Xác nhận ngừng sử dụng":"Xác nhận kích hoạt lại")+" danh mục. Backend sẽ từ chối nếu có quan hệ/công việc không cho phép."));U.save(s,d,form,{},"/api/v1/catalogs","POST",()=>({type,...current,isActive:!current.isActive}),async()=>{s.message="Đã cập nhật trạng thái.";render(s);},"Xác nhận");d.body.replaceChildren(form);}catch(error){U.failure(s,d.body,error);}}
  async function render(s){const pending=U.request(s),q=s.route.query,type=q.type||"AREAS",tabs=U.actions(...Object.entries(types).map(([id,label])=>{const n=U.link(label,R.href("catalogs",{},{type:id}));n.classList.toggle("btn-orange",id===type);n.classList.toggle("btn-outline-orange",id!==type);n.setAttribute("aria-current",id===type?"page":"false");return n;}));tabs.setAttribute("aria-label","Danh mục");
    if(type==="LOCATIONS"){s.root.replaceChildren(tabs);const child=U.el("div","catalog-locations");s.root.append(child);s.locationChild=true;window.LocationsPage.mount(child,s.user,{...s.route,query:{...q,status:q.status||"ALL"}},{permissions:s.permissions,signal:s.abort.signal});return;}
    s.root.replaceChildren(tabs,U.el("p","admin-empty","Đang tải danh mục…"));try{const data=await s.read("/api/v1/catalogs",pending.signal);if(!s.alive()||pending.signal.aborted||pending.epoch!==s.epoch)return;s.data=data;const form=U.el("form","row g-3 admin-filters"),f={};U.field(form,f,"keyword","Tìm mã hoặc tên",q.keyword,{maxLength:100});U.field(form,f,"isActive","Trạng thái",q.isActive,{items:[["","Tất cả trạng thái"],["true","Đang sử dụng"],["false","Ngừng sử dụng"]]});if(type==="WAREHOUSES")U.field(form,f,"branchId","Bưu cục",q.branchId,{items:[["","Tất cả bưu cục"],...data.branches.map(b=>[b.id,b.name])]});const search=U.button("Tìm kiếm",null,"btn btn-outline-orange");search.type="submit";form.append(U.actions(search));form.addEventListener("submit",e=>{e.preventDefault();R.navigate(R.href("catalogs",{},{type,...Object.fromEntries(Object.entries(f).map(([key,v])=>[key,v.control.value.trim()]))}));});for(const key of ["isActive","branchId"])f[key]?.control.addEventListener("change",()=>form.requestSubmit());const rows=data[type.toLowerCase()];if(!Array.isArray(rows))throw Error("Danh mục trả dữ liệu không hợp lệ.");const filtered=rows.filter(c=>(!q.isActive||c.isActive===(q.isActive==="true"))&&(!q.branchId||c.branchId===q.branchId)&&(!q.keyword||[c.code,c.name,c.address].some(v=>v?.toLocaleLowerCase("vi").includes(q.keyword.toLocaleLowerCase("vi")))));
      const columns=type==="AREAS"?["Khu vực cha","Loại"]:type==="BRANCHES"?["Khu vực","Địa chỉ","Điện thoại"]:type==="WAREHOUSES"?["Bưu cục","Địa chỉ"]:[];
      const feedback=U.el("div"),toolbar=U.actions(U.button("Làm mới",()=>render(s),"btn btn-outline-orange"));if(editable(s,type))toolbar.prepend(U.button("Thêm "+types[type].toLocaleLowerCase("vi"),()=>editor(s,type),"btn btn-orange"));s.root.replaceChildren(tabs,toolbar,form,feedback,U.el("p","small text-secondary",filtered.length+" kết quả"),filtered.length?U.table(["Mã","Tên",...columns,"Trạng thái","Thao tác"],filtered.map(c=>{const extra=type==="AREAS"?[name(data.areas,c.parentId),{CITY:"Tỉnh / Thành phố",DISTRICT:"Quận / Huyện",WARD:"Phường / Xã",SERVICE_ZONE:"Vùng phục vụ"}[c.areaType]]:type==="BRANCHES"?[name(data.areas,c.areaId),c.address,c.phone]:type==="WAREHOUSES"?[name(data.branches,c.branchId),c.address]:[];return[c.code,c.name,...extra,U.badge(c.isActive),editable(s,type)?U.actions(U.button("Sửa",()=>editor(s,type,c.id)),U.button(c.isActive?"Ngừng sử dụng":"Kích hoạt lại",()=>toggle(s,type,c))):"Chỉ xem"]; })):U.el("p","admin-empty","Không có danh mục phù hợp."));if(s.message){U.notice(feedback,s.message,"success");s.message="";}
    }catch(error){if(!pending.signal.aborted)U.failure(s,s.root,error,()=>render(s));}}
  function mount(container,user,route,context){destroy();active=U.state(container,user,route,context);render(active);}
  window.CatalogsPage=Object.freeze({mount,destroy});
}());

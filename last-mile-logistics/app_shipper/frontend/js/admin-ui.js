"use strict";
(function () {
  const {el,button,table,date,summary} = window.LogisticsUI;
  let unique = 0;
  const query = values => new URLSearchParams(Object.entries(values).filter(([,v]) => v !== "" && v != null)).toString();
  function actions(...nodes) { const n=el("div","admin-actions");n.append(...nodes);return n; }
  function link(label,href) { const n=el("a","btn btn-outline-orange btn-sm",label);n.href=href;return n; }
  function notice(box,message,tone="danger") { box.replaceChildren();if(message){const n=el("div","alert alert-"+tone,message);n.setAttribute("role",tone==="success"?"status":"alert");box.append(n);} }
  function failure(s,box,error,retry) { if(!s.alive()||error.name==="AbortError"||error.sessionExpired)return;notice(box,(error.status===403?"Không có quyền. ":"")+error.message);if(retry&&![403,404].includes(error.status))box.append(button("Thử lại",retry,"btn btn-outline-orange")); }
  function state(container,user,route,context) {
    const s={root:el("section","admin-page admin-"+route.pageId),user,route,permissions:context.permissions,abort:new AbortController(),epoch:0,dirty:false};
    s.alive=()=>!s.abort.signal.aborted;s.can=code=>s.permissions?.known&&s.permissions.codes.has(code);
    s.read=(path,signal=s.abort.signal)=>window.ApiClient.request(path,{signal});
    s.confirmLeave=()=>!s.dirty||window.confirm("Có thay đổi chưa lưu. Bạn muốn bỏ thay đổi và rời trang?");
    s.beforeUnload=e=>{if(s.dirty){e.preventDefault();e.returnValue="";}};
    s.onAbort=()=>s.destroy();context.signal?.addEventListener("abort",s.onAbort,{once:true});window.addEventListener("beforeunload",s.beforeUnload);
    s.destroy=()=>{if(!s.alive())return;s.destroying=true;s.dialog?.close();s.pending?.abort();s.abort.abort();context.signal?.removeEventListener("abort",s.onAbort);window.removeEventListener("beforeunload",s.beforeUnload);if(s.ownsGuard)window.Router.setLeaveGuard(null);};
    s.guard=()=>{s.ownsGuard=true;window.Router.setLeaveGuard(s.confirmLeave);};
    container.replaceChildren(s.root);if(context.signal?.aborted)s.destroy();return s;
  }
  function select(items,value) { const n=el("select","form-select");for(const [v,label,disabled] of items){const o=el("option","",label);o.value=v;o.disabled=!!disabled;n.append(o);}n.value=value??"";return n; }
  function field(form,fields,key,label,value,config={}) {
    const wrap=el("div",config.full?"col-12":"col-md-6"),cap=el("label","form-label",label);
    const control=config.items?select(config.items,value):el(config.multiline?"textarea":"input","form-control");
    if(!config.items){if(!config.multiline)control.type=config.type||"text";control.value=value??"";}
    control.id="admin-field-"+(++unique);control.name=key;cap.htmlFor=control.id;control.required=!!config.required;
    for(const attr of ["maxLength","min","max","step","pattern"])if(config[attr]!=null)control[attr]=config[attr];
    if(config.readonly)control.readOnly=true;if(config.disabled)control.disabled=true;
    const error=el("div","invalid-feedback");error.id=control.id+"-error";control.setAttribute("aria-describedby",error.id);wrap.append(cap,control,error);form.append(wrap);fields[key]={control,error};return control;
  }
  function invalid(fields,key,message) {const f=fields[key];if(f){f.control.classList.add("is-invalid");f.control.setAttribute("aria-invalid","true");f.error.textContent=message;}}
  function validate(fields) {for(const [key,f] of Object.entries(fields)){f.control.classList.remove("is-invalid");f.control.removeAttribute("aria-invalid");f.error.textContent="";if(f.control.disabled)continue;if(f.control.required&&!f.control.value.trim())invalid(fields,key,"Vui lòng nhập trường này.");else if(!f.control.checkValidity())invalid(fields,key,"Dữ liệu không hợp lệ.");}}
  function dialog(s,title) {
    if(s.dialog)return null;const node=el("dialog","admin-modal"),heading=el("h2","h5 mb-0",title),header=el("div","admin-modal-header"),body=el("div","admin-modal-body");heading.id="admin-dialog-"+(++unique);node.setAttribute("aria-labelledby",heading.id);
    const abort=new AbortController(),cancel=()=>abort.abort(),focus=document.activeElement; s.abort.signal.addEventListener("abort",cancel,{once:true});
    const d={node,body,heading,signal:abort.signal,busy:false,closed:false};
    d.close=()=>{if(d.closed)return;d.closed=true;abort.abort();s.abort.signal.removeEventListener("abort",cancel);if(node.open)node.close();node.remove();if(s.dialog===d)s.dialog=null;if(focus?.isConnected&&s.alive())focus.focus();};
    const close=button("Đóng",()=>{if(!d.busy)d.close();},"btn btn-outline-secondary btn-sm");d.busyState=b=>{d.busy=b;close.disabled=b;};header.append(heading,close);node.append(header,body);node.addEventListener("cancel",e=>{e.preventDefault();if(!d.busy)d.close();});node.addEventListener("close",d.close);s.root.append(node);s.dialog=d;body.append(el("p","text-secondary","Đang tải…"));node.showModal();return d;
  }
  function save(s,d,form,fields,path,method,build,done,label="Lưu") {
    form.noValidate=true;const box=el("div","col-12"),submit=button(label,null,"btn btn-orange");submit.type="submit";form.append(box,actions(submit));
    form.addEventListener("submit",async e=>{e.preventDefault();if(d.busy)return;validate(fields);notice(box,"");const payload=build();const first=Object.values(fields).find(f=>f.control.classList.contains("is-invalid"));if(first||!payload){first?.control.focus();return;}
      const controls=[...form.querySelectorAll("input,select,textarea,button")].map(c=>[c,c.disabled]);for(const [c]of controls)c.disabled=true;d.busyState(true);submit.textContent="Đang lưu…";
      try{const result=await window.ApiClient.request(path,{method,body:JSON.stringify(payload),signal:d.signal});if(!s.alive()||d.closed)return;d.close();await done(result);}
      catch(error){if(!s.alive()||d.closed||error.name==="AbortError"||error.sessionExpired)return;for(const [key,messages]of Object.entries(error.data?.errors||{})){const actual=Object.keys(fields).find(k=>k.toLowerCase()===key.split(".").at(-1).toLowerCase());if(actual)invalid(fields,actual,[].concat(messages).join(" "));}notice(box,error.message+(error.status===409?" Hãy tải lại dữ liệu trước khi thử lại.":""));}
      finally{if(!d.closed){d.busyState(false);for(const [c,disabled]of controls)c.disabled=disabled;submit.textContent=label;}}
    });
  }
  function request(s) {s.pending?.abort();s.pending=new AbortController();return {epoch:++s.epoch,signal:AbortSignal.any([s.abort.signal,s.pending.signal])};}
  function badge(active){return el("span","badge "+(active?"text-bg-success":"text-bg-secondary"),active?"Đang sử dụng":"Ngừng sử dụng");}
  function pager(box,data,change) {const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize)),prev=button("‹ Trước",()=>change({page:data.page-1})),next=button("Sau ›",()=>change({page:data.page+1}));prev.disabled=data.page<=1;next.disabled=data.page>=pages;const size=select([...new Set([10,20,50,100,data.pageSize])].sort((a,b)=>a-b).map(n=>[n,n+" dòng"]),data.pageSize);size.setAttribute("aria-label","Số dòng mỗi trang");size.addEventListener("change",()=>change({page:1,pageSize:Number(size.value)}));box.replaceChildren(el("span","text-secondary",data.totalItems+" kết quả · Trang "+data.page+" / "+pages),prev,next,size);}
  window.AdminUI=Object.freeze({el,button,table,date,summary,query,actions,link,notice,failure,state,select,field,invalid,validate,dialog,save,request,badge,pager});
}());

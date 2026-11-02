"use strict";
module.exports=async function(c){
  const {visit,admin,evaluate,until,check,click,change,snapshot,send,fixtureCommand,assert,checks}=c;
  const loaded="document.querySelector('#report-results[aria-busy=false]') && document.querySelector('.report-period')";
  await visit(admin,'#/reports?from=2026-09-09&to=2026-09-12&pageSize=10');await until(loaded);
  await send('Emulation.setDeviceMetricsOverride',{width:1366,height:1000,deviceScaleFactor:1,mobile:false});
  await check('Compact desktop filters share a row and inputs are 38px',"(()=>{const fields=[...document.querySelectorAll('.report-filter-main input,.report-filter-main select,.report-filter-actions button')].map(n=>n.getBoundingClientRect());return Math.max(...fields.map(r=>r.top))-Math.min(...fields.map(r=>r.top))<2 && fields.every(r=>r.height>=36&&r.height<=40) && document.querySelector('.report-filters').clientHeight<145})()");
  await check('Logo/menu/header/content stay within the layout without overlap',"(()=>{const logo=document.querySelector('.brand-sidebar').getBoundingClientRect(),menu=document.querySelector('[data-page=reports]').getBoundingClientRect(),side=document.querySelector('.sidebar').getBoundingClientRect(),title=document.querySelector('.page-heading').getBoundingClientRect(),header=document.querySelector('.topbar').getBoundingClientRect();return logo.left>=0&&logo.right<=side.right&&menu.left>=0&&menu.right<=side.right&&title.left>=side.right&&title.top>=header.bottom})()");
  await check('Three branch rows have a compact footer and no unnecessary previous/next',"(()=>{const panel=[...document.querySelectorAll('.report-panel')].at(-1),pager=panel.querySelector('.report-pagination'),size=pager.querySelector('select'),controls=pager.querySelector('.report-page-controls');return panel.querySelectorAll('tbody tr').length===3 && pager.textContent.includes('Hiển thị 1–3 trong 3 kết quả') && !controls.querySelector('button') && size.getBoundingClientRect().width>=90 && size.getBoundingClientRect().width<=110 && Math.abs(pager.querySelector('.report-page-summary').getBoundingClientRect().top-controls.getBoundingClientRect().top)<12})()");
  await check('Branch columns are short; all numeric columns align right',"(()=>{const t=[...document.querySelectorAll('.report-table')].at(-1);return [...t.querySelectorAll('th')].map(n=>n.textContent).join('|')==='Bưu cục|Tổng đơn|Thành công|Thất bại|Hủy/hoàn'&&[...t.querySelectorAll('td.report-number')].every(n=>getComputedStyle(n).textAlign==='right')})()");
  await check('Definitions are collapsed initially; technical notice is removed',"document.querySelector('.report-method').hidden && !document.querySelector('#report-results').textContent.includes('Danh sách đơn hiện chưa hỗ trợ') && !document.querySelector('.report-result-heading h2')");
  await click('Cách tính số liệu');await check('Expanded definition keeps current-state and distinct-order semantics',"!document.querySelector('.report-method').hidden && document.querySelector('.report-method').textContent.includes('Mỗi đơn đếm một lần') && document.querySelector('.report-method').textContent.includes('DELIVERED')");await click('Cách tính số liệu');
  for(const width of [1366,1920,390])await snapshot('orders',width);
  await send('Emulation.setDeviceMetricsOverride',{width:768,height:1000,deviceScaleFactor:1,mobile:false});
  await check('Tablet shows two metric cards per row',"(()=>{const r=[...document.querySelectorAll('.report-stat')].map(n=>n.getBoundingClientRect());return Math.abs(r[0].top-r[1].top)<2 && r[2].top>r[0].bottom})()");

  await change('to','2026-09-11','.report-filters');
  const before=await evaluate("({period:document.querySelector('.report-period').textContent,total:document.querySelector('.report-stat strong').textContent})");
  await click('Làm mới');await until(loaded);
  assert.deepEqual(await evaluate("({period:document.querySelector('.report-period').textContent,total:document.querySelector('.report-stat strong').textContent})"),before);
  await check('Refresh keeps applied range and preserves draft fields',"document.querySelector('[name=to]').value==='2026-09-11' && location.hash.includes('to=2026-09-12') && document.querySelector('.report-draft') && [...document.querySelectorAll('button')].find(b=>b.textContent==='Xuất CSV').disabled");
  await click('Áp dụng');await until("document.querySelector('#report-results[aria-busy=false]') && location.hash.includes('to=2026-09-11')");
  await check('Apply commits matching labels and results together',"document.querySelector('.report-period').textContent.includes('11/09/2026') && document.querySelectorAll('.report-chart tbody tr').length===3 && !document.querySelector('.report-draft')");
  await click('7 ngày');await check('Quick range selection is explicit and waits for Apply',"document.querySelector('.report-quick button[aria-pressed=true]').textContent==='7 ngày' && location.hash.includes('to=2026-09-11') && !!document.querySelector('.report-draft')");
  await change('from','2026-09-09','.report-filters');await change('to','2026-09-12','.report-filters');await click('Áp dụng');await until(loaded+" && location.hash.includes('to=2026-09-12')");
  await click('Giao hàng');await until(loaded+" && !!document.querySelector('#report-tab-delivery[aria-selected=true]')");
  await check('Delivery labels count attempts and detailed explanation retains repeat attempts',"[...document.querySelectorAll('.report-stat-label span')].map(n=>n.textContent).join('|')==='Phân công trong kỳ|Lượt giao|Giao thành công|Tỷ lệ thành công' && document.querySelector('.report-method').textContent.includes('Một đơn có thể có nhiều phân công/lần giao') && document.querySelector('.report-stat[title]').title.includes('Số lượt giao thành công / tổng lượt giao × 100%')");
  for(const width of [1366,1920,390])await snapshot('delivery',width);
  await click('Đơn hàng');await until(loaded+" && !!document.querySelector('.report-plot svg')");
  await until("document.querySelector('.report-plot svg').viewBox.baseVal.width<500");
  await check('SVG re-renders after tab switch at mobile width with 260px plot',"(()=>{const svg=document.querySelector('.report-plot svg'),r=svg.getBoundingClientRect();return r.width>200&&r.height>=240&&r.height<=280&&svg.querySelectorAll('circle').length===4&&svg.viewBox.baseVal.width<500})()");
  await click('Cước phí & COD');await until(loaded+" && !!document.querySelector('#report-tab-finance[aria-selected=true]')");
  for(const width of [1366,1920,390])await snapshot('finance',width);
  await click('Cách tính số liệu');await check('Finance explanations retain fee/COD distinction and historical caveats on demand',"!document.querySelector('.report-method').hidden && document.querySelector('.report-method').textContent.includes('COD không phải doanh thu') && document.querySelector('.report-method').textContent.includes('không phải ảnh chụp trạng thái quá khứ')");await click('Cách tính số liệu');

  await evaluate("window.qaOriginalNS=document.createElementNS;document.createElementNS=function(ns,name,...args){if(name==='polyline')throw Error('QA chart failure');return qaOriginalNS.call(this,ns,name,...args)}");
  await click('Đơn hàng');await until(loaded+" && !!document.querySelector('.report-chart-error')");
  await check('Chart failure shows an error and expands the real daily data table',"document.querySelector('.report-chart-error').textContent.includes('Không thể hiển thị biểu đồ') && document.querySelector('.report-chart details').open && [...document.querySelectorAll('.report-chart tbody tr')].map(r=>r.cells[1].textContent).join(',')==='1,2,9,0'");
  await evaluate('document.createElementNS=qaOriginalNS');
  await click('Giao hàng');await until(loaded+" && !!document.querySelector('#report-tab-delivery[aria-selected=true]')");
  await click('Đơn hàng');await until(loaded+" && !!document.querySelector('.report-plot svg')");

  // Verify the real API with more than one full page of rows in the isolated database.
  await fixtureCommand('ManyRows');
  await visit(admin,'#/reports?from=2026-09-09&to=2026-09-12&tab=delivery&pageSize=10');await until(loaded);
  await check('Many-row table uses backend pagination without nested vertical scrolling',"document.querySelectorAll('.report-panel tbody tr').length===10 && document.querySelector('.report-page-summary').textContent==='Hiển thị 1–10 trong 28 kết quả' && [...document.querySelectorAll('.report-table-wrap')].every(n=>n.scrollHeight<=n.clientHeight+1)");
  for(const width of [1366,1920,390])await snapshot('delivery-many',width);
  await click('Sau ›');await until(loaded+" && location.hash.includes('page=2')");
  await check('Many-row footer advances without changing totals',"document.querySelector('.report-page-summary').textContent==='Hiển thị 11–20 trong 28 kết quả'");
  await evaluate("window.qa.csv=null;const create=URL.createObjectURL;URL.createObjectURL=function(blob){blob.text().then(text=>qa.csv=text);return create.call(this,blob)};HTMLAnchorElement.prototype.click=function(){};");
  await click('Xuất CSV');await until('qa.csv!==null');await check('Many-row CSV contains rows outside current page',"qa.csv.includes('Nhân viên kiểm tra 24') && qa.csv.includes('Nhân viên kiểm tra 1')");
  checks.push('UI verification used real API data, 100% zoom, 1366/1920/mobile, short and many-row tables');
};

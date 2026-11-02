"use strict";
// The real form's submit/inline-validation flow, with only its business clock controlled.
module.exports = async ({ evaluate, change, click, until, check, control, checks }) => {
  await evaluate(`(()=>{
    qa.originalVietnamDate=window.VietnamDate;qa.originalProbeFetch=window.fetch;qa.probeRequests=0;
    window.VietnamDate={...qa.originalVietnamDate,isLicenseExpired:day=>qa.originalVietnamDate.isLicenseExpired(day,new Date(qa.licenseNow))};
    window.fetch=async(...args)=>{
      if(String(args[0]).endsWith('/api/v1/shippers')&&args[1]?.method==='POST'){
        qa.probeRequests++;return new Response(JSON.stringify({message:'Kiểm tra ngày thử, không ghi dữ liệu.'}),{status:400,headers:{'Content-Type':'application/json'}});
      }
      return qa.originalProbeFetch(...args);
    };
  })()`);
  try {
    for (const [instant, expiry, expired] of [
      ["2026-10-19T23:59:00+07:00", "2026-10-19", false],
      ["2026-10-20T00:00:00+07:00", "2026-10-19", true],
      ["2026-10-20T06:59:00+07:00", "2026-10-19", true],
      ["2026-10-20T06:59:00+07:00", "2026-10-20", false],
      ["2026-10-20T23:59:59+07:00", "2026-10-20", false],
    ]) {
      await evaluate(`qa.licenseNow=${JSON.stringify(instant)};qa.probeRequests=0;`);
      await change("Ngày hết hạn bằng lái", expiry);
      await click("Lưu", "dialog button");
      await until("[...document.querySelectorAll('dialog button')].some(b=>b.textContent==='Lưu'&&!b.disabled)");
      await check("Real shipper form expiry " + expiry + " at " + instant,
        `${control("Ngày hết hạn bằng lái")}.classList.contains('is-invalid')===${expired}&&qa.probeRequests===${expired ? 0 : 1}&&${control("Ngày hết hạn bằng lái")}.value===${JSON.stringify(expiry)}`);
    }
    checks.push("Controlled form-clock probes preserve date-only input and do not write SQL");
  } finally {
    await evaluate("window.VietnamDate=qa.originalVietnamDate;window.fetch=qa.originalProbeFetch;");
  }
};

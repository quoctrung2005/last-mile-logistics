"use strict";
const fs = require("node:fs"), path = require("node:path"), http = require("node:http"), { spawn } = require("node:child_process");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, ".."), output = path.join(__dirname, ".artifacts", "sidebar-layout");
const { createServer } = require(path.join(root, "dev-server.cjs"));
const staticServer = createServer(), serve = staticServer.listeners("request")[0];
staticServer.removeAllListeners("request");
staticServer.on("request", (req, res) => {
  if (req.url !== "/") return serve(req, res);
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8").replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, "").replace('class="login-page"', 'class="login-page d-none"').replace('class="app-shell d-none"', 'class="app-shell"');
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }); res.end(html);
});
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let edge, socket, id = 0; const pending = new Map();
async function main() {
  fs.mkdirSync(output, { recursive: true });
  await new Promise(resolve => staticServer.listen(0, "127.0.0.1", resolve));
  const profile = path.join(output, "profile-" + Date.now()); fs.mkdirSync(profile, { recursive: true });
  edge = spawn("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", ["--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--remote-debugging-address=127.0.0.1", "--remote-debugging-port=0", "--user-data-dir=" + profile, "about:blank"], { windowsHide: true, stdio: "ignore" });
  const portFile = path.join(profile, "DevToolsActivePort");
  for (let i = 0; i < 150 && !fs.existsSync(portFile); i++) await sleep(100);
  const port = fs.readFileSync(portFile, "utf8").split("\n")[0];
  const tabs = await (await fetch("http://127.0.0.1:" + port + "/json/list")).json();
  socket = new WebSocket(tabs.find(tab => tab.type === "page").webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { const timeout = setTimeout(() => reject(Error("Browser connection timed out")), 10000); socket.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true }); socket.addEventListener("error", reject, { once: true }); });
  socket.addEventListener("message", event => { const data = JSON.parse(event.data); if (data.id) { const waiter = pending.get(data.id); pending.delete(data.id); data.error ? waiter.reject(Error(data.error.message)) : waiter.resolve(data.result); } });
  const send = (method, params = {}) => new Promise((resolve, reject) => { const next = ++id; const timeout = setTimeout(() => reject(Error(method + " timed out")), 20000); pending.set(next, { resolve: result => { clearTimeout(timeout); resolve(result); }, reject }); socket.send(JSON.stringify({ id: next, method, params })); });
  const evaluate = async expression => { const result = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }); if (result.exceptionDetails) throw Error(result.exceptionDetails.text); return result.result.value; };
  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: "http://127.0.0.1:" + staticServer.address().port + "/" });
  for (let i = 0; i < 150; i++) { if (await evaluate("document.readyState === 'complete' && !!document.querySelector('.sidebar-account-avatar')")) break; await sleep(100); }
  await evaluate(`document.getElementById('sidebar-account-name').textContent='Nguyễn Hoàng Minh'; document.getElementById('sidebar-account-role').textContent='Quản trị viên'; document.getElementById('sidebar-account-avatar').textContent='HM'; document.getElementById('branch-label').textContent='Toàn hệ thống'; document.getElementById('main-navigation').innerHTML=Array.from({length:24},(_,i)=>'<a class="navigation-link" href="#/dashboard"><i class="bi bi-box-seam"></i><span>Mục điều hướng '+(i+1)+'</span></a>').join('');`);
  for (const [width, height, longName] of [[1280, 720, false], [390, 844, false], [1280, 480, true], [390, 480, true]]) {
    await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    await evaluate(`document.getElementById('sidebar').classList.add('is-open');document.getElementById('sidebar-account-name').textContent=${JSON.stringify(longName ? "Nguyễn Hoàng Minh Phương Thanh" : "Nguyễn Hoàng Minh")};document.getElementById('sidebar-account-role').textContent=${JSON.stringify(longName ? "Kế toán / Đối soát" : "Quản trị viên")};document.getElementById('branch-label').textContent=${JSON.stringify(longName ? "Bưu cục #123456789" : "Toàn hệ thống")};`);
    await sleep(300);
    const layout = await evaluate(`(() => {const footer=document.querySelector('.sidebar-footer'), button=document.getElementById('sidebar-signout'), nav=document.querySelector('.sidebar-scroll'), bounds=button.getBoundingClientRect();return {width:innerWidth,height:innerHeight,footerHeight:footer.offsetHeight,buttonBottom:bounds.bottom,buttonHeight:bounds.height,footerFits:footer.scrollWidth<=footer.clientWidth,navScrollable:nav.scrollHeight>nav.clientHeight,pageFits:document.documentElement.scrollWidth<=innerWidth};})()`);
    assert(layout.footerFits && layout.pageFits && layout.navScrollable && layout.buttonBottom <= height && layout.buttonHeight >= 28, JSON.stringify(layout));
    console.log(JSON.stringify(layout));
    const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
    fs.writeFileSync(path.join(output, `sidebar-${width}-${height}.png`), Buffer.from(shot.data, "base64"));
  }
  await evaluate("document.getElementById('sidebar-signout').focus()");
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9, modifiers: 8 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9, modifiers: 8 });
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9 });
  assert(await evaluate("getComputedStyle(document.getElementById('sidebar-signout')).outlineStyle==='solid'"));
  console.log("Sidebar layout and keyboard focus checks passed.");
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => { socket?.close(); edge?.kill(); staticServer.close(); });

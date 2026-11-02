'use strict';
// Real password + recovery APIs and SMTP delivery, entirely inside a temporary
// LocalDB database and a loopback-only SMTP inbox. No external mail is sent.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const net = require('node:net');
const path = require('node:path');
const { spawn, execFile } = require('node:child_process');
const { promisify } = require('node:util');
const root = path.resolve(__dirname, '../..');
const backend = path.join(root, 'backend/LastMile/LastMile.Api');
const build = process.env.SHIPPER_TEST_BUILD || path.join(__dirname, '.artifacts/shipper-auth/build');
const database = 'CodexAccounts_' + crypto.randomBytes(16).toString('hex');
const jwtKey = crypto.randomBytes(64).toString('hex');
const secret = () => 'Qa!' + crypto.randomBytes(18).toString('hex');
const rawToken = () => crypto.randomBytes(32).toString('base64url');
const hash = token => crypto.createHash('sha256').update(token).digest('hex').toUpperCase();
const checks = [], messages = [], sockets = new Set();
let processApi, origin, smtp;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const check = description => { checks.push(description); console.log('PASS ' + description); };

async function fixture(mode) {
  const script = mode === 'Prepare' ? 'auth-sessions-fixture.ps1' : 'accounts-fixture.ps1';
  try {
    const { stdout } = await promisify(execFile)('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, script),
      '-Mode', mode, '-Database', database,
    ], { windowsHide: true, maxBuffer: 8 * 1024 * 1024 });
    return JSON.parse(stdout);
  } catch { throw new Error('Isolated password fixture failed: ' + mode); }
}

async function sql(query) {
  assert.match(database, /^CodexAccounts_[a-f0-9]{32}$/);
  const { stdout } = await promisify(execFile)('sqlcmd', [
    '-S', '(localdb)\\MSSQLLocalDB', '-d', database, '-E', '-C', '-I', '-b', '-h', '-1', '-W',
    '-Q', 'SET NOCOUNT ON; ' + query,
  ], { windowsHide: true, maxBuffer: 1024 * 1024 });
  return stdout.trim();
}

function jwt(payload) {
  const head = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return head + '.' + body + '.' + crypto.createHmac('sha256', jwtKey).update(head + '.' + body).digest('base64url');
}

async function api(url, session, body, expected = 200, method = 'POST') {
  const response = await fetch(origin + url, {
    method, headers: { 'Content-Type': 'application/json',
      ...(session ? { Authorization: 'Bearer ' + session.accessToken } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  assert.equal(response.status, expected, method + ' ' + url + ' status');
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
const me = (session, expected = 200) => api('/api/v1/auth/me', session, undefined, expected, 'GET');
const recover = (body, expected = 200) => api('/api/v1/auth/password-recovery', null, body, expected);
const denied = async session => {
  await me(session, 401);
  await api('/api/v1/auth/refresh', null, { refreshToken: session.refreshToken }, 401);
};

function emailToken(raw) {
  const split = raw.indexOf('\r\n\r\n');
  const headers = raw.slice(0, split);
  let body = raw.slice(split + 4);
  if (/Content-Transfer-Encoding:\s*base64/i.test(headers)) {
    body = Buffer.from(body.replace(/\s/g, ''), 'base64').toString('utf8');
  } else if (/Content-Transfer-Encoding:\s*quoted-printable/i.test(headers)) {
    body = body.replace(/=\r\n/g, '').replace(/=([A-Fa-f0-9]{2})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
  }
  const token = body.split(/\r?\n/).map(line => line.trim()).find(line => /^[A-Za-z0-9_-]{43}$/.test(line));
  assert.ok(token, 'Loopback inbox received a complete recovery token');
  return token;
}

async function inbox() {
  smtp = net.createServer(socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => {});
    socket.setEncoding('utf8');
    socket.write('220 localhost QA SMTP\r\n');
    let buffer = '', data = null, authStage = 0;
    socket.on('data', chunk => {
      buffer += chunk;
      let end;
      while ((end = buffer.indexOf('\r\n')) >= 0) {
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 2);
        if (data !== null) {
          if (line === '.') {
            messages.push(emailToken(data.join('\r\n'))); data = null;
            socket.write('250 Queued in local test inbox\r\n');
          } else data.push(line);
        } else if (authStage) {
          socket.write(authStage++ === 1 ? '334 UGFzc3dvcmQ6\r\n' : '235 Authenticated\r\n');
          if (authStage > 2) authStage = 0;
        } else if (/^EHLO/i.test(line)) socket.write('250-localhost\r\n250 AUTH LOGIN PLAIN\r\n');
        else if (/^AUTH LOGIN/i.test(line)) {
          // .NET may send the username as an initial SASL response on this line.
          const hasInitialResponse = line.trim().split(/\s+/).length > 2;
          authStage = hasInitialResponse ? 2 : 1;
          socket.write(hasInitialResponse ? '334 UGFzc3dvcmQ6\r\n' : '334 VXNlcm5hbWU6\r\n');
        }
        else if (/^AUTH PLAIN/i.test(line)) socket.write('235 Authenticated\r\n');
        else if (/^DATA$/i.test(line)) { data = []; socket.write('354 End with a dot\r\n'); }
        else if (/^QUIT$/i.test(line)) { socket.end('221 Goodbye\r\n'); }
        else socket.write('250 OK\r\n');
      }
    });
  });
  await new Promise((resolve, reject) => { smtp.once('error', reject); smtp.listen(0, '127.0.0.1', resolve); });
  return smtp.address().port;
}

(async () => {
  const setup = await fixture('Create');
  const { sessionId } = await fixture('Prepare');
  const smtpPort = await inbox();
  const actor = setup.actors.find(actor => actor.role === 'ADMIN');
  const bootstrap = { accessToken: jwt({ iss: 'PasswordQA', aud: 'PasswordQA',
    exp: Math.floor(Date.now() / 1000) + 3600, sid: sessionId,
    'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier': String(actor.accountId),
    'http://schemas.microsoft.com/ws/2008/06/identity/claims/role': 'ADMIN',
  }) };
  let log = '';
  processApi = spawn('dotnet', [path.join(build, 'LastMile.Api.dll'), '--urls', 'http://127.0.0.1:0'], {
    cwd: backend, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, ASPNETCORE_ENVIRONMENT: 'Development',
      ConnectionStrings__DefaultConnection: setup.connectionString,
      Jwt__Key: jwtKey, Jwt__Issuer: 'PasswordQA', Jwt__Audience: 'PasswordQA',
      LoginSecurity__IpPermitLimit: '1000',
      Email__Host: '127.0.0.1', Email__Port: String(smtpPort), Email__EnableSsl: 'false',
      Email__From: 'qa@example.invalid', Email__Username: 'local-qa', Email__Password: secret(),
    },
  });
  processApi.stdout.on('data', data => { log += data; });
  processApi.stderr.on('data', data => { log += data; });
  for (let i = 0; i < 150 && !/Now listening on: (http:\/\/127.0.0.1:\d+)/.test(log); i++) await sleep(100);
  origin = log.match(/Now listening on: (http:\/\/127.0.0.1:\d+)/)?.[1];
  assert.ok(origin, 'Isolated password API started');
  const roles = (await api('/api/v1/roles?lookupOnly=true', bootstrap, undefined, 200, 'GET')).items;
  let password = secret();
  const account = await api('/api/v1/accounts', bootstrap, {
    username: 'qa.password.driver', password, fullName: 'QA Password Driver',
    email: 'driver@example.invalid', roleId: roles.find(role => role.code === 'SHIPPER').id,
    branchId: setup.actors.find(actor => actor.role === 'BRANCH_MANAGER').branchId,
  }, 201);
  const login = () => api('/api/v1/auth/login', null, { username: account.username, password });
  let a = await login(), b = await login();
  assert.equal((await me(a)).role, 'SHIPPER');
  let next = secret();
  const change = (body, expected, session = a) => api('/api/v1/auth/change-password', session, body, expected);
  await change({ currentPassword: 'wrong', newPassword: next, confirmPassword: next }, 400);
  await me(a);
  await change({ currentPassword: password, newPassword: 'short', confirmPassword: 'short' }, 400);
  await change({ currentPassword: password, newPassword: password, confirmPassword: password }, 400);
  await change({ currentPassword: password, newPassword: next, confirmPassword: secret() }, 400);
  check('Wrong current password, weak/unchanged/mismatched new passwords are rejected without changing the active session');
  await change({ currentPassword: password, newPassword: next, confirmPassword: next }, 200);
  await denied(a); await denied(b);
  await api('/api/v1/auth/login', null, { username: account.username, password }, 401);
  password = next; a = await login(); b = await login(); await me(a);
  check('Password change accepts the new password and revokes all previous access and refresh sessions');

  const notice = await recover({ action: 'REQUEST', email: 'driver@example.invalid' });
  assert.equal(messages.length, 1, 'Exactly one local email delivered');
  const code = messages[0];
  assert.equal(await sql(`SELECT COUNT(*) FROM dbo.TokenKhoiPhucMatKhau WHERE MaTaiKhoan=${account.id} AND GiaTriBamToken='${hash(code)}';`), '1');
  check('Recovery REQUEST delivers a real email to the loopback inbox and stores only its hashed token');
  assert.deepEqual(await recover({ action: 'REQUEST', email: 'unknown@example.invalid' }), notice);
  assert.deepEqual(await recover({ action: 'REQUEST', email: 'driver@example.invalid' }), notice);
  assert.equal(messages.length, 1);
  check('Unknown email and repeated requests return the same generic notice; resend within a minute creates no second email');

  next = secret();
  await recover({ action: 'RESET', recoveryToken: rawToken(), newPassword: next, confirmPassword: next }, 401);
  const expired = rawToken();
  await sql(`INSERT dbo.TokenKhoiPhucMatKhau(MaTaiKhoan,GiaTriBamToken,ThoiGianTao,HetHanLuc) VALUES(${account.id},'${hash(expired)}',DATEADD(MINUTE,-20,SYSUTCDATETIME()),DATEADD(MINUTE,-1,SYSUTCDATETIME()));`);
  await recover({ action: 'RESET', recoveryToken: expired, newPassword: next, confirmPassword: next }, 401);
  await recover({ action: 'RESET', recoveryToken: code, newPassword: next, confirmPassword: secret() }, 400);
  await me(a);
  check('Unknown/expired tokens and mismatched confirmation cannot reset the password or revoke a valid session');
  await recover({ action: 'RESET', recoveryToken: code, newPassword: next, confirmPassword: next });
  await denied(a); await denied(b);
  await recover({ action: 'RESET', recoveryToken: code, newPassword: next, confirmPassword: next }, 401);
  password = next; await me(await login());
  check('Email recovery resets the password, revokes all sessions and consumes the code exactly once');

  await sql(`UPDATE dbo.TokenKhoiPhucMatKhau SET ThoiGianTao=DATEADD(MINUTE,-5,SYSUTCDATETIME()) WHERE MaTaiKhoan=${account.id}; UPDATE dbo.TaiKhoan SET TrangThaiTaiKhoan='LOCKED' WHERE MaTaiKhoan=${account.id};`);
  await recover({ action: 'REQUEST', email: 'driver@example.invalid' });
  assert.equal(messages.length, 2);
  next = secret();
  await recover({ action: 'RESET', recoveryToken: messages[1], newPassword: next, confirmPassword: next });
  assert.equal(await sql(`SELECT TrangThaiTaiKhoan FROM dbo.TaiKhoan WHERE MaTaiKhoan=${account.id};`), 'LOCKED');
  await api('/api/v1/auth/login', null, { username: account.username, password: next }, 401);
  check('Recovery does not unlock an administratively locked account');
  console.log(JSON.stringify({ passed: checks.length, checks, externalEmailsSent: 0, operationalDatabaseWrites: false }));
})().catch(error => { console.error(error.stack); process.exitCode = 1; }).finally(async () => {
  if (processApi && processApi.exitCode === null) {
    const stopped = new Promise(resolve => processApi.once('exit', resolve));
    processApi.kill(); await stopped;
  }
  for (const socket of sockets) socket.destroy();
  if (smtp) await new Promise(resolve => smtp.close(resolve));
  try { await fixture('Drop'); console.log('Isolated password database removed.'); }
  catch { console.error('Isolated password database cleanup failed.'); process.exitCode = 1; }
});

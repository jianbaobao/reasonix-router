// ============================================================
//  Reasonix Router - Web Management UI v2
//  完整路由管理功能
// ============================================================

// ─── Tab 切换 ─────────────────────────────────────────────
function showTab(name) {
    document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.tab').forEach(el => el.classList.remove('active'));
    const tab = document.getElementById(name);
    if (tab) tab.classList.add('active');
    const btn = document.querySelector(`.tab[onclick*="${name}"]`);
    if (btn) btn.classList.add('active');
    // 进入 tab 时刷新
    switch(name) {
        case 'status': refreshStatus(); break;
        case 'network': refreshNetwork(); break;
        case 'dhcp': refreshDHCP(); break;
        case 'forward': refreshForward(); break;
        case 'log': refreshLog(); break;
        case 'tools': break;
        case 'plugins': refreshPlugins(); refreshPluginStore(); break;
        case 'system': refreshSystem(); break;
    }
}

// ─── API 调用 ─────────────────────────────────────────────
const API_BASE = '/cgi-bin/api?path=';
async function api(method, path, body) {
    try {
        const clean = path.replace(/^\//, '');
        const opts = { method };
        if (body) {
            opts.headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
            opts.body = body;
        }
        const resp = await fetch(`${API_BASE}${clean}`, opts);
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        const text = await resp.text();
        try { return JSON.parse(text); } catch(e) { return { error: text }; }
    } catch (e) {
        return { error: e.message };
    }
}

// ─── 状态页 ───────────────────────────────────────────────
async function refreshStatus() {
    const uptime = await api('GET', '/uptime');
    const e = document.getElementById('uptime');
    if (uptime.uptime) { e.textContent = uptime.uptime; e.removeAttribute('data-i18n'); }
    else { e.textContent = t('status.unavailable'); }

    const mem = await api('GET', '/memory');
    const me = document.getElementById('memory');
    if (mem.total) {
        me.textContent = `${(mem.used / 1024).toFixed(1)} MB / ${(mem.total / 1024).toFixed(1)} MB`;
        me.removeAttribute('data-i18n');
    } else { me.textContent = t('status.unavailable'); }

    const load = await api('GET', '/loadavg');
    const le = document.getElementById('loadavg');
    if (load.loadavg) { le.textContent = load.loadavg; le.removeAttribute('data-i18n'); }
    else { le.textContent = t('status.unavailable'); }

    const ifaces = await api('GET', '/interfaces');
    const tb = document.querySelector('#interfaces tbody');
    if (ifaces.interfaces && ifaces.interfaces.length > 0) {
        tb.innerHTML = ifaces.interfaces.map(i => {
            const speedTxt = i.speed > 0 ? (i.speed >= 1000 ? (i.speed/1000)+'G' : i.speed+'M') : '-';
            const rxTxt = formatBytes(i.rx_bytes || 0);
            const txTxt = formatBytes(i.tx_bytes || 0);
            const errTxt = (i.rx_errors||0) + '/' + (i.tx_errors||0);
            return `<tr class="iface-row" onclick="toggleIfaceDetail('${i.name}')">
                <td><strong>${i.name}</strong></td>
                <td>${i.ip||'-'}</td>
                <td>${i.mac||'-'}</td>
                <td class="${i.up?'status-up':'status-down'}">${i.up ? t('table.up') : t('table.down')}</td>
                <td>${speedTxt}</td>
                <td>${rxTxt}</td>
                <td>${txTxt}</td>
            </tr>
            <tr id="iface-detail-${i.name}" class="iface-detail" style="display:none">
                <td colspan="7">
                    <div class="detail-grid">
                        <span><b>MTU:</b> ${i.mtu||'1500'}</span>
                        <span><b>Duplex:</b> ${i.duplex||'unknown'}</span>
                        <span><b>Carrier:</b> ${i.carrier||'?'}</span>
                        <span><b>RX Pkts:</b> ${(i.rx_packets||0).toLocaleString()}</span>
                        <span><b>TX Pkts:</b> ${(i.tx_packets||0).toLocaleString()}</span>
                        <span><b>Errors:</b> ${errTxt}</span>
                        <span><b>RX Drop:</b> ${(i.rx_dropped||0).toLocaleString()}</span>
                        <span><b>TX Drop:</b> ${(i.tx_dropped||0).toLocaleString()}</span>
                        <span><b>Flags:</b> ${i.flags||'-'}</span>
                    </div>
                </td>
            </tr>`;
        }).join('');
    } else {
        tb.innerHTML = `<tr><td colspan="7">${t('error.no-data')}</td></tr>`;
    }
}

// 格式化字节
function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0';
    const units = ['B', 'KB', 'MB', 'GB'];
    let i = 0;
    let val = bytes;
    while (val >= 1024 && i < units.length - 1) { val /= 1024; i++; }
    return val.toFixed(1) + ' ' + units[i];
}

// 展开/收起接口详情
function toggleIfaceDetail(name) {
    const row = document.getElementById('iface-detail-' + name);
    if (row) row.style.display = row.style.display === 'none' ? 'table-row' : 'none';
}

// 扫描网口
async function scanInterfaces() {
    const scanBtn = document.getElementById('scan-btn');
    if (scanBtn) { scanBtn.textContent = t('status.scanning') + '...'; scanBtn.disabled = true; }
    await api('POST', '/interfaces-scan');
    if (scanBtn) { scanBtn.textContent = t('status.scan'); scanBtn.disabled = false; }
    refreshStatus();
}

// ─── 接口角色配置 ─────────────────────────────────────────
async function loadInterfaceRoles() {
    const res = await api('GET', '/interface-roles');
    const wanSel = document.getElementById('role-wan');
    const lanSel = document.getElementById('role-lan');
    if (!wanSel || !lanSel || !res.available) return;

    // 填充可用接口选项
    const currentWan = res.wan || '';
    const currentLan = res.lan || '';
    let wanOpts = '', lanOpts = '';
    for (const iface of res.available) {
        const selWan = (iface.name === currentWan) ? 'selected' : '';
        const selLan = (iface.name === currentLan) ? 'selected' : '';
        const label = `${iface.name} (${iface.mac})`;
        wanOpts += `<option value="${iface.name}" ${selWan}>${label}</option>`;
        lanOpts += `<option value="${iface.name}" ${selLan}>${label}</option>`;
    }
    wanSel.innerHTML = wanOpts;
    lanSel.innerHTML = lanOpts;
    document.getElementById('role-status').textContent =
        t('network.roles-current') + `: WAN=${currentWan || 'auto'}, LAN=${currentLan || 'auto'}`;
}

async function applyInterfaceRoles() {
    const wan = document.getElementById('role-wan').value;
    const lan = document.getElementById('role-lan').value;
    if (wan === lan) {
        alert(t('network.roles-same')); return;
    }
    const btn = document.querySelector('[onclick="applyInterfaceRoles()"]');
    if (btn) { btn.textContent = t('network.roles-applying') + '...'; btn.disabled = true; }

    const res = await api('POST', '/interface-roles',
        `wan=${encodeURIComponent(wan)}&lan=${encodeURIComponent(lan)}`);

    if (btn) { btn.textContent = t('network.roles-apply'); btn.disabled = false; }
    alert(res.message || res.error || 'Done');
    // 刷新网络和状态
    refreshNetwork();
    refreshStatus();
    refreshDHCP();
}

// ─── 网络页 ───────────────────────────────────────────────
async function refreshNetwork() {
    // 加载接口角色配置
    await loadInterfaceRoles();

    // 路由表和 NAT
    const rt = await api('GET', '/route');
    const re = document.getElementById('routing-table');
    if (rt.route) { re.textContent = rt.route; re.removeAttribute('data-i18n'); }
    else { re.textContent = t('error.no-data'); }

    const nat = await api('GET', '/nat');
    const ne = document.getElementById('nat-rules');
    if (nat.nat) { ne.textContent = nat.nat; ne.removeAttribute('data-i18n'); }
    else { ne.textContent = t('error.no-data'); }
}

// ─── DHCP 页 ──────────────────────────────────────────────
async function refreshDHCP() {
    // 活跃租约
    const leases = await api('GET', '/dhcp-leases');
    const tb = document.querySelector('#dhcp-leases tbody');
    if (leases.leases && leases.leases.length > 0) {
        tb.innerHTML = leases.leases.map(l =>
            `<tr><td>${l.mac}</td><td>${l.ip}</td><td>${l.hostname||'-'}</td><td>${l.remaining||'-'}</td></tr>`
        ).join('');
    } else {
        tb.innerHTML = `<tr><td colspan="4">${leases.leases ? t('dhcp.no-leases') : t('error.no-data')}</td></tr>`;
    }

    // 静态绑定
    const stb = document.querySelector('#dhcp-static tbody');
    if (leases.static && leases.static.length > 0) {
        stb.innerHTML = leases.static.map((h, i) =>
            `<tr><td>${h.mac}</td><td>${h.ip}</td><td>${h.hostname||'-'}</td>
             <td><button class="btn-sm" onclick="deleteDhcpHost(${i+1})">❌</button></td></tr>`
        ).join('');
    } else {
        stb.innerHTML = `<tr><td colspan="4">${t('dhcp.no-static')}</td></tr>`;
    }
}

async function addDhcpHost() {
    const mac = document.getElementById('dhcp-mac').value.trim();
    const ip = document.getElementById('dhcp-ip').value.trim();
    const hostname = document.getElementById('dhcp-name').value.trim();
    if (!mac || !ip) { alert(t('error.mac-ip-req')); return; }
    const body = `action=add&mac=${encodeURIComponent(mac)}&ip=${encodeURIComponent(ip)}&hostname=${encodeURIComponent(hostname)}`;
    const res = await api('POST', '/dhcp-hosts', body);
    alert(res.message || res.error || 'Done');
    refreshDHCP();
}

async function deleteDhcpHost(idx) {
    const body = `action=delete&idx=${idx}`;
    const res = await api('POST', '/dhcp-hosts', body);
    alert(res.message || res.error || 'Done');
    refreshDHCP();
}

// ─── 端口转发页 ───────────────────────────────────────────
async function refreshForward() {
    const res = await api('GET', '/portforward');
    const tb = document.querySelector('#forward-rules tbody');
    if (res.rules && res.rules.length > 0) {
        tb.innerHTML = res.rules.map(r =>
            `<tr><td>${r.proto||'tcp'}</td><td>${r.wan_port}</td><td>${r.lan_ip}</td><td>${r.lan_port}</td>
             <td><button class="btn-sm" onclick="deletePortForward(${r.idx})">❌</button></td></tr>`
        ).join('');
    } else {
        tb.innerHTML = `<tr><td colspan="5">${t('forward.no-rules')}</td></tr>`;
    }
}

async function addPortForward() {
    const proto = document.getElementById('fw-proto').value;
    const wanPort = document.getElementById('fw-wan-port').value.trim();
    const lanIp = document.getElementById('fw-lan-ip').value.trim();
    const lanPort = document.getElementById('fw-lan-port').value.trim();
    if (!wanPort || !lanIp || !lanPort) {
        alert(t('error.all-fields')); return;
    }
    const body = `action=add&proto=${proto}&wan_port=${wanPort}&lan_ip=${encodeURIComponent(lanIp)}&lan_port=${lanPort}`;
    const res = await api('POST', '/portforward', body);
    alert(res.message || res.error || 'Done');
    refreshForward();
}

async function deletePortForward(idx) {
    const body = `action=delete&idx=${idx}`;
    const res = await api('POST', '/portforward', body);
    alert(res.message || res.error || 'Done');
    refreshForward();
}

// ─── 日志页 ───────────────────────────────────────────────
async function refreshLog() {
    const filter = document.getElementById('log-filter').value.trim();
    let path = '/log';
    if (filter) path += `?filter=${encodeURIComponent(filter)}`;
    const res = await api('GET', path);
    document.getElementById('log-output').textContent = res.log || t('error.no-data');
}

function clearLogFilter() {
    document.getElementById('log-filter').value = '';
    refreshLog();
}

// ─── 工具页 ───────────────────────────────────────────────
async function runPing() {
    const target = document.getElementById('ping-target').value.trim();
    if (!target) { alert(t('error.target-req')); return; }
    const output = document.getElementById('ping-output');
    output.textContent = t('tools.pinging') + ' ' + target + '...';
    const res = await api('POST', '/ping', `target=${encodeURIComponent(target)}&count=4`);
    output.textContent = res.result || res.error || 'No result';
}

// ─── 系统操作 ─────────────────────────────────────────────
async function execAction(action) {
    const result = await api('POST', `/action/${action}`);
    const msg = result.message || result.error || t('action.done');
    alert(result.error ? `❌ ${msg}` : `✅ ${msg}`);
    refreshStatus(); refreshNetwork(); refreshDHCP(); refreshSystem();
}

function confirmReboot() {
    if (confirm(t('action.confirm-reboot'))) {
        api('POST', '/reboot').then(r => {
            alert(r.message || 'Rebooting...');
            setTimeout(() => { document.body.innerHTML = '<div style="text-align:center;padding:100px;color:#4fc3f7"><h1>System is rebooting...</h1></div>'; }, 1000);
        });
    }
}

function confirmPoweroff() {
    if (confirm(t('action.confirm-poweroff'))) {
        api('POST', '/poweroff').then(r => {
            alert(r.message || 'Shutting down...');
            setTimeout(() => { document.body.innerHTML = '<div style="text-align:center;padding:100px;color:#ffa726"><h1>System halted</h1><p>You may now close the VM.</p></div>'; }, 1000);
        });
    }
}

// ─── 自动刷新 ─────────────────────────────────────────────
let autoRefresh = null;
function startAutoRefresh() {
    if (autoRefresh) clearInterval(autoRefresh);
    autoRefresh = setInterval(() => {
        const active = document.querySelector('.tab-content.active');
        if (!active) return;
        switch(active.id) {
            case 'status': refreshStatus(); break;
            case 'network': refreshNetwork(); break;
            case 'dhcp': refreshDHCP(); break;
        }
    }, 5000);
}

// ─── 插件管理 ────────────────────────────────────────────
async function refreshPlugins() {
    const res = await api('GET', '/plugins');
    const container = document.getElementById('plugin-list');
    if (!container) return;
    if (!res.plugins || res.plugins.length === 0) {
        container.innerHTML = `<p>${t('plugins.none')}</p>`; return;
    }
    let html = '';
    for (const p of res.plugins) {
        const checked = (p.enabled === true || p.enabled === 'true') ? 'checked' : '';
        html += `<div class="card plugin-card">
            <div class="plugin-header">
                <div><h3>${p.name}</h3><p class="plugin-desc">${p.desc} <span class="plugin-ver">v${p.version}</span></p></div>
                <label class="switch"><input type="checkbox" ${checked} onchange="togglePlugin('${p.name}',this.checked)"><span class="slider"></span></label>
            </div>
            <div class="plugin-config" id="plugin-config-${p.name}"></div>
        </div>`;
    }
    container.innerHTML = html;
    for (const p of res.plugins) {
        const cfg = document.getElementById('plugin-config-${p.name}');
        if (!cfg) continue;
        if (p.name === 'ddns') {
            const st = await api('GET','/plugin/ddns-status');
            const cf = await api('GET','/plugin/ddns-config');
            cfg.innerHTML = '<details '+(checked?'open':'')+'><summary>${t('plugins.ddns-config')}</summary>'+
                '<div class="form-row">'+
                '<input type="text" id="ddns-domain" placeholder="Domain" value="'+(cf.domain||'')+'">'+
                '<input type="text" id="ddns-token" placeholder="Token" value="'+(cf.token||'')+'">'+
                '<button onclick="saveDdnsConfig()">${t('plugins.save')}</button></div>'+
                '<p style="margin:8px 0;font-size:0.85em;color:#78909c">${t('plugins.ddns-status')}: '+
                (st.last_ip ? 'IP: '+st.last_ip : t('plugins.ddns-wait')) +
                (st.last_log ? '<br><small>'+st.last_log+'</small>' : '') + '</p></details>';
        } else if (p.name === 'adblock') {
            const st = await api('GET','/plugin/adblock-status');
            cfg.innerHTML = '<details '+(checked?'open':'')+'><summary>${t('plugins.adblock-config')}</summary>'+
                '<p style="margin:8px 0;font-size:0.9em">${t('plugins.adblock-stats')}: <strong>'+(st.blocked||0)+'</strong> | ${t('plugins.adblock-entries')}: <strong>'+(st.entries||0)+'</strong></p>'+
                '<div class="form-row"><input type="text" id="adblock-domain" placeholder="example.com">'+
                '<button onclick="addAdblockDomain()">${t('plugins.adblock-add')}</button></div></details>';
        }
    }
    if (typeof applyLang === 'function') applyLang();
}

async function togglePlugin(name, enabled) {
    const a = enabled ? 'enable' : 'disable';
    const r = await api('POST', '/plugin/' + a + '/' + name);
    alert(r.message ? '✅ ' + r.message : (r.error || 'Done'));
    refreshPlugins();
}

async function saveDdnsConfig() {
    const d = document.getElementById('ddns-domain').value.trim();
    const t = document.getElementById('ddns-token').value.trim();
    const r = await api('POST', '/plugin/ddns-config', 'domain='+encodeURIComponent(d)+'&token='+encodeURIComponent(t));
    alert(r.message || r.error || 'Done');
    refreshPlugins();
}

// ─── 第三方 API 工具 ─────────────────────────────────────
async function runDnsLookup() {
    const domain = document.getElementById('dns-domain').value.trim();
    const type = document.getElementById('dns-type').value;
    if (!domain) { alert(t('tools.enter-domain')); return; }
    const el = document.getElementById('dns-output');
    el.textContent = t('status.loading') + '...';
    const res = await api('GET', `/dnslookup?domain=${encodeURIComponent(domain)}&type=${type}`);
    el.textContent = res.result || res.error || 'No result';
}

async function lookupGeoIP() {
    const ip = document.getElementById('geoip-target').value.trim();
    if (!ip) { alert(t('tools.enter-ip')); return; }
    const el = document.getElementById('geoip-result');
    el.style.display = 'block';
    el.innerHTML = `<p>${t('status.loading')}...</p>`;
    const res = await api('GET', `/geoip?ip=${encodeURIComponent(ip)}`);
    if (res.status === 'success') {
        el.innerHTML = `
            <table><tbody>
                <tr><td>IP</td><td><strong>${res.query}</strong></td></tr>
                <tr><td>${t('tools.country')}</td><td>${res.country} - ${res.regionName}</td></tr>
                <tr><td>${t('tools.city')}</td><td>${res.city}</td></tr>
                <tr><td>ISP</td><td>${res.isp || 'N/A'}</td></tr>
                <tr><td>${t('tools.org')}</td><td>${res.org || 'N/A'}</td></tr>
                <tr><td>AS</td><td>${res.as || 'N/A'}</td></tr>
                <tr><td>${t('tools.timezone')}</td><td>${res.timezone || 'N/A'}</td></tr>
                <tr><td>${t('tools.coords')}</td><td>${res.lat}, ${res.lon}</td></tr>
            </tbody></table>
        `;
    } else {
        el.innerHTML = `<p style="color:#ef5350">${res.error || 'Query failed'}</p>`;
    }
}

async function lookupMyIP() {
    const el = document.getElementById('geoip-result');
    el.style.display = 'block';
    el.innerHTML = `<p>${t('status.loading')}...</p>`;
    // First get my public IP
    const ipRes = await api('GET', '/publicip');
    if (ipRes.ip) {
        document.getElementById('geoip-target').value = ipRes.ip;
        // Then lookup geo
        const geoRes = await api('GET', `/geoip?ip=${encodeURIComponent(ipRes.ip)}`);
        if (geoRes.status === 'success') {
            el.innerHTML = `
                <p style="margin-bottom:8px"><strong>${t('tools.public-ip')}: ${geoRes.query}</strong></p>
                <table><tbody>
                    <tr><td>${t('tools.country')}</td><td>${geoRes.country} - ${geoRes.regionName}</td></tr>
                    <tr><td>${t('tools.city')}</td><td>${geoRes.city}</td></tr>
                    <tr><td>ISP</td><td>${geoRes.isp || 'N/A'}</td></tr>
                    <tr><td>${t('tools.org')}</td><td>${geoRes.org || 'N/A'}</td></tr>
                    <tr><td>AS</td><td>${geoRes.as || 'N/A'}</td></tr>
                </tbody></table>
            `;
        } else {
            el.innerHTML = `<p>${t('tools.public-ip')}: ${ipRes.ip}<br>${geoRes.error || ''}</p>`;
        }
    } else {
        el.innerHTML = `<p style="color:#ef5350">${ipRes.error || 'Cannot detect IP'}</p>`;
    }
}

// ─── 插件商店 ────────────────────────────────────────────
async function refreshPluginStore() {
    const el = document.getElementById('plugin-store');
    if (!el) return;
    const res = await api('GET', '/plugin-available');
    if (res.plugins && res.plugins.length > 0) {
        let html = `<p style="margin-bottom:8px;font-size:0.85em;color:#78909c">${t('plugins.store-source')}: ${res.source || 'online'}</p>
        <table><thead><tr>
            <th data-i18n="plugins.store-name">名称</th>
            <th data-i18n="plugins.store-desc">描述</th>
            <th data-i18n="plugins.store-version">版本</th>
            <th data-i18n="table.action">操作</th>
        </tr></thead><tbody>`;
        for (const p of res.plugins) {
            const url = p.url || '';
            html += `<tr>
                <td><strong>${p.name}</strong></td>
                <td>${p.desc}</td>
                <td>${p.version||'1.0'}</td>
                <td><button class="btn-sm" onclick="installPlugin('${p.name}','${url}')" ${url ? '' : 'disabled'}>${t('plugins.store-install')}</button></td>
            </tr>`;
        }
        html += '</tbody></table>';
        el.innerHTML = html;
        if (typeof applyLang === 'function') applyLang();
    } else {
        el.innerHTML = `<p>${t('plugins.store-unavailable')}</p>`;
    }
}

async function installPlugin(name, url) {
    if (!confirm(t('plugins.store-confirm').replace('{name}', name))) return;
    const body = `name=${encodeURIComponent(name)}&url=${encodeURIComponent(url)}`;
    const res = await api('POST', '/plugin-install', body);
    alert(res.message || res.error || 'Done');
    refreshPlugins();
}

async function addAdblockDomain() {
    const d = document.getElementById('adblock-domain').value.trim();
    if (!d) { alert(t('plugins.adblock-enter')); return; }
    const r = await api('POST', '/plugin/adblock-add', 'domain='+encodeURIComponent(d));
    alert(r.message || r.error || 'Done');
    refreshPlugins();
}

// ─── 初始化 ───────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    setTimeout(() => {
        refreshStatus();
        refreshNetwork();
        refreshDHCP();
        refreshForward();
        refreshPlugins();
        refreshSystem();
        startAutoRefresh();
    }, 50);
});

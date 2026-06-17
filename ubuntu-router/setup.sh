#!/bin/bash
# ============================================================
#  Reasonix Router — Ubuntu Server 一键配置脚本
#  在已安装的 Ubuntu 24.04 Server 上运行，变成软路由
#
#  用法:
#    wget -O - https://git.io/xxx | sudo bash
#     或
#    sudo ./setup.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}→${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error(){ echo -e "${RED}✗${NC} $1"; exit 1; }

# ─── 检查 root ────────────────────────────────────────────
[ "$EUID" -eq 0 ] || error "请用 sudo 运行"

# ─── 检测 WAN/LAN 接口 ────────────────────────────────────
detect_interfaces() {
    info "检测网络接口..."
    ALL=$(ip -o link show | grep -v lo | awk -F': ' '{print $2}' | grep -v 'br-\|docker\|veth\|tun\|tap')
    WAN=$(echo "$ALL" | head -1)
    LAN=$(echo "$ALL" | tail -1)
    [ "$WAN" = "$LAN" ] && LAN=""  # 单网口
    echo "  WAN: $WAN (DHCP)"
    echo "  LAN: $LAN (192.168.2.1)"
}

# ─── 安装包 ────────────────────────────────────────────────
install_packages() {
    info "安装必要软件包..."
    apt update -qq
    # iptables-persistent 需要预先配置 debconf 避免交互
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections 2>/dev/null || true
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt install -y -qq dnsmasq lighttpd iptables-persistent net-tools curl wget 2>&1 | tail -5
    ok "软件包安装完成"
}

# ─── 配置网络 ──────────────────────────────────────────────
configure_network() {
    info "配置网络..."

    # netplan
    cat > /etc/netplan/01-router.yaml << NETEOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $WAN:
      dhcp4: true
      dhcp4-overrides: { route-metric: 100 }
NETEOF
    if [ -n "$LAN" ]; then
        cat >> /etc/netplan/01-router.yaml << NETEOF
    $LAN:
      addresses: [192.168.2.1/24]
      dhcp4: false
NETEOF
    fi
    netplan apply 2>/dev/null || true

    # IP 转发
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-router.conf
    echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-router.conf
    sysctl -p /etc/sysctl.d/99-router.conf 2>/dev/null || true
    ok "网络配置完成"
}

# ─── 配置 DHCP ─────────────────────────────────────────────
configure_dhcp() {
    [ -z "$LAN" ] && warn "无 LAN 接口，跳过 DHCP" && return
    info "配置 DHCP/DNS..."

    cat > /etc/dnsmasq.conf << DNSEOF
interface=$LAN
bind-interfaces
dhcp-range=192.168.2.100,192.168.2.200,12h
dhcp-option=3,192.168.2.1
dhcp-option=6,192.168.2.1
dhcp-authoritative
server=114.114.114.114
server=8.8.8.8
server=223.5.5.5
cache-size=500
local=/router/
address=/router/192.168.2.1
log-dhcp
log-facility=/var/log/dnsmasq.log
DNSEOF

    systemctl enable dnsmasq 2>/dev/null || true
    systemctl restart dnsmasq 2>/dev/null || true
    ok "DHCP 配置完成"
}

# ─── 配置防火墙 ────────────────────────────────────────────
configure_firewall() {
    info "配置防火墙/NAT..."

    iptables -t nat -A POSTROUTING -o $WAN -j MASQUERADE
    iptables -A FORWARD -i $LAN -o $WAN -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -i $WAN -o $LAN -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -i $LAN -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -i $WAN -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -i $WAN -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -i $WAN -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i $WAN -j DROP

    netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    ok "防火墙配置完成"
}

# ─── 部署 Web UI ──────────────────────────────────────────
deploy_webui() {
    info "部署 Web UI..."
    mkdir -p /var/www/html/cgi-bin

    # Web UI 文件直接嵌入脚本 (内联 base64)
    echo "  生成 index.html..."
    cat > /var/www/html/index.html << 'INDEX'
<!DOCTYPE html><html lang=zh-CN><meta charset=UTF-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Reasonix Router</title>
<link rel=stylesheet href=/style.css>
<div class=container>
<header><div class=header-top><h1>🛜 Reasonix Router</h1>
<button id=lang-btn class=lang-btn onclick=toggleLang()>English</button></div>
<p class=subtitle>Ubuntu 软路由系统</p></header>
<nav class=tabs>
<button class="tab active" onclick="showTab('status')" data-i18n=tab.status>📊 状态</button>
<button class=tab onclick="showTab('network')" data-i18n=tab.network>🌐 网络</button>
<button class=tab onclick="showTab('dhcp')" data-i18n=tab.dhcp>📡 DHCP</button>
<button class=tab onclick="showTab('system')" data-i18n=tab.system>⚙️ 系统</button>
</nav>
<div id=status class="tab-content active">
<h2 data-i18n=status.title>系统状态</h2>
<div class=card-grid>
<div class=card><h3 data-i18n=status.uptime>运行时间</h3><p id=uptime>加载中...</p></div>
<div class=card><h3 data-i18n=status.memory>内存</h3><p id=memory>加载中...</p></div>
<div class=card><h3 data-i18n=status.load>负载</h3><p id=loadavg>加载中...</p></div>
</div>
<div class=card><h3 data-i18n=status.interfaces>接口</h3>
<table id=interfaces><thead><tr><th data-i18n=table.interface>接口<th data-i18n=table.ip>IP<th data-i18n=table.status>状态</table></div></div>
<div id=network class=tab-content>
<h2 data-i18n=network.title>网络</h2>
<div class=card><h3 data-i18n=network.routing>路由表</h3><pre id=routing-table>加载中...</pre></div>
<div class=card><h3 data-i18n=network.nat>NAT</h3><pre id=nat-rules>加载中...</pre></div></div>
<div id=dhcp class=tab-content>
<h2 data-i18n=dhcp.title>DHCP</h2>
<div class=card><h3 data-i18n=dhcp.leases>租约</h3>
<table id=dhcp-leases><thead><tr><th data-i18n=table.mac>MAC<th data-i18n=table.ip>IP<th data-i18n=dhcp.hostname>主机名<th data-i18n=dhcp.remaining>剩余</table></div></div>
<div id=system class=tab-content>
<h2 data-i18n=system.title>系统</h2>
<div class=card><h3 data-i18n=system.info>信息</h3><pre id=sysinfo>加载中...</pre></div>
<div class=card><h3 data-i18n=system.actions>操作</h3>
<div class=actions>
<button onclick=\"api('POST','/cgi-bin/api.sh?path=restart-dhcp')\">重启 DHCP</button>
<button onclick=\"api('POST','/cgi-bin/api.sh?path=flush-conntrack')\">清空连接</button>
<button onclick=\"confirm('重启系统?')&&api('POST','/cgi-bin/api.sh?path=reboot')\">重启</button>
<button onclick=\"confirm('关机?')&&api('POST','/cgi-bin/api.sh?path=poweroff')\">关机</button>
</div></div></div>
<footer><p>Reasonix Router &copy; 2025</p></footer>
<script src=/lang.js></script><script src=/app.js></script>
INDEX

    echo "  生成 style.css..."
    cat > /var/www/html/style.css << 'CSS'
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0f1923;color:#e0e0e0;min-height:100vh}
.container{max-width:1000px;margin:0 auto;padding:20px}
header{padding:20px 0;border-bottom:1px solid #1e3a5f;margin-bottom:20px}
.header-top{display:flex;justify-content:space-between;align-items:center}
h1{font-size:1.8em;color:#4fc3f7}
.subtitle{color:#78909c;font-size:.9em;margin-top:5px}
.lang-btn{background:0;border:1px solid #2a5a8a;color:#4fc3f7;padding:6px 16px;border-radius:4px;cursor:pointer}
.lang-btn:hover{background:#1976d2;color:#fff}
.tabs{display:flex;gap:8px;margin-bottom:20px;flex-wrap:wrap}
.tab{background:#1a2d3d;border:1px solid #2a4a6a;color:#b0c4d8;padding:10px 20px;border-radius:6px;cursor:pointer}
.tab:hover{background:#243b50}.tab.active{background:#1976d2;color:#fff}
.tab-content{display:none}.tab-content.active{display:block}
.card{background:#1a2d3d;border:1px solid #2a4a6a;border-radius:8px;padding:20px;margin-bottom:16px}
.card h3{color:#4fc3f7;margin-bottom:12px}
.card-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-bottom:16px}
table{width:100%;border-collapse:collapse}
th{text-align:left;padding:10px 8px;border-bottom:2px solid #2a4a6a;color:#78909c;font-weight:500;font-size:.85em}
td{padding:10px 8px;border-bottom:1px solid #1e3a5f;font-size:.9em}
tr:hover td{background:#1f3447}
pre{background:#0a1520;border:1px solid #1e3a5f;border-radius:4px;padding:12px;font-family:monospace;font-size:.85em;color:#a8d8ea;overflow-x:auto}
.actions{display:flex;flex-wrap:wrap;gap:10px}
.actions button{background:#1e3a5f;border:1px solid #2a5a8a;color:#b0c4d8;padding:8px 20px;border-radius:4px;cursor:pointer}
.actions button:hover{background:#1976d2;color:#fff}
.status-up{color:#66bb6a}.status-down{color:#ef5350}
footer{text-align:center;padding:20px;color:#546e7a;font-size:.85em;border-top:1px solid #1e3a5f;margin-top:40px}
@media(max-width:600px){.tabs{flex-direction:column}.tab{width:100%}}
CSS

    echo "  生成 app.js..."
    cat > /var/www/html/app.js << 'APPJS'
const API='/cgi-bin/api.sh?path=';
async function api(m,p,b){
try{const r=await fetch(API+p.replace(/^\//,''),{method:m,body:b,
headers:b?{'Content-Type':'application/x-www-form-urlencoded'}:{}})
const t=await r.text();try{return JSON.parse(t)}catch(e){return{error:t}}}
catch(e){return{error:e.message}}}
function showTab(n){
document.querySelectorAll('.tab-content,.tab').forEach(e=>e.classList.remove('active'))
const t=document.getElementById(n);if(t)t.classList.add('active')
const b=document.querySelector(\`.tab[onclick*="\${n}"]\`);if(b)b.classList.add('active')
switch(n){case'status':refreshStatus();break
case'network':refreshNetwork();break
case'dhcp':refreshDHCP();break
case'system':refreshSystem();break}}
async function refreshStatus(){
const u=await api('GET','/uptime');document.getElementById('uptime').textContent=u.uptime||'N/A'
const m=await api('GET','/memory');document.getElementById('memory').textContent=m.total?(m.used/1024).toFixed(1)+'/'+(m.total/1024).toFixed(1)+' MB':'N/A'
const l=await api('GET','/loadavg');document.getElementById('loadavg').textContent=l.loadavg||'N/A'
const i=await api('GET','/interfaces')
const tb=document.querySelector('#interfaces tbody')
if(i.interfaces&&i.interfaces.length>0)
tb.innerHTML=i.interfaces.map(x=>'<tr><td><strong>'+x.name+'</strong></td><td>'+(x.ip||'-')+'</td><td class="'+(x.up?'status-up':'status-down')+'">'+(x.up?'🟢 运行中':'🔴 关闭')+'</td></tr>').join('')
else tb.innerHTML='<tr><td colspan="3">无数据</td></tr>'}
async function refreshNetwork(){
const r=await api('GET','/route');document.getElementById('routing-table').textContent=r.route||'N/A'
const n=await api('GET','/nat');document.getElementById('nat-rules').textContent=n.nat||'N/A'}
async function refreshDHCP(){
const l=await api('GET','/dhcp-leases')
const tb=document.querySelector('#dhcp-leases tbody')
if(l.leases&&l.leases.length>0)
tb.innerHTML=l.leases.map(x=>'<tr><td>'+x.mac+'</td><td>'+x.ip+'</td><td>'+(x.hostname||'-')+'</td><td>'+(x.remaining||'-')+'</td></tr>').join('')
else tb.innerHTML='<tr><td colspan="4">暂无租约</td></tr>'}
async function refreshSystem(){
const i=await api('GET','/sysinfo');document.getElementById('sysinfo').textContent=i.info||'N/A'}
document.addEventListener('DOMContentLoaded',()=>{setTimeout(()=>{refreshStatus();refreshNetwork();refreshDHCP();refreshSystem()},100)})
APPJS

    echo "  生成 lang.js..."
    cat > /var/www/html/lang.js << 'LANG'
const I18N={zh:{
'page.title':'Reasonix Router - 管理控制台','header.subtitle':'Ubuntu 软路由系统',
'tab.status':'📊 状态','tab.network':'🌐 网络','tab.dhcp':'📡 DHCP','tab.system':'⚙️ 系统',
'status.title':'系统状态','status.uptime':'运行时间','status.memory':'内存','status.load':'负载','status.interfaces':'网络接口','status.loading':'加载中...','status.unavailable':'不可用',
'table.interface':'接口','table.ip':'IP 地址','table.mac':'MAC 地址','table.status':'状态',
'network.title':'网络配置','network.routing':'路由表','network.nat':'NAT 规则',
'dhcp.title':'DHCP 服务','dhcp.leases':'活跃租约','dhcp.hostname':'主机名','dhcp.remaining':'剩余时间','dhcp.no-leases':'暂无租约',
'system.title':'系统管理','system.info':'系统信息','system.actions':'操作',
'lang.switch':'English','footer.text':'基于 Ubuntu 的软路由系统','error.no-data':'无数据',
},en:{
'page.title':'Reasonix Router','header.subtitle':'Ubuntu-based Soft Router',
'tab.status':'📊 Status','tab.network':'🌐 Network','tab.dhcp':'📡 DHCP','tab.system':'⚙️ System',
'status.title':'System Status','status.uptime':'Uptime','status.memory':'Memory','status.load':'CPU Load','status.interfaces':'Interfaces','status.loading':'Loading...','status.unavailable':'N/A',
'table.interface':'Interface','table.ip':'IP','table.mac':'MAC','table.status':'Status',
'network.title':'Network','network.routing':'Routing Table','network.nat':'NAT Rules',
'dhcp.title':'DHCP','dhcp.leases':'Active Leases','dhcp.hostname':'Hostname','dhcp.remaining':'Remaining','dhcp.no-leases':'No leases',
'system.title':'System','system.info':'Info','system.actions':'Actions',
'lang.switch':'中文','footer.text':'Ubuntu Router OS','error.no-data':'No data',
}};
let currentLang=localStorage.getItem('reasonix-lang')||'zh';
function t(k){return(I18N[currentLang]||I18N.zh)[k]||k}
function applyLang(){document.documentElement.lang=currentLang;document.title=t('page.title')
document.querySelectorAll('[data-i18n]').forEach(el=>{el.textContent=t(el.getAttribute('data-i18n'))})
document.getElementById('lang-btn').textContent=t('lang.switch')
localStorage.setItem('reasonix-lang',currentLang)}
function toggleLang(){currentLang=currentLang==='zh'?'en':'zh';applyLang();location.reload()}
document.addEventListener('DOMContentLoaded',applyLang)
LANG

    echo "  生成 API 后端..."
    cat > /var/www/html/cgi-bin/api.sh << 'APISH'
#!/bin/bash
echo "Content-Type: application/json; charset=utf-8"
echo ""
RQ="${QUERY_STRING#*path=}"; RQ="${RQ%%&*}"; RQ=$(echo "$RQ"|sed 's/%2F/\//g;s/%20/ /g')
METHOD="${REQUEST_METHOD:-GET}"
POST_DATA=""
[ "$METHOD" = "POST" ] && [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null && POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
read_param(){ echo "$POST_DATA"|sed 's/&/\n/g'|grep "^${1}="|head -1|cut -d= -f2-|sed 's/+/ /g'; }
json_escape(){ echo "$1"|sed 's/"/\\"/g'|tr '\n' ' '; }
case "$RQ" in
  uptime) u=$(cat /proc/uptime|awk '{print $1}')
    d=$(echo "$u/86400"|bc 2>/dev/null); h=$(echo "($u%86400)/3600"|bc 2>/dev/null); m=$(echo "($u%3600)/60"|bc 2>/dev/null)
    echo "{\"uptime\":\"${d:-0}d ${h:-0}h ${m:-0}m\"}" ;;
  memory) t=$(grep MemTotal /proc/meminfo|awk '{print $2}')
    f=$(grep MemFree /proc/meminfo|awk '{print $2}'); b=$(grep Buffers /proc/meminfo|awk '{print $2}'); c=$(grep Cached /proc/meminfo|awk '{print $2}')
    echo "{\"total\":$t,\"used\":$((t-f-b-c)),\"free\":$f}" ;;
  loadavg) echo "{\"loadavg\":\"$(cat /proc/loadavg|awk '{print $1,$2,$3}')\"}" ;;
  interfaces) out=""; for d in /sys/class/net/*/; do [ -d "$d" ]||continue; n=$(basename "$d"); [ "$n" = "lo" ]&&continue
    a=$(cat ${d}address 2>/dev/null); o=$(cat ${d}operstate 2>/dev/null)
    ip=$(ip -4 addr show "$n" 2>/dev/null|grep 'inet '|head -1|awk '{print $2}'|cut -d/ -f1); [ -z "$ip" ]&&ip="-"
    up="false"; [ "$o" = "up" ]&&up="true"; out="${out}{\"name\":\"$n\",\"ip\":\"$ip\",\"mac\":\"$a\",\"up\":$up},"
    done; echo "{\"interfaces\":[${out%%,}]}" ;;
  route) echo "{\"route\":\"$(json_escape "$(ip route show 2>/dev/null)")\"}" ;;
  nat) echo "{\"nat\":\"$(json_escape "$(iptables -t nat -L -n 2>/dev/null||echo N/A)")\"}" ;;
  sysinfo) echo "{\"info\":\"Hostname: $(hostname)\\nKernel: $(uname -r)\\nUptime: $(cat /proc/uptime|awk '{printf \"%ds\",$1}')\"}" ;;
  dhcp-leases) ls=""; [ -f /var/lib/misc/dnsmasq.leases ] && ls=$(cat /var/lib/misc/dnsmasq.leases|while read e m i h r; do
    [ -z "$m" ]&&continue; now=$(date +%s); rem=$((e-now)); [ "$rem" -lt 0 ]&&continue; [ "$rem" -gt 86400 ]&&rs=">24h"||rs="${rem}s"
    echo "{\"mac\":\"$m\",\"ip\":\"$i\",\"hostname\":\"$h\",\"remaining\":\"$rs\"},"
    done); echo "{\"leases\":[${ls%%,}]}" ;;
  restart-dhcp) systemctl restart dnsmasq 2>/dev/null; echo '{"message":"DHCP restarted"}' ;;
  flush-conntrack) echo f>/proc/net/nf_conntrack 2>/dev/null; echo '{"message":"Done"}' ;;
  reboot) (sleep 1; reboot)& echo '{"message":"Rebooting..."}' ;;
  poweroff) (sleep 1; poweroff)& echo '{"message":"Shutting down..."}' ;;
  *) echo "{\"error\":\"Unknown: $RQ\"}" ;;
esac
APISH
    chmod +x /var/www/html/cgi-bin/api.sh

    # 配置 lighttpd

    # 配置 lighttpd
    cat > /etc/lighttpd/lighttpd.conf << LIGHTEOF
server.document-root = "/var/www/html"
server.port = 80
server.bind = "0.0.0.0"
index-file.names = ("index.html")
mimetype.assign = (".html"=>"text/html",".css"=>"text/css",".js"=>"application/javascript")
server.modules = ("mod_cgi")
cgi.assign = (".sh" => "/bin/bash")
LIGHTEOF

    systemctl enable lighttpd 2>/dev/null || true
    systemctl restart lighttpd 2>/dev/null || true
    ok "Web UI 部署完成"
}

# ─── 显示结果 ──────────────────────────────────────────────
show_result() {
    IP=$(ip -4 addr show $LAN 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
    [ -z "$IP" ] && IP="192.168.2.1"
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  ✅ Reasonix Router 配置完成!            ║"
    echo "║                                         ║"
    echo "║  WAN: $WAN (DHCP)"
    echo "║  LAN: $LAN ($IP)"
    echo "║  Web: http://$IP"
    echo "║  SSH: 本机用户名@$IP"
    echo "║                                         ║"
    echo "║  建议重启以应用所有更改                   ║"
    echo "║  sudo reboot                            ║"
    echo "╚══════════════════════════════════════════╝"
}

# ─── 主流程 ──────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Reasonix Router — Ubuntu 一键配置      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

detect_interfaces
install_packages
configure_network
configure_dhcp
configure_firewall
deploy_webui
show_result

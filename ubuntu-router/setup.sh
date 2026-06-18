#!/bin/sh
# ============================================================
#  Reasonix Router — 多系统兼容一键配置脚本
#  支持: Ubuntu/Debian/CentOS/Arch/Alpine/openSUSE
#  自动检测操作系统、包管理器、服务管理器
#
#  用法:
#    wget -O - https://git.io/xxx | sudo sh
#    或
#    sudo sh setup.sh
# ============================================================

# ─── ANSI 颜色 ────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf "${CYAN}→${NC} %s\n" "$1"; }
ok()    { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
error() { printf "${RED}✗${NC} %s\n" "$1"; exit 1; }

# ─── 检查 root ────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || error "请用 root 运行 (sudo su)"

# ============================================================
#  第一步: 检测操作系统
# ============================================================
detect_os() {
    OS=""
    PKG_MGR=""
    PKG_UPDATE=""
    PKG_INSTALL=""
    SERVICE_MGR=""
    NET_MGR=""

    # 发行版检测
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif command -v pacman >/dev/null 2>&1; then
        OS="arch"
    elif command -v apk >/dev/null 2>&1; then
        OS="alpine"
    else
        OS="unknown"
    fi

    # 包管理器检测
    case "$OS" in
        ubuntu|debian|linuxmint|elementary|pop|kali)
            PKG_MGR="apt"; OS="debian"
            PKG_UPDATE="apt update -qq"
            PKG_INSTALL="env DEBIAN_FRONTEND=noninteractive apt install -y -qq"
            # iptables-persistent 预配置
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections 2>/dev/null || true
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections 2>/dev/null || true
            ;;
        rhel|centos|fedora|rocky|alma|amzn)
            PKG_MGR="dnf"; OS="rhel"
            PKG_UPDATE="dnf check-update -q 2>/dev/null || true"
            PKG_INSTALL="dnf install -y -q"
            command -v dnf >/dev/null 2>&1 || PKG_MGR="yum"
            command -v yum >/dev/null 2>&1 || PKG_MGR="dnf"
            [ "$PKG_MGR" = "yum" ] && PKG_INSTALL="yum install -y -q"
            ;;
        arch|manjaro|endeavouros)
            OS="arch"; PKG_MGR="pacman"
            PKG_UPDATE="pacman -Sy --noconfirm 2>/dev/null || true"
            PKG_INSTALL="pacman -S --noconfirm --needed"
            ;;
        alpine)
            PKG_MGR="apk"
            PKG_UPDATE="apk update -q"
            PKG_INSTALL="apk add -q"
            ;;
        opensuse*|suse)
            OS="suse"; PKG_MGR="zypper"
            PKG_UPDATE="zypper refresh -q"
            PKG_INSTALL="zypper install -y -q"
            ;;
        *)
            error "不支持的系统: $OS"
            ;;
    esac

    # 服务管理器检测
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MGR="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        SERVICE_MGR="openrc"
    elif command -v service >/dev/null 2>&1; then
        SERVICE_MGR="sysvinit"
    else
        SERVICE_MGR="none"
    fi

    # 网络管理器检测
    if [ -d /etc/netplan ]; then
        NET_MGR="netplan"
    elif command -v nmcli >/dev/null 2>&1; then
        NET_MGR="networkmanager"
    elif [ -f /etc/systemd/networkd.conf ]; then
        NET_MGR="systemd-networkd"
    elif [ -f /etc/network/interfaces ]; then
        NET_MGR="ifupdown"
    else
        NET_MGR="unknown"
    fi

    echo "  系统: $OS"
    echo "  包管理器: $PKG_MGR"
    echo "  服务管理器: $SERVICE_MGR"
    echo "  网络管理器: $NET_MGR"
}

# ============================================================
#  第二步: 检测网络接口
# ============================================================
detect_interfaces() {
    info "检测网络接口..."
    # 获取所有物理网卡 (排除虚拟接口)
    ALL=$(ip -o link show | grep -v lo | awk -F': ' '{print $2}' | \
          grep -v 'br-\|docker\|veth\|tun\|tap\|virbr\|wg[0-9]')
    WAN=$(echo "$ALL" | head -1)
    LAN=$(echo "$ALL" | tail -1)
    [ "$WAN" = "$LAN" ] && LAN=""
    echo "  WAN: $WAN (DHCP)"
    echo "  LAN: $LAN (192.168.2.1)"
}

# ============================================================
#  第三步: 安装软件包
# ============================================================
install_packages() {
    info "安装软件包..."

    # 定义各系统需要的包名
    case "$OS" in
        debian)
            DEPS="dnsmasq lighttpd iptables curl"
            ;;
        rhel|centos|fedora)
            DEPS="dnsmasq lighttpd iptables-services curl"
            # RHEL 需要 EPEL
            command -v epel-release >/dev/null 2>&1 || $PKG_INSTALL epel-release 2>/dev/null || true
            ;;
        arch)
            DEPS="dnsmasq lighttpd iptables curl"
            ;;
        alpine)
            DEPS="dnsmasq lighttpd iptables curl"
            ;;
        suse)
            DEPS="dnsmasq lighttpd iptables curl"
            ;;
    esac

    $PKG_UPDATE 2>&1 | tail -1 || true
    $PKG_INSTALL $DEPS 2>&1 | tail -3
    ok "软件包安装完成"
}

# ============================================================
#  第四步: 配置网络
# ============================================================
configure_network() {
    info "配置网络..."

    case "$NET_MGR" in
        netplan)
            cat > /etc/netplan/01-router.yaml << NETEOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $WAN:
      dhcp4: true
      dhcp4-overrides: { route-metric: 100 }
NETEOF
            [ -n "$LAN" ] && cat >> /etc/netplan/01-router.yaml << NETEOF
    $LAN:
      addresses: [192.168.2.1/24]
      dhcp4: false
NETEOF
            netplan apply 2>/dev/null || true
            ;;
        ifupdown)
            cat >> /etc/network/interfaces << IFEOF
auto $WAN
iface $WAN inet dhcp
IFEOF
            [ -n "$LAN" ] && cat >> /etc/network/interfaces << IFEOF
auto $LAN
iface $LAN inet static
  address 192.168.2.1/24
IFEOF
            ifup -a 2>/dev/null || true
            ;;
        networkmanager)
            nmcli device set "$WAN" managed yes 2>/dev/null || true
            [ -n "$LAN" ] && nmcli connection add type ethernet ifname "$LAN" con-name lan \
                ipv4.method manual ipv4.addresses 192.168.2.1/24 2>/dev/null || true
            ;;
        systemd-networkd)
            cat > /etc/systemd/network/10-wan.network << NTEOF
[Match]
Name=$WAN
[Network]
DHCP=ipv4
NTEOF
            [ -n "$LAN" ] && cat > /etc/systemd/network/20-lan.network << NTEOF
[Match]
Name=$LAN
[Network]
Address=192.168.2.1/24
NTEOF
            systemctl restart systemd-networkd 2>/dev/null || true
            ;;
    esac

    # IP 转发 (所有系统通用)
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-router.conf 2>/dev/null
    echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-router.conf 2>/dev/null
    sysctl -p /etc/sysctl.d/99-router.conf 2>/dev/null || echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
    ok "网络配置完成"
}

# ============================================================
#  第五步: 配置 DHCP/DNS
# ============================================================
configure_dhcp() {
    [ -z "$LAN" ] && warn "无 LAN 接口，跳过 DHCP" && return
    info "配置 DHCP/DNS..."
    command -v dnsmasq >/dev/null 2>&1 || { warn "dnsmasq 未安装，跳过 DHCP"; return; }

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

    case "$SERVICE_MGR" in
        systemd) systemctl enable dnsmasq 2>/dev/null && systemctl restart dnsmasq 2>/dev/null || true ;;
        openrc)  rc-update add dnsmasq default 2>/dev/null && rc-service dnsmasq start 2>/dev/null || true ;;
        sysvinit) update-rc.d dnsmasq defaults 2>/dev/null && service dnsmasq restart 2>/dev/null || true ;;
    esac
    ok "DHCP/DNS 配置完成"
}

# ============================================================
#  第六步: 配置防火墙
# ============================================================
configure_firewall() {
    info "配置防火墙/NAT..."
    local OS="$1"

    # firewalld (RHEL/CentOS/Fedora)
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-masquerade 2>/dev/null || true
        firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i "$LAN" -o "$WAN" -j ACCEPT 2>/dev/null || true
        firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i "$WAN" -o "$LAN" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        ok "firewalld NAT 配置完成"
        return
    fi
    info "配置防火墙/NAT..."

    # 检测防火墙工具
    FW="iptables"
    command -v iptables >/dev/null 2>&1 || FW="nft"

    if [ "$FW" = "iptables" ]; then
        # 基础 NAT
        iptables -t nat -A POSTROUTING -o "$WAN" -j MASQUERADE 2>/dev/null || true
        # 转发
        [ -n "$LAN" ] && iptables -A FORWARD -i "$LAN" -o "$WAN" -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -i "$WAN" -o "$LAN" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        # INPUT 规则
        [ -n "$LAN" ] && iptables -A INPUT -i "$LAN" -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -i "$WAN" -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -i "$WAN" -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -i "$WAN" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -i "$WAN" -j DROP 2>/dev/null || true

        # 保存规则 (各系统不同)
        case "$OS" in
            debian)
                command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save 2>/dev/null || \
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
                ;;
            rhel|centos)
                iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
                ;;
            arch)
                iptables-save > /etc/iptables/iptables.rules 2>/dev/null || true
                systemctl enable iptables 2>/dev/null || true
                ;;
            alpine)
                iptables-save > /etc/iptables/rules-save 2>/dev/null || true
                rc-update add iptables 2>/dev/null || true
                ;;
        esac
    fi

    ok "防火墙配置完成"
}

# ============================================================
#  第七步: 部署 Web UI (内联全部文件)
# ============================================================
deploy_webui() {
    info "部署 Web UI..."
    mkdir -p /var/www/html/cgi-bin

    # ── index.html ──
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html><html lang=zh-CN><meta charset=UTF-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Reasonix Router</title><link rel=stylesheet href=/style.css>
<div class=container>
<header><div class=header-top><h1>🛜 Reasonix Router</h1>
<button id=lang-btn class=lang-btn onclick=toggleLang()>English</button></div>
<p class=subtitle>Multi-OS Router System</p></header>
<nav class=tabs>
<button class="tab active" onclick="showTab('status')" data-i18n=tab.status>📊 状态</button>
<button class=tab onclick="showTab('network')" data-i18n=tab.network>🌐 网络</button>
<button class=tab onclick="showTab('dhcp')" data-i18n=tab.dhcp>📡 DHCP</button>
<button class=tab onclick="showTab('system')" data-i18n=tab.system>⚙️ 系统</button></nav>
<div id=status class="tab-content active"><h2 data-i18n=status.title>系统状态</h2>
<div class=card-grid><div class=card><h3 data-i18n=status.uptime>运行时间</h3><p id=uptime>加载中...</p></div>
<div class=card><h3 data-i18n=status.memory>内存</h3><p id=memory>加载中...</p></div>
<div class=card><h3 data-i18n=status.load>负载</h3><p id=loadavg>加载中...</p></div></div>
<div class=card><h3 data-i18n=status.interfaces>接口</h3>
<table id=interfaces><thead><tr><th data-i18n=table.interface>接口<th data-i18n=table.ip>IP<th data-i18n=table.status>状态</table></div></div>
<div id=network class=tab-content><h2 data-i18n=network.title>网络</h2>
<div class=card><h3 data-i18n=network.routing>路由表</h3><pre id=routing-table>加载中...</pre></div>
<div class=card><h3 data-i18n=network.nat>NAT</h3><pre id=nat-rules>加载中...</pre></div></div>
<div id=dhcp class=tab-content><h2 data-i18n=dhcp.title>DHCP</h2>
<div class=card><h3 data-i18n=dhcp.leases>租约</h3>
<table id=dhcp-leases><thead><tr><th data-i18n=table.mac>MAC<th data-i18n=table.ip>IP<th data-i18n=dhcp.hostname>主机名<th data-i18n=dhcp.remaining>剩余</table></div></div>
<div id=system class=tab-content><h2 data-i18n=system.title>系统</h2>
<div class=card><h3 data-i18n=system.info>信息</h3><pre id=sysinfo>加载中...</pre></div>
<div class=card><h3 data-i18n=system.actions>操作</h3>
<div class=actions>
<button onclick="api('POST','/cgi-bin/api.sh?path=restart-dhcp')">重启 DHCP</button>
<button onclick="api('POST','/cgi-bin/api.sh?path=flush-conntrack')">清空连接</button>
<button onclick="confirm('重启?')&&api('POST','/cgi-bin/api.sh?path=reboot')">重启</button>
<button onclick="confirm('关机?')&&api('POST','/cgi-bin/api.sh?path=poweroff')">关机</button>
</div></div></div>
<footer><p>Reasonix Router</p></footer>
<script src=/lang.js></script><script src=/app.js></script>
EOF

    # ── style.css (精简) ──
    cat > /var/www/html/style.css << 'EOF'
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0f1923;color:#e0e0e0;min-height:100vh}
.container{max-width:1000px;margin:0 auto;padding:20px}
header{padding:20px 0;border-bottom:1px solid #1e3a5f;margin-bottom:20px}
.header-top{display:flex;justify-content:space-between;align-items:center}
h1{font-size:1.8em;color:#4fc3f7}.subtitle{color:#78909c;font-size:.9em;margin-top:5px}
.lang-btn{background:0;border:1px solid #2a5a8a;color:#4fc3f7;padding:6px 16px;border-radius:4px;cursor:pointer}
.lang-btn:hover{background:#1976d2;color:#fff}
.tabs{display:flex;gap:8px;margin-bottom:20px;flex-wrap:wrap}
.tab{background:#1a2d3d;border:1px solid #2a4a6a;color:#b0c4d8;padding:10px 20px;border-radius:6px;cursor:pointer}
.tab:hover,.tab.active{background:#1976d2;color:#fff}
.tab-content{display:none}.tab-content.active{display:block}
.card{background:#1a2d3d;border:1px solid #2a4a6a;border-radius:8px;padding:20px;margin-bottom:16px}
.card h3{color:#4fc3f7;margin-bottom:12px}
.card-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-bottom:16px}
table{width:100%;border-collapse:collapse}
th{text-align:left;padding:10px 8px;border-bottom:2px solid #2a4a6a;color:#78909c;font-weight:500}
td{padding:10px 8px;border-bottom:1px solid #1e3a5f;font-size:.9em}
pre{background:#0a1520;border:1px solid #1e3a5f;border-radius:4px;padding:12px;font-family:monospace;font-size:.85em;color:#a8d8ea;overflow-x:auto}
.actions{display:flex;flex-wrap:wrap;gap:10px}
.actions button{background:#1e3a5f;border:1px solid #2a5a8a;color:#b0c4d8;padding:8px 20px;border-radius:4px;cursor:pointer}
.actions button:hover{background:#1976d2;color:#fff}
.status-up{color:#66bb6a}.status-down{color:#ef5350}
footer{text-align:center;padding:20px;color:#546e7a;font-size:.85em;border-top:1px solid #1e3a5f;margin-top:40px}
EOF

    # ── app.js ──
    cat > /var/www/html/app.js << 'EOF'
const API='/cgi-bin/api.sh?path=';
async function api(m,p,b){try{const r=await fetch(API+p.replace(/^\//,''),{method:m,body:b,
headers:b?{'Content-Type':'application/x-www-form-urlencoded'}:{}});
const t=await r.text();try{return JSON.parse(t)}catch(e){return{error:t}}}catch(e){return{error:e.message}}}
function showTab(n){document.querySelectorAll('.tab-content,.tab').forEach(e=>e.classList.remove('active'));
const t=document.getElementById(n);if(t)t.classList.add('active');
const b=document.querySelector(`.tab[onclick*="${n}"]`);if(b)b.classList.add('active');
switch(n){case'status':refreshStatus();break;case'network':refreshNetwork();break;case'dhcp':refreshDHCP();break;case'system':refreshSystem();break}}
async function refreshStatus(){const u=await api('GET','/uptime');document.getElementById('uptime').textContent=u.uptime||'N/A';
const m=await api('GET','/memory');document.getElementById('memory').textContent=m.total?(m.used/1024).toFixed(1)+'/'+(m.total/1024).toFixed(1)+' MB':'N/A';
const l=await api('GET','/loadavg');document.getElementById('loadavg').textContent=l.loadavg||'N/A';
const i=await api('GET','/interfaces');const tb=document.querySelector('#interfaces tbody');
if(i.interfaces&&i.interfaces.length>0)tb.innerHTML=i.interfaces.map(x=>'<tr><td><strong>'+x.name+'</strong></td><td>'+(x.ip||'-')+'</td><td class="'+(x.up?'status-up':'status-down')+'">'+(x.up?'🟢 Run':'🔴 Down')+'</td></tr>').join('');
else tb.innerHTML='<tr><td colspan="3">No data</td></tr>'}
async function refreshNetwork(){const r=await api('GET','/route');document.getElementById('routing-table').textContent=r.route||'N/A';
const n=await api('GET','/nat');document.getElementById('nat-rules').textContent=n.nat||'N/A'}
async function refreshDHCP(){const l=await api('GET','/dhcp-leases');const tb=document.querySelector('#dhcp-leases tbody');
if(l.leases&&l.leases.length>0)tb.innerHTML=l.leases.map(x=>'<tr><td>'+x.mac+'</td><td>'+x.ip+'</td><td>'+(x.hostname||'-')+'</td><td>'+(x.remaining||'-')+'</td></tr>').join('');
else tb.innerHTML='<tr><td colspan="4">No leases</td></tr>'}
async function refreshSystem(){const i=await api('GET','/sysinfo');document.getElementById('sysinfo').textContent=i.info||'N/A'}
document.addEventListener('DOMContentLoaded',()=>{setTimeout(()=>{refreshStatus();refreshNetwork();refreshDHCP();refreshSystem()})})
EOF

    # ── lang.js ──
    cat > /var/www/html/lang.js << 'EOF'
const I18N={zh:{'page.title':'Reasonix Router','header.subtitle':'多系统兼容软路由',
'tab.status':'📊 状态','tab.network':'🌐 网络','tab.dhcp':'📡 DHCP','tab.system':'⚙️ 系统',
'status.title':'系统状态','status.uptime':'运行时间','status.memory':'内存','status.load':'负载','status.interfaces':'接口',
'status.loading':'加载中...','table.interface':'接口','table.ip':'IP','table.mac':'MAC','table.status':'状态',
'network.title':'网络','network.routing':'路由表','network.nat':'NAT规则',
'dhcp.title':'DHCP','dhcp.leases':'租约','dhcp.hostname':'主机名','dhcp.remaining':'剩余','dhcp.no-leases':'无租约',
'system.title':'系统','system.info':'信息','system.actions':'操作','lang.switch':'English','error.no-data':'无数据'},
en:{'page.title':'Reasonix Router','header.subtitle':'Multi-OS Router',
'tab.status':'📊 Status','tab.network':'🌐 Network','tab.dhcp':'📡 DHCP','tab.system':'⚙️ System',
'status.title':'System Status','status.uptime':'Uptime','status.memory':'Memory','status.load':'CPU Load','status.interfaces':'Interfaces',
'status.loading':'Loading...','table.interface':'Interface','table.ip':'IP','table.mac':'MAC','table.status':'Status',
'network.title':'Network','network.routing':'Routing Table','network.nat':'NAT Rules',
'dhcp.title':'DHCP','dhcp.leases':'Leases','dhcp.hostname':'Hostname','dhcp.remaining':'Remaining','dhcp.no-leases':'No leases',
'system.title':'System','system.info':'Info','system.actions':'Actions','lang.switch':'中文','error.no-data':'No data'}};
let L=localStorage.getItem('lang')||'zh';function t(k){return(I18N[L]||I18N.zh)[k]||k}
function a(){document.documentElement.lang=L;document.title=t('page.title');
document.querySelectorAll('[data-i18n]').forEach(e=>{e.textContent=t(e.dataset.i18n)})
document.getElementById('lang-btn').textContent=t('lang.switch');localStorage.setItem('lang',L)}
function toggleLang(){L=L==='zh'?'en':'zh';a();location.reload()}
document.addEventListener('DOMContentLoaded',a)
EOF

    # ── CGI API ──
    cat > /var/www/html/cgi-bin/api.sh << 'APISH'
#!/bin/sh
echo "Content-Type: application/json; charset=utf-8"
echo ""
RQ="${QUERY_STRING#*path=}"; RQ="${RQ%%&*}"; RQ=$(echo "$RQ"|sed 's/%2F/\//g;s/%20/ /g')
case "$RQ" in
  uptime) u=$(cat /proc/uptime 2>/dev/null|awk '{print $1}')
    d=$(echo "$u/86400"|bc 2>/dev/null);h=$(echo "($u%86400)/3600"|bc 2>/dev/null);m=$(echo "($u%3600)/60"|bc 2>/dev/null)
    echo "{\"uptime\":\"${d:-0}d ${h:-0}h ${m:-0}m\"}" ;;
  memory) t=$(grep MemTotal /proc/meminfo|awk '{print $2}');f=$(grep MemFree /proc/meminfo|awk '{print $2}')
    b=$(grep Buffers /proc/meminfo|awk '{print $2}');c=$(grep Cached /proc/meminfo|awk '{print $2}')
    echo "{\"total\":$t,\"used\":$((t-f-b-c)),\"free\":$f}" ;;
  loadavg) echo "{\"loadavg\":\"$(cat /proc/loadavg|awk '{print $1,$2,$3}' 2>/dev/null)\"}" ;;
  interfaces) o=""
    for d in /sys/class/net/*/;do [ -d "$d" ]||continue;n=$(basename "$d");[ "$n" = "lo" ]&&continue
    a=$(cat ${d}address 2>/dev/null);p=$(cat ${d}operstate 2>/dev/null)
    i=$(ip -4 addr show "$n" 2>/dev/null|grep 'inet '|head -1|awk '{print $2}'|cut -d/ -f1);[ -z "$i" ]&&i="-"
    u="false";[ "$p" = "up" ]&&u="true";o="${o}{\"name\":\"$n\",\"ip\":\"$i\",\"mac\":\"$a\",\"up\":$u},"
    done;echo "{\"interfaces\":[${o%%,}]}" ;;
  route) echo "{\"route\":\"$(ip route show 2>/dev/null|sed 's/\"/\\\\\"/g'|tr '\n' ' ')\"}" ;;
  nat) echo "{\"nat\":\"$(iptables -t nat -L -n 2>/dev/null|sed 's/\"/\\\\\"/g'|tr '\n' ' ')\"}" ;;
  sysinfo) echo "{\"info\":\"Host: $(hostname 2>/dev/null)\\nKernel: $(uname -r 2>/dev/null)\\nUptime: $(cat /proc/uptime 2>/dev/null|awk '{printf \"%ds\",\$1}')\"}" ;;
  dhcp-leases) l=""
    [ -f /var/lib/misc/dnsmasq.leases ] && l=$(cat /var/lib/misc/dnsmasq.leases 2>/dev/null|while read e m i h r;do
    [ -z "$m" ]&&continue;now=$(date +%s);rem=$((e-now));[ "$rem" -lt 0 ]&&continue;[ "$rem" -gt 86400 ]&&rs=">24h"||rs="${rem}s"
    echo "{\"mac\":\"$m\",\"ip\":\"$i\",\"hostname\":\"$h\",\"remaining\":\"$rs\"},"
    done);echo "{\"leases\":[${l%%,}]}" ;;
  restart-dhcp) killall dnsmasq 2>/dev/null;dnsmasq 2>/dev/null& echo '{"message":"DHCP restarted"}' ;;
  flush-conntrack) echo f>/proc/net/nf_conntrack 2>/dev/null;echo '{"message":"Conntrack flushed"}' ;;
  reboot) (sleep 1;reboot -f 2>/dev/null||reboot)& echo '{"message":"Rebooting..."}' ;;
  poweroff) (sleep 1;poweroff -f 2>/dev/null||poweroff)& echo '{"message":"Shutting down..."}' ;;
  *) echo "{\"error\":\"Unknown: $RQ\"}" ;;
esac
APISH
    chmod +x /var/www/html/cgi-bin/api.sh

    # ── lighttpd 配置 ──
    cat > /etc/lighttpd/lighttpd.conf << 'LIGHT'
server.document-root = "/var/www/html"
server.port = 80
server.bind = "0.0.0.0"
index-file.names = ("index.html")
mimetype.assign = (".html"=>"text/html",".css"=>"text/css",".js"=>"application/javascript")
server.modules = ("mod_cgi")
cgi.assign = (".sh" => "/bin/sh")
LIGHT

    case "$SERVICE_MGR" in
        systemd) systemctl enable lighttpd 2>/dev/null && systemctl restart lighttpd 2>/dev/null || true ;;
        openrc)  rc-update add lighttpd default 2>/dev/null && rc-service lighttpd start 2>/dev/null || true ;;
        sysvinit) service lighttpd restart 2>/dev/null || true ;;
    esac
    ok "Web UI 部署完成"
}

# ============================================================
#  显示结果
# ============================================================
show_result() {
    LAN_IP=$(ip -4 addr show "$LAN" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
    [ -z "$LAN_IP" ] && LAN_IP="192.168.2.1"
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  ✅ Reasonix Router Ready!               ║"
    echo "║                                         ║"
    echo "║  OS:    $OS"
    echo "║  WAN:   $WAN (DHCP)"
    echo "║  LAN:   $LAN ($LAN_IP)"
    echo "║  Web:   http://$LAN_IP"
    echo "║  SSH:   user@$LAN_IP"
    echo "║                                         ║"
    echo "║  sudo reboot  (recommended)              ║"
    echo "╚══════════════════════════════════════════╝"
}

# ============================================================
#  主流程
# ============================================================
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Reasonix Router — Multi-OS Installer   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

detect_os
detect_interfaces
install_packages
configure_network
configure_dhcp
configure_firewall
deploy_webui
show_result

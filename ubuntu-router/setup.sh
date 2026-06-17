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
    apt install -y -qq dnsmasq lighttpd iptables-persistent net-tools curl wget
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

    # 下载最新的 Web UI 文件
    BASE="https://raw.githubusercontent.com/jianbaobao/reasonix-router/main/ubuntu-router/webui"
    for f in index.html style.css app.js lang.js; do
        wget -q -O "/var/www/html/$f" "$BASE/$f" 2>/dev/null || touch "/var/www/html/$f"
    done
    wget -q -O "/var/www/html/cgi-bin/api.sh" "$BASE/cgi-bin/api" 2>/dev/null || touch "/var/www/html/cgi-bin/api.sh"
    chmod +x /var/www/html/cgi-bin/api.sh 2>/dev/null || true

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

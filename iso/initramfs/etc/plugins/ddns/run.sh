#!/bin/sh
# DDNS Plugin - DuckDNS 更新脚本
# 每 5 分钟检查并更新 IP

DDNS_CONF="/etc/plugins/ddns/ddns.conf"
DDNS_LOG="/var/log/ddns.log"

# 如果没配置，退出
[ -f "$DDNS_CONF" ] || exit 0

# 读取配置
. "$DDNS_CONF"
[ -z "$DUCKDNS_DOMAIN" ] && exit 0
[ -z "$DUCKDNS_TOKEN" ] && exit 0

# 获取当前公网 IP
CURRENT_IP=""
# 尝试多个来源获取公网 IP
for src in "https://api.ipify.org" "https://checkip.amazonaws.com" "https://ipv4.icanhazip.com"; do
    CURRENT_IP=$(wget -q -O - "$src" 2>/dev/null | tr -d ' \n')
    [ -n "$CURRENT_IP" ] && break
done

[ -z "$CURRENT_IP" ] && exit 1

# 读取上次更新的 IP
LAST_IP=""
[ -f /var/run/ddns_last_ip ] && LAST_IP=$(cat /var/run/ddns_last_ip)

# IP 没变，不更新
[ "$CURRENT_IP" = "$LAST_IP" ] && exit 0

# 更新 DuckDNS
UPDATE_URL="https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=${CURRENT_IP}"
RESULT=$(wget -q -O - "$UPDATE_URL" 2>/dev/null)

if echo "$RESULT" | grep -q "OK"; then
    echo "$CURRENT_IP" > /var/run/ddns_last_ip
    echo "[$(date)] Updated: $DUCKDNS_DOMAIN -> $CURRENT_IP" >> "$DDNS_LOG"
else
    echo "[$(date)] Failed: $RESULT" >> "$DDNS_LOG"
fi

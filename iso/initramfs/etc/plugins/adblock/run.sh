#!/bin/sh
# AdBlock Plugin - DNS 广告过滤
# 生成 dnsmasq adblock 配置文件

ADBLOCK_CONF="/etc/plugins/adblock/blocklist.txt"
ADBLOCK_OUT="/tmp/adblock.conf"
ADBLOCK_LOG="/var/log/adblock.log"

echo "# AdBlock generated $(date)" > "$ADBLOCK_OUT"

COUNT=0
if [ -f "$ADBLOCK_CONF" ]; then
    while IFS= read -r domain; do
        # 跳过注释和空行
        case "$domain" in
            ''|'#'*) continue ;;
        esac
        # 写入 dnsmasq 格式: address=/example.com/0.0.0.0
        echo "address=/${domain}/0.0.0.0" >> "$ADBLOCK_OUT"
        echo "address=/${domain}/::" >> "$ADBLOCK_OUT"
        COUNT=$((COUNT + 1))
    done < "$ADBLOCK_CONF"
fi

echo "[$(date)] AdBlock loaded $COUNT domains" >> "$ADBLOCK_LOG"
echo "$COUNT" > /var/run/adblock_count

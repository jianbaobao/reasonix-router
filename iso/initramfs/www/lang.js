// ============================================================
//  Reasonix Router - i18n Language Pack v2
//  支持: 中文(zh) / English(en)
// ============================================================

const I18N = {
    zh: {
        'page.title': 'Reasonix Router - 软路由管理系统',
        'header.subtitle': '软路由管理系统 v1.0',

        // Tabs
        'tab.status': '📊 状态',
        'tab.network': '🌐 网络',
        'tab.dhcp': '📡 DHCP',
        'tab.forward': '🔌 转发',
        'tab.log': '📋 日志',
        'tab.tools': '🛠️ 工具',
        'tab.system': '⚙️ 系统',

        // 状态页
        'status.title': '系统状态',
        'status.uptime': '运行时间',
        'status.memory': '内存使用',
        'status.load': 'CPU 负载',
        'status.interfaces': '接口状态',
        'status.loading': '加载中...',
        'status.unavailable': '不可用',
        'status.scan': '🔍 扫描网口',
        'status.scanning': '扫描中',
        'status.click-hint': '点击接口行查看详情 (MTU/双工/载波/丢包)',

        // 表格
        'table.interface': '接口',
        'table.ip': 'IP 地址',
        'table.mac': 'MAC 地址',
        'table.status': '状态',
        'table.speed': '速率',
        'table.rx': 'RX',
        'table.tx': 'TX',
        'table.action': '操作',
        'table.up': '🟢 运行中',
        'table.down': '🔴 关闭',
        'table.no-data': '无数据',

        // 网络页
        'network.title': '网络配置',
        'network.roles': '接口角色配置',
        'network.roles-hint': '选择哪个网口作为 WAN（连接互联网）和 LAN（连接内网）',
        'network.roles-current': '当前',
        'network.roles-apply': '应用并重启网络',
        'network.roles-applying': '应用中',
        'network.roles-same': 'WAN 和 LAN 不能相同',
        'network.routing': '路由表',
        'network.nat': 'NAT 规则',

        // DHCP 页
        'dhcp.title': 'DHCP 服务',
        'dhcp.leases': '活跃租约',
        'dhcp.static-title': '静态 DHCP 绑定',
        'dhcp.hostname': '主机名',
        'dhcp.remaining': '剩余时间',
        'dhcp.no-leases': '暂无租约',
        'dhcp.no-static': '暂无静态绑定',
        'dhcp.add-binding': '➕ 添加静态绑定',
        'dhcp.add-btn': '添加',

        // 端口转发
        'forward.title': '端口转发',
        'forward.rules': '转发规则',
        'forward.proto': '协议',
        'forward.wan-port': 'WAN 端口',
        'forward.lan-ip': 'LAN IP',
        'forward.lan-port': 'LAN 端口',
        'forward.no-rules': '暂无转发规则',
        'forward.add-rule': '➕ 添加转发规则',
        'forward.add-btn': '添加',

        // 日志
        'log.title': '系统日志',
        'log.filter': '过滤关键词...',
        'log.refresh': '刷新',
        'log.clear': '清除',

        // 工具
        'tools.title': '网络诊断',
        'tools.ping': 'Ping 测试',
        'tools.ping-btn': 'Ping',
        'tools.pinging': '正在 Ping',
        'tools.dns': 'DNS 查询',
        'tools.dns-btn': '查询',
        'tools.enter-domain': '请输入域名',
        'tools.geoip': 'IP 地理位置',
        'tools.geoip-btn': '查询',
        'tools.myip': '我的 IP',
        'tools.enter-ip': '请输入 IP 地址',
        'tools.public-ip': '公网 IP',
        'tools.country': '国家/地区',
        'tools.city': '城市',
        'tools.org': '组织',
        'tools.timezone': '时区',
        'tools.coords': '坐标',

        // 系统
        'system.title': '系统管理',
        'system.info': '系统信息',
        'system.actions': '操作',

        // 操作按钮
        'action.restart-dhcp': '重启 DHCP',
        'action.flush-conntrack': '清空连接跟踪',
        'action.restart-network': '重启网络',
        'action.reboot': '重启系统',
        'action.poweroff': '关机',
        'action.done': '操作已执行',
        'action.confirm-reboot': '确定要重启系统吗？',
        'action.confirm-poweroff': '确定要关机吗？',

        // 语言
        'lang.switch': 'English',

        // Footer
        'footer.text': '基于 Linux 的软路由系统',

        // 错误
        'error.no-data': '无数据',
        'error.mac-ip-req': '需要 MAC 和 IP 地址',
        'error.all-fields': '请填写所有字段',
        'error.target-req': '请输入目标地址',

        // 插件
        'tab.plugins': '🧩 插件',
        'plugins.title': '插件管理',
        'plugins.none': '暂无已安装的插件',
        'plugins.ddns-config': 'DuckDNS 配置',
        'plugins.ddns-status': '状态',
        'plugins.ddns-wait': '等待首次更新...',
        'plugins.adblock-config': 'AdBlock 配置',
        'plugins.adblock-stats': '已拦截域名数',
        'plugins.adblock-entries': '列表条目',
        'plugins.adblock-add': '添加域名',
        'plugins.adblock-enter': '请输入域名',
        'plugins.save': '保存',
        'plugins.store': '🧩 插件商店',
        'plugins.store-loading': '正在加载可用插件列表...',
        'plugins.store-source': '来源',
        'plugins.store-name': '名称',
        'plugins.store-desc': '描述',
        'plugins.store-version': '版本',
        'plugins.store-install': '安装',
        'plugins.store-confirm': '确定安装 {name} 吗？',
        'plugins.store-unavailable': '插件商店暂时不可用',
    },

    en: {
        'page.title': 'Reasonix Router - Management Console',
        'header.subtitle': 'Soft Router Management Console v1.0',

        'tab.status': '📊 Status',
        'tab.network': '🌐 Network',
        'tab.dhcp': '📡 DHCP',
        'tab.forward': '🔌 Forward',
        'tab.log': '📋 Log',
        'tab.tools': '🛠️ Tools',
        'tab.system': '⚙️ System',

        'status.title': 'System Status',
        'status.uptime': 'Uptime',
        'status.memory': 'Memory',
        'status.load': 'CPU Load',
        'status.interfaces': 'Interfaces',
        'status.loading': 'Loading...',
        'status.unavailable': 'N/A',
        'status.scan': '🔍 Scan Ports',
        'status.scanning': 'Scanning',
        'status.click-hint': 'Click interface row for details (MTU/Duplex/Carrier/Drops)',

        'table.interface': 'Interface',
        'table.ip': 'IP Address',
        'table.mac': 'MAC Address',
        'table.status': 'Status',
        'table.speed': 'Speed',
        'table.rx': 'RX',
        'table.tx': 'TX',
        'table.action': 'Action',
        'table.up': '🟢 Running',
        'table.down': '🔴 Down',
        'table.no-data': 'No data',

        'network.title': 'Network Config',
        'network.roles': 'Interface Roles',
        'network.roles-hint': 'Choose which port is WAN (Internet) and LAN (internal network)',
        'network.roles-current': 'Current',
        'network.roles-apply': 'Apply & Restart Network',
        'network.roles-applying': 'Applying',
        'network.roles-same': 'WAN and LAN cannot be the same',
        'network.routing': 'Routing Table',
        'network.nat': 'NAT Rules',

        'dhcp.title': 'DHCP Service',
        'dhcp.leases': 'Active Leases',
        'dhcp.static-title': 'Static DHCP Bindings',
        'dhcp.hostname': 'Hostname',
        'dhcp.remaining': 'Remaining',
        'dhcp.no-leases': 'No active leases',
        'dhcp.no-static': 'No static bindings',
        'dhcp.add-binding': '➕ Add Static Binding',
        'dhcp.add-btn': 'Add',

        'forward.title': 'Port Forwarding',
        'forward.rules': 'Forward Rules',
        'forward.proto': 'Proto',
        'forward.wan-port': 'WAN Port',
        'forward.lan-ip': 'LAN IP',
        'forward.lan-port': 'LAN Port',
        'forward.no-rules': 'No forward rules',
        'forward.add-rule': '➕ Add Forward Rule',
        'forward.add-btn': 'Add',

        'log.title': 'System Log',
        'log.filter': 'Filter keywords...',
        'log.refresh': 'Refresh',
        'log.clear': 'Clear',

        'tools.title': 'Network Diagnostic',
        'tools.ping': 'Ping Test',
        'tools.ping-btn': 'Ping',
        'tools.pinging': 'Pinging',
        'tools.dns': 'DNS Lookup',
        'tools.dns-btn': 'Lookup',
        'tools.enter-domain': 'Enter domain',
        'tools.geoip': 'IP Geolocation',
        'tools.geoip-btn': 'Lookup',
        'tools.myip': 'My IP',
        'tools.enter-ip': 'Enter IP address',
        'tools.public-ip': 'Public IP',
        'tools.country': 'Country',
        'tools.city': 'City',
        'tools.org': 'Organization',
        'tools.timezone': 'Timezone',
        'tools.coords': 'Coordinates',

        'system.title': 'System Management',
        'system.info': 'System Info',
        'system.actions': 'Actions',

        'action.restart-dhcp': 'Restart DHCP',
        'action.flush-conntrack': 'Flush Conntrack',
        'action.restart-network': 'Restart Network',
        'action.reboot': 'Reboot',
        'action.poweroff': 'Shutdown',
        'action.done': 'Action executed',
        'action.confirm-reboot': 'Reboot system now?',
        'action.confirm-poweroff': 'Shutdown system now?',

        'lang.switch': '中文',

        'footer.text': 'Linux-based Soft Router System',

        'error.no-data': 'No data',
        'error.mac-ip-req': 'MAC and IP address required',
        'error.all-fields': 'All fields are required',
        'error.target-req': 'Please enter a target',

        // Plugins
        'tab.plugins': '🧩 Plugins',
        'plugins.title': 'Plugin Manager',
        'plugins.none': 'No plugins installed',
        'plugins.ddns-config': 'DuckDNS Config',
        'plugins.ddns-status': 'Status',
        'plugins.ddns-wait': 'Waiting for first update...',
        'plugins.adblock-config': 'AdBlock Config',
        'plugins.adblock-stats': 'Blocked domains',
        'plugins.adblock-entries': 'List entries',
        'plugins.adblock-add': 'Add Domain',
        'plugins.adblock-enter': 'Enter a domain',
        'plugins.save': 'Save',
        'plugins.store': '🧩 Plugin Store',
        'plugins.store-loading': 'Loading available plugins...',
        'plugins.store-source': 'Source',
        'plugins.store-name': 'Name',
        'plugins.store-desc': 'Description',
        'plugins.store-version': 'Version',
        'plugins.store-install': 'Install',
        'plugins.store-confirm': 'Install {name}?',
        'plugins.store-unavailable': 'Plugin store unavailable',
    }
};

// ─── 当前语言 ─────────────────────────────────────────────
let currentLang = localStorage.getItem('reasonix-lang') || 'zh';

// ─── 翻译函数 ─────────────────────────────────────────────
function t(key, fallback) {
    const dict = I18N[currentLang] || I18N.zh;
    return dict[key] || fallback || key;
}

// ─── 应用翻译到页面 ────────────────────────────────────────
function applyLang() {
    document.documentElement.lang = currentLang === 'zh' ? 'zh-CN' : 'en';
    document.title = t('page.title');

    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        const text = t(key);
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
            el.placeholder = text;
        } else if (el.tagName === 'SUMMARY') {
            el.textContent = text;
        } else {
            el.textContent = text;
        }
    });

    const langBtn = document.getElementById('lang-btn');
    if (langBtn) langBtn.textContent = t('lang.switch');

    localStorage.setItem('reasonix-lang', currentLang);
}

// ─── 切换语言 ─────────────────────────────────────────────
function toggleLang() {
    currentLang = currentLang === 'zh' ? 'en' : 'zh';
    applyLang();
    // 重新刷新数据
    const active = document.querySelector('.tab-content.active');
    if (active) {
        switch(active.id) {
            case 'status': refreshStatus(); break;
            case 'network': refreshNetwork(); break;
            case 'dhcp': refreshDHCP(); break;
            case 'forward': refreshForward(); break;
            case 'log': break;
            case 'tools': break;
            case 'system': refreshSystem(); break;
        }
    }
}

document.addEventListener('DOMContentLoaded', () => { applyLang(); });

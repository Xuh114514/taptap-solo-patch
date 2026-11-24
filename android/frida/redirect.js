/*
 * 开放空间 安卓版 —— 第二步：把 dispatch 指到你 PC 上的 Lolo
 *
 * 前提：
 *   1) PC 上已经跑过 lan-server.ps1（Lolo 监听 0.0.0.0:18881）
 *   2) 安卓设备和 PC 在同一 WiFi
 *   3) 用 probe.js 的结果确认了类名 / 请求方式
 *
 * 用法：
 *   frida -U -f <包名> -l redirect.js --no-pause
 *
 * 改 PC_IP 为你 PC 的局域网地址（lan-server.ps1 会打印）
 */

var PC_IP = '192.168.1.100';     // <-- 改成你 PC 的局域网 IP
var PC_PORT = 18881;              // Lolo 在 lan 模式下监听的端口

// 1) OkHttp 层：把 dispatch 域名替换成 PC
try {
    var Builder = Java.use('okhttp3.Request$Builder');
    var build = Builder.build;
    build.implementation = function () {
        var req = build.call(this);
        try {
            var u = req.url().toString();
            if (u.indexOf('dsp-prod-of.inutan.com') >= 0 || u.indexOf(':18881') >= 0) {
                var nu = u
                    .replace(/http:\/\/dsp-prod-of\.inutan\.com:18881/g, 'http://' + PC_IP + ':' + PC_PORT)
                    .replace(/http:\/\/\d+\.\d+\.\d+\.\d+:18881/g, 'http://' + PC_IP + ':' + PC_PORT);
                if (nu !== u) {
                    console.log('[redirect] ' + u + '  ->  ' + nu);
                    var nb = Java.use('okhttp3.Request$Builder').$new();
                    // 简单做法：重建请求
                    var HB = Java.use('okhttp3.Request').$new();
                    // 直接改 URL 更稳：HttpUrl.parse
                    var HU = Java.use('okhttp3.HttpUrl');
                    var parsed = HU.parse(nu);
                    req.url = parsed;
                }
            }
        } catch (e) {
            console.log('[redirect] err: ' + e);
        }
        return req;
    };
    console.log('[hook] okhttp redirect ready');
} catch (e) {
    console.log('[skip] no okhttp: ' + e);
}

// 2) Unity 原生层：如果 dispatch 用 UnityWebRequest，就把内存里的域名换成 PC IP
//    原理：扫内存找到 'dsp-prod-of.inutan.com' 字符串，替换成等长 IP 字符串（用空格补齐）
setTimeout(function () {
    var target = 'dsp-prod-of.inutan.com';
    var repl = PC_IP;
    while (repl.length < target.length) repl += ' ';
    repl = repl.substring(0, target.length);

    var ranges = Process.enumerateRanges('rw-');
    var count = 0;
    ranges.forEach(function (r) {
        try {
            var res = Memory.scanSync(r.base, r.size, target);
            res.forEach(function (m) {
                try {
                    Memory.writeUtf8String(m.address, repl);
                    count++;
                } catch (e) { }
            });
        } catch (e) { }
    });
    console.log('[mem] 已替换 ' + count + ' 处域名 -> ' + PC_IP);
    if (count === 0) {
        console.log('[mem] 没找到，说明域名在 il2cpp metadata 里被加密/压缩，需要换思路（见 docs/安卓方案.md 方案 B）');
    }
}, 6000);

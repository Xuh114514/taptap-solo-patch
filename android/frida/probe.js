/*
 * 开放空间 安卓版 —— 第一步：侦察脚本
 * 用途：摸清 TapSDK 的类名、登录方法、以及游戏发出 dispatch 请求的方式。
 *
 * 用法（需要 root 手机 / MuMu 模拟器，装 frida-server）：
 *   frida -U -f com.xxx.overfield -l probe.js --no-pause
 *   （包名先用 `frida-ps -Uai` 查，开放空间 TapTap 版一般是 com.inutan.of 之类）
 *
 * 这个脚本只打印信息，不改任何东西，安全。
 */

Java.perform(function () {
    console.log('========== probe start ==========');

    // 1) 找 TapSDK / QuickSDK / 游戏自身的类
    var interesting = /(taptap|TapSDK|TapLogin|quicksdk|QuickSDK|inutan|OverField|OpenSpace|sdkapi)/i;
    var hits = [];
    Java.enumerateLoadedClasses({
        onMatch: function (name) {
            if (interesting.test(name)) hits.push(name);
        },
        onComplete: function () {
            hits.sort();
            console.log('---- 可疑类 (' + hits.length + ') ----');
            hits.forEach(function (n) { console.log('[class] ' + n); });
        }
    });

    // 2) 打印所有 OkHttp 请求（TapSDK 的 HTTP 一般走 OkHttp）
    try {
        var Builder = Java.use('okhttp3.Request$Builder');
        var build = Builder.build;
        build.implementation = function () {
            var req = build.call(this);
            try {
                var u = req.url().toString();
                if (/inutan|taptap|dispatch|oauth|sdkapi/i.test(u)) {
                    console.log('[okhttp] ' + req.method() + ' ' + u);
                }
            } catch (e) { }
            return req;
        };
        console.log('[hook] okhttp3.Request$Builder 已挂上');
    } catch (e) {
        console.log('[skip] 没有 okhttp3（可能是加固或别的网络库）');
    }

    // 3) 兜底：打印 java.net.URL 的构造（很多 SDK 用它）
    try {
        var URL = Java.use('java.net.URL');
        var init = URL.$init.overload('java.lang.String');
        init.implementation = function (s) {
            if (/inutan|taptap|dispatch|oauth|sdkapi|18881/i.test(s)) {
                console.log('[url] ' + s);
            }
            return init.call(this, s);
        };
        console.log('[hook] java.net.URL 已挂上');
    } catch (e) {
        console.log('[skip] URL hook 失败: ' + e);
    }

    // 4) 找 TapTap 登录入口（类名不确定，全部枚举一次方法名）
    setTimeout(function () {
        hits.forEach(function (n) {
            if (!/taptap|TapSDK|TapLogin/i.test(n)) return;
            try {
                var C = Java.use(n);
                var methods = C.class.getDeclaredMethods();
                methods.forEach(function (m) {
                    var s = m.toString();
                    if (/login|Login|auth|Auth|token|Token/.test(s)) console.log('[method] ' + s);
                });
            } catch (e) { }
        });
        console.log('========== probe done ==========');
    }, 3000);
});

// Unity 原生层（il2cpp）的 URL 字符串：直接扫内存里的 inutan 域名
setTimeout(function () {
    try {
        var ranges = Process.enumerateRanges('r--');
        var needle = 'dsp-prod-of.inutan.com';
        var found = 0;
        ranges.forEach(function (r) {
            try {
                var res = Memory.scanSync(r.base, r.size, needle);
                if (res.length) {
                    found += res.length;
                    console.log('[mem] ' + needle + ' @ ' + r.base + ' (' + res.length + ')');
                }
            } catch (e) { }
        });
        console.log('[mem] 命中 ' + found + ' 处（说明游戏里硬编码了这个域名）');
    } catch (e) {
        console.log('[mem] scan 失败: ' + e);
    }
}, 6000);

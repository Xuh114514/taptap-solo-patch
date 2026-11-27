# 开放空间 TapTap/渠道版 本地单机启动补丁

给 [miaomiao-launcher v1.0.0](https://github.com/inori-dream/miaomiao-launcher/releases/tag/v1.0.0) 补上渠道客户端的本地登录。

只干这一件事：让 TapTap / QuickSDK 渠道版客户端能连到你自己电脑上的服务端。

不含游戏本体，不含服务端程序，不含账号数据，也没有任何改存档、发道具的功能。

---

## 先装这个能省 90% 的功夫

```
1. 打开启动器 → 单机模式 → UID 随便填 → 更改目录 → 点「启动单机游戏」
   这次一定会失败，会弹到官网，不用管，让它跑完再关掉

2. 本页 Code → Download ZIP → 解压

3. 右键 install.ps1 → 使用 PowerShell 运行
   UAC 点「是」，把启动器文件夹拖进窗口，回车

4. 再打开启动器，单机模式，点「启动单机游戏」
   渠道登录窗弹出来直接关掉，就进去了
```

卡住了再往下看。

---

## 为什么不装这个补丁就进不去

原项目只认 B 站 PC 版 1.1.12，做法是把客户端里的 `PCGameSDK.dll` 换成自己写的 DLL 来伪造登录。

TapTap / QuickSDK 渠道版里压根没有 `PCGameSDK.dll`。它走的是另一条路：

```
游戏启动 → 拉起 PCSDKUI.exe → 开 https://sdkapi-of.inutan.com/open/oauth 网页
       → 你在网页上登录 → 网页把 token 通过命名管道 \\.\pipe\quickpc<游戏PID> 塞回游戏
       → 游戏拿 token 去 http://dsp-prod-of.inutan.com:18881/dispatch/... 换区服
       → 连官方网关 14.103.x.x:11001
```

所以换 DLL 对渠道版没用，游戏照样走官网，断网必挂。

这个补丁把这条链路整条搬到本机：

```
游戏启动 → 拉起「假的 PCSDKUI.exe」→ 直接返回一个本地登录成功，不联网
       → hosts 把 dsp-prod-of.inutan.com 指到 127.0.0.1
       → 18881 转发到本机 Lolo 的 18080
       → Lolo 的 region_info 返回 gate 127.0.0.1:18100
       → 客户端连你自己电脑
```

---

## 装之前得有的是这些

- **原项目启动器**：下 [OverFieldLauncher-portable.zip](https://github.com/inori-dream/miaomiao-launcher/releases/download/v1.0.0/OverFieldLauncher-portable.zip)，完整解压到一个可写目录，比如 `D:\Games\OverFieldLauncher`
- **游戏客户端**：你自己装好的 TapTap 版（协议按 1.1.12 验的）
- **系统**：Win10 / Win11 就行，.NET 4.x 系统自带
- **权限**：要管理员，因为得写 hosts 和端口转发，会弹 UAC

不用装 Python，不用装 Visual Studio，也不动游戏本体。

---

## 装的过程

### 一、先让启动器生成一份客户端副本

打开启动器，左边点「单机模式」，UID 填个数字比如 `1000000`，点「更改目录」选中你的游戏目录（比如 `C:\TapTap\PC Games\176228`），然后点「启动单机游戏」。

**这一步失败是正常的，弹到官网也正常。** 要的就是它生成这个目录：

```
<启动器目录>\profiles\solo\client\launcher_Data\Plugins\Win\PCSDK_release\
```

能看到里面的 `PCSDKUI.exe` 就可以把游戏关了。

### 二、跑安装脚本

解压本项目，右键 `install.ps1` → 使用 PowerShell 运行。弹 UAC 点「是」，然后把它要的启动器目录整个拖进窗口回车。

它会做四件事：

1. 把 `PCSDKUI.exe` 换成替身，原文件改名成 `PCSDKUI.orig.exe` 留着
2. hosts 里加 `127.0.0.1 dsp-prod-of.inutan.com`
3. 加端口转发 `127.0.0.1:18881` → `127.0.0.1:18080`
4. 如果你开着系统代理（Clash、V2Ray 之类），往「不使用代理」列表里加 `*.inutan.com`，不然请求会被代理吃成 502

### 三、再启动一次

还是那几步：单机模式 → UID → 启动单机游戏。

渠道登录窗会弹出来，直接关掉，游戏自己进本地服。

### 四、确认真的连的是本地

看 `<启动器目录>\profiles\solo\logs\` 里最新的 `server-xxxx.log`，出现这些就是成了：

```
[Gate] Gateway accepted new connection: 127.0.0.1:xxxxx
[login.go:89,VerifyLoginToken] UserId:1000000 platform:AccountType_Windows verify success
[player_basic.go:129,PlayerLogin] UserId:1000000 Name:... 登录成功!
```

### 五、想验证是不是真离线

断网，再点一次「启动单机游戏」，能进就是真本地。

公告和 CDN 图片还是会去官方域名要，断网时它们会失败，但不影响进游戏。

---

## 出问题

`点启动报 Profile port 18080 is occupied`
上次的 Lolo.exe 没退干净。任务管理器里把所有 Lolo.exe 结束掉再启动。

`游戏里提示「服务器获取失败」`
dispatch 请求被系统代理劫走了。重新跑一遍 install.ps1，它会检测代理并补旁路。没装代理的人碰不到这个。

`游戏里提示「SDK 登录校验失败」`
还在连官方 18881。先看 hosts 有没有那一行，再看 `netsh interface portproxy show v4tov4` 里有没有 18881。

`启动后闪退，或者又弹官网网页`
替身没生效。看 `PCSDK_release\PCSDKUI.exe` 是不是 8KB 左右（原版 170KB）。如果还是原版大小，删掉 `profiles\solo\client` 整个目录，回第一步重来。

---

## 想切回官服

双击 `一键切换.bat`，它会告诉你当前在哪个模式：

```
============================================
   开放空间 · 单机 / 官服 一键切换
============================================
   当前状态：单机模式（走本机服务端）

   1  切到【单机模式】
   2  切回【官服模式】
   0  退出
```

按 2 回官服，按 1 回单机。第一次按 1 会让你拖一次启动器目录，注意是放 `OverFieldLauncher.exe` 的那个文件夹，不是游戏目录 176228。之后它会记在 `launcher.path` 里，不用再填。

不想看菜单就直接双击 `切回官服.bat` 或 `切到单机.bat`。

**装完补丁以后，直接点 TapTap 启动器是回不去官服的。** 因为 hosts 那行和 18881 转发还在，官方客户端拿到 token 后请求 dispatch 会被导到本机，结果要么连到本地服务，要么直接报「服务器获取失败」。

命令行也行：

```powershell
powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode official   # 回官服
powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode solo       # 回单机
```

想彻底卸掉就跑 `uninstall.ps1`（要管理员），它会还原 hosts、删掉 18881 转发、把 `PCSDKUI.orig.exe` 换回去、清掉代理旁路。

切完不放心可以自己验一下：

```powershell
Get-Content C:\Windows\System32\drivers\etc\hosts | Select-String inutan   # 应该没输出
netsh interface portproxy show v4tov4                                       # 应该看不到 18881
[System.Net.Dns]::GetHostAddresses('dsp-prod-of.inutan.com')                # 应该不是 127.0.0.1
```

切之前顺手在启动器里点一下「停止」，把 Lolo.exe 关掉。

---

## 具体改了啥

- `PCSDKUI.exe` 替身：接管命名管道 `\\.\pipe\quickpc<游戏PID>`，回 `{"action":"init"}` 和 `{"action":"loginSuccess"}`，用你填的 UID 做本地登录
- hosts 把 dispatch 域名指到本机
- 18881 到 18080 的端口转发
- 系统代理旁路

没动的东西：游戏本体、原客户端目录（只碰 `profiles\solo\client` 这份副本）、存档、数据库。也不发道具、不改角色。

游戏本体和服务端二进制都不在这个仓库里，`Lolo.exe` 那些自己从上游项目拿，放进 `server-kit\`。

---

## 免责

本项目是非官方社区补丁，和游戏开发商、发行商、渠道方（TapTap / bilibili 等）以及 [inori-dream/miaomiao-launcher](https://github.com/inori-dream/miaomiao-launcher) 的作者都没有关系，没有授权也没有背书。

不提供也不分发游戏客户端、服务端程序、游戏资源、账号数据或任何受版权保护的内容。用之前你应该已经通过正规途径有了游戏客户端，服务端资源也请自行准备。

只建议拿来做本机自用和学一下渠道 SDK 的本地登录链路。别拿去商业化、别拿去开服、别倒卖。

不绕过任何付费内容，没有破解、激活、内购规避之类的功能。

用出问题自己担着。可能出现的包括但不限于：客户端异常、存档配置损坏、游戏更新后失效、渠道账号被风控。作者和贡献者不承担任何直接或间接责任。

如果权利人认为这里有问题，开 Issue 说一声，会立刻调整或删除相关代码。

下载、安装或运行本仓库任意文件，就当你已经看过并接受上面这些。不接受就别用。

---

## 文件都是干嘛的

- `一键切换.bat` —— 双击这个，菜单里选单机还是官服
- `切回官服.bat` / `切到单机.bat` —— 跳过菜单直接切
- `switch.ps1` —— 上面三个 bat 背后的逻辑，也能命令行带 `-Mode` 调
- `install.ps1` —— 装补丁 / 修复，会自己申请管理员
- `uninstall.ps1` —— 完整还原
- `tools/PCSDKUIStub.exe` —— 替身程序，预编译好了直接用
- `tools/PCSDKUIStub.cs` —— 替身源码，想审就审
- `tools/build-stub.ps1` —— 重新编译用系统自带的 csc，不用装 VS
- `docs/原理.md` —— 协议链路细节，给想深挖的人

## 致谢

启动器 [inori-dream/miaomiao-launcher](https://github.com/inori-dream/miaomiao-launcher)，服务端 [BanterSR/Lolo](https://github.com/BanterSR/Lolo) 和 [byzp/of-ps](https://github.com/byzp/of-ps)。这个补丁只补了渠道版本地登录那一环，其他功能看上游。

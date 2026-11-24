# 开放空间 · TapTap/渠道版「本地单机启动」补丁

> 给 [miaomiao-launcher v1.0.0](https://github.com/inori-dream/miaomiao-launcher/releases/tag/v1.0.0) 补上 TapTap / QuickSDK 渠道客户端的本地登录能力。
>
> **本项目只做一件事：让渠道版客户端能连到你自己电脑上的本地服务端。**
> 不含游戏本体、不含服务端程序、不含任何账号数据、不含任何「全角色 / 全道具 / 改存档」功能。

---

## 30 秒速通（懒人版）

```
1. 打开启动器 → 单机模式 → 填 UID → 更改目录 → 点「启动单机游戏」
   （这次会失败、会弹官网，没关系；目的是让它生成客户端副本）→ 关掉游戏

2. 本页 → Code → Download ZIP → 解压

3. 右键 install.ps1 → 使用 PowerShell 运行
   → UAC 点「是」
   → 把启动器文件夹拖进窗口 → 回车

4. 重新打开启动器 → 单机模式 → 启动单机游戏
   → 渠道登录弹窗直接关掉 → 进游戏
```

详细说明和排错在后面，卡住了再往下看。

---

## 0. 先说人话：为什么你照原项目做，还是弹官网登录？

原项目只适配 **B 站 PC 版 1.1.12**，它的做法是把客户端里的 `PCGameSDK.dll` 换成自制 DLL 来伪造登录。

但 TapTap / QuickSDK 渠道版客户端里 **根本没有 `PCGameSDK.dll`**，它登录走的是另一条路：

```
游戏启动 -> 拉起 PCSDKUI.exe -> 打开 https://sdkapi-of.inutan.com/open/oauth 网页
        -> 你登录官网账号 -> 网页把 token 通过命名管道 \\.\pipe\quickpc<游戏PID> 回传给游戏
        -> 游戏拿 token 去 http://dsp-prod-of.inutan.com:18881/dispatch/... 换区服列表
        -> 连官方网关 14.103.x.x:11001
```

所以原项目的 DLL 替换对渠道版 **完全无效**，游戏照旧走官网，断网必然起不来。

这个补丁把上面那条链路整条换成本地：

```
游戏启动 -> 拉起「替身 PCSDKUI.exe」-> 直接回一个假的本地登录成功（不联网）
        -> hosts 把 dsp-prod-of.inutan.com 指到 127.0.0.1
        -> 18881 端口转发到本机 Lolo 的 18080
        -> Lolo 的 /dispatch/region_info 直接返回 gate 127.0.0.1:18100
        -> 客户端连你自己电脑上的服务端
```

---

## 1. 你需要先准备什么

| 东西 | 说明 |
| --- | --- |
| 原项目启动器 | 下载 [OverFieldLauncher-portable.zip](https://github.com/inori-dream/miaomiao-launcher/releases/download/v1.0.0/OverFieldLauncher-portable.zip)，**完整解压**到一个可写目录，比如 `D:\Games\OverFieldLauncher` |
| 游戏客户端 | 你自己已经装好的 TapTap / 渠道版客户端（原项目验证过 1.1.12 协议） |
| 系统 | Windows 10 / 11，自带 .NET Framework 4.x（Win10/11 默认就有） |
| 权限 | 安装时要**管理员**（要写 hosts 和端口转发），会弹 UAC，点「是」 |

> 不需要装 Python、不需要装 Visual Studio、不需要改游戏本体。

---

## 2. 六步装好（照着做就行）

### 第 1 步：让启动器先生成客户端副本

1. 双击启动器 `OverFieldLauncher.exe`
2. 点左边「单机模式」
3. UID 随便填个数字，比如 `1000000`
4. 点「更改目录」，选中你的游戏客户端目录（例如 `C:\TapTap\PC Games\176228`）
5. 点「启动单机游戏」

**这一步会失败、会弹到官网登录，都正常。** 我们要的是它生成这个目录：

```
<启动器目录>\profiles\solo\client\launcher_Data\Plugins\Win\PCSDK_release\
```

看到 `PCSDKUI.exe` 在这个目录里，就可以把游戏关掉了（Alt+F4）。

### 第 2 步：下载本项目

点本页右上角 `Code` → `Download ZIP`，解压到任意位置，比如 `D:\taptap-solo-patch`。

### 第 3 步：运行安装脚本

进入解压出来的目录，**右键** `install.ps1` → **使用 PowerShell 运行**。

- 弹出 UAC 就点「是」
- 提示你输入启动器目录时，把 `<启动器目录>` 整个文件夹**拖进窗口**，回车

脚本会自动做完这四件事：

1. 备份并替换 `PCSDKUI.exe` 为替身（原文件存成 `PCSDKUI.orig.exe`）
2. 往 hosts 加一行 `127.0.0.1 dsp-prod-of.inutan.com`
3. 加端口转发 `127.0.0.1:18881 -> 127.0.0.1:18080`
4. （**只有你装了系统代理才会做这一步**）在你系统代理的「不使用代理」列表里加 `*.inutan.com`，防止 Clash/V2Ray 把请求变成 502

### 第 4 步：重新打开启动器，点「启动单机游戏」

还是那三步：单机模式 → 填 UID → 启动单机游戏。

游戏会出现原来的渠道登录弹窗，**不用管它，直接关掉**，游戏会自己进本地服务。

### 第 5 步：确认真的进了本地服

打开 `<启动器目录>\profiles\solo\logs\` 里最新的 `server-xxxx.log`，能看到这些就是成功：

```
[Gate] Gateway accepted new connection: 127.0.0.1:xxxxx
[login.go:89,VerifyLoginToken] UserId:1000000 platform:AccountType_Windows verify success
[player_basic.go:129,PlayerLogin] UserId:1000000 Name:... 登录成功!
```

### 第 6 步（可选）：断网测试

把网线拔了 / 关掉 WiFi，再点一次「启动单机游戏」。能进就是真的本地了。

> 公告、CDN 图片这些还会去官方域名拿，断网时它们会失败，但不影响进游戏。

---

## 3. 出问题了看这里

| 现象 | 原因 | 怎么办 |
| --- | --- | --- |
| 点启动就报 `Profile port 18080 is occupied by another service` | 上次的 `Lolo.exe` 没退干净 | 任务管理器结束所有 `Lolo.exe`，再启动 |
| 游戏里提示「服务器获取失败」 | dispatch 请求走了你的代理（Clash 之类） | 重新跑一次 `install.ps1`（会检测代理并自动补旁路；没有代理的人不会遇到） |
| 游戏里提示「SDK 登录校验失败」 | 还在连官方 18881 | 检查 hosts 有没有那一行；检查 `netsh interface portproxy show v4tov4` 里有没有 18881 |
| 启动后直接闪退 / 回官网登录弹窗 | 替身没生效 | 看 `PCSDK_release\PCSDKUI.exe` 是不是 8KB 左右（原版是 170KB） |
| 装完还是弹官网网页 | 客户端副本没重建 | 删掉 `profiles\solo\client` 整个目录，回第 1 步重来，再跑一次 `install.ps1` |

---

## 4. 想回官服怎么办

### 最省事：双击 `一键切换.bat`

双击后会弹菜单，直接告诉你现在是什么模式：

```
============================================
   开放空间 · 单机 / 官服 一键切换
============================================
   当前状态：单机模式（走本机服务端）

   1  切到【单机模式】
   2  切回【官服模式】
   0  退出
```

按 `2` → UAC 点「是」→ 自动回官服；按 `1` → 自动回单机。

第一次按 `1` 会让你拖一次启动器目录（**是放 OverFieldLauncher.exe 的那个文件夹，不是游戏目录 176228**），之后它会记在 `launcher.path` 里，以后不用再填。

不想看菜单也行，直接双击这两个：

- `切回官服.bat`
- `切到单机.bat`

**注意：装完补丁后，直接点 TapTap 启动器是回不去官服的。**

因为 hosts 那一行和 18881 端口转发还在，官方客户端拿到登录 token 后请求
`http://dsp-prod-of.inutan.com:18881/dispatch/...` 会被导到本机，
结果要么连到本地服务，要么报「服务器获取失败」。

正确的切换方式，二选一：

### 方式 A：一键切换（推荐）

```powershell
# 回官服
powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode official

# 再回单机
powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode solo
```

右键 `switch.ps1` 直接跑也可以，默认按单机处理；要回官服就在命令行带 `-Mode official`。

### 方式 B：完整卸载

右键运行 `uninstall.ps1`（要管理员），它会：

- 从备份还原 `hosts`
- 删除 18881 端口转发
- 把 `PCSDKUI.orig.exe` 还原成 `PCSDKUI.exe`
- 清掉代理旁路里加的条目

**两种方式做完后，你的客户端和装补丁前完全一样，TapTap 启动器直接进官服。**

想确认切干净了，跑这三条：

```powershell
Get-Content C:\Windows\System32\drivers\etc\hosts | Select-String inutan   # 应该没有输出
netsh interface portproxy show v4tov4                                       # 应该看不到 18881
[System.Net.Dns]::GetHostAddresses('dsp-prod-of.inutan.com')                # 应该不是 127.0.0.1
```

> 切回官服前，建议先在启动器里点一次「停止」，把本地 `Lolo.exe` 关掉（任务管理器里结束也行）。

---

## 5. 这个项目做了什么、没做什么

**做了：**

- `PCSDKUI.exe` 替身：接管游戏的命名管道 `\\.\pipe\quickpc<游戏PID>`，回 `{"action":"init"}` / `{"action":"loginSuccess"}`，用你填的 UID 做本地登录
- hosts 重定向 dispatch 域名到本机
- 18881 → 18080 端口转发
- 系统代理旁路

**没做（也不会做）：**

- 不改游戏本体、不改原客户端目录（只动 `profiles\solo\client` 这个副本）
- 不发道具、不改角色、不改存档、不碰数据库
- 不提供游戏本体、不提供服务端二进制（`Lolo.exe` 等请自行从合法来源获取并放进 `server-kit\`）
- 不触碰你在官服的任何数据

---

## 6. 免责声明（务必看完）

1. **本项目为非官方社区补丁**，与游戏开发商、发行商、渠道方（TapTap / 哔哩哔哩等）以及
   [inori-dream/miaomiao-launcher](https://github.com/inori-dream/miaomiao-launcher) 作者均无关联，
   未获得任何授权、合作或背书。
2. 本项目**不提供、不分发**游戏客户端、服务端程序、游戏资源、账号数据或任何受版权保护的内容。
   使用本项目前，你应当已经通过合法途径拥有游戏客户端；服务端资源由你自行从合法来源准备。
3. 本项目**仅用于本机自用与学习研究**（理解渠道 SDK 的本地登录链路）。
   **禁止**用于商业化运营、对外提供联机服务、二次贩卖、任何形式的牟利或大规模传播。
4. 本项目不绕过任何付费内容，不提供任何破解、激活、内购规避能力。
5. **使用风险由你自行承担。** 可能出现（但不限于）：客户端异常、存档/配置损坏、
   游戏更新后失效、渠道账号被风控等后果。作者与贡献者**不承担任何直接或间接责任**，
   包括但不限于数据丢失、账号处罚、设备损坏、法律纠纷。
6. 请勿将本补丁用于任何违反游戏用户协议、渠道服务条款或当地法律法规的用途。
   是否使用、如何使用，由你自行判断并承担全部后果。
7. 若你是权利人并认为本项目侵犯了你的权益，请通过 Issue 联系，本项目会立即调整或删除相关代码。
8. **下载、安装或运行本项目任意文件，即视为你已阅读、理解并接受以上全部条款。**
   如果你不同意，请不要使用。

---

## 7. 文件说明

| 文件 | 用途 |
| --- | --- |
| `一键切换.bat` | **双击这个**，菜单里选单机 / 官服 |
| `切回官服.bat` | 双击直接回官服 |
| `切到单机.bat` | 双击直接回单机 |
| `switch.ps1` | 上面三个 bat 背后的逻辑，也可以命令行带 `-Mode` 调用 |
| `install.ps1` | 安装 / 修复补丁（自动申请管理员） |
| `uninstall.ps1` | 完整还原 |
| `tools/PCSDKUIStub.exe` | 替身程序（预编译，直接可用） |
| `tools/PCSDKUIStub.cs` | 替身源码，可自行审阅 |
| `tools/build-stub.ps1` | 重新编译替身（用系统自带 csc，不需要 VS） |
| `docs/原理.md` | 协议链路细节，给想深挖的人 |

## 8. 致谢

- 启动器：[inori-dream/miaomiao-launcher](https://github.com/inori-dream/miaomiao-launcher)
- 服务端：[BanterSR/Lolo](https://github.com/BanterSR/Lolo)、[byzp/of-ps](https://github.com/byzp/of-ps)
- 本补丁只补了「渠道版本地登录」这一环，其余功能以上游项目为准

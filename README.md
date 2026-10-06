# dsh-workbuddy-setup

把 WorkBuddy 桌面 App 里已经登录的模型（GLM / DeepSeek / Kimi / MiniMax / Hy 系列）接进 DeepSeek Harness（DSH）。下面是 2026-10-06 在 Windows 上的实际操作记录，另外附两个 PowerShell 脚本，一个负责改 profile 装插件，一个负责体检。

非官方项目，与腾讯、WorkBuddy、DeepSeek 均无关联。涉及的插件都是第三方 npm 包，作者和版本以 npm 为准。

## 摘要

1. 先读出 DSH 实际运行的内核版本，再挑插件版本。装错了不会报错：宿主会把整个组合包静默跳过。
2. 2026-10 在 DSH `0.2.0-rc.2`（Windows 桌面版）上能跑、并且带设置卡片的是 `dsh-connect-workbuddy@3.6.0`。
3. `dsh-workbuddy-connect@0.7.1` 在同一内核上也能跑（17 个模型正常出现），但没有设置卡片。0.2.0 移除了 `installSection`，这个版本没有适配新的 Config 表单门面。
4. 两个插件注册的 provider id 都是 `workbuddy`，只能装一个。并存会撞 id，模型分组出现两份。
5. 装完需要重启 DSH，bundle 只在宿主启动时挂载。

## 1. 判定内核版本

DSH 的启动参数里带着实际使用的运行时目录，内核版本写在那个目录的 `runtime.json` 里：

```powershell
# 1) 找到正在运行的 DSH 进程，读出它的运行时目录（最后一个 resources\runtime\bin 之前的那个参数）
Get-CimInstance Win32_Process -Filter "Name like '%DeepSeek%'" |
  Select-Object -First 1 -ExpandProperty CommandLine

# 2) 读 desktopVersion
Get-Content "<安装目录>\resources\runtime\primary-runtime\runtime.json" | ConvertFrom-Json |
  Select-Object desktopVersion, nodeVersion
```

`runtime.json` 里还有 `nodeVersion` / `pnpmVersion` / `pythonVersion`，同一份文件就够挑版本了。

Windows 桌面版的常见安装位置是 `D:\DeepSeekHarness\` 或 `%LOCALAPPDATA%\Programs\DeepSeek Harness\`。`%LOCALAPPDATA%\Programs` 下没有它，不代表没装，它可能在别的盘。

## 2. 插件选型

DSH 的随包门禁（`packages/boot/app-boot/src/plugin-compatibility.ts` 里的 `evaluatePluginCompatibility`）会逐条核对插件声明的 `dsh-*` peer 范围。只要有一条不满足，整个组合包就被跳过，进 `skippedBundles`，且只打印到 stderr。界面上的表现是 provider 不注册、设置卡片不出现、模型列表为空，一个报错都没有。

所以选版本要对着表来。

### 2.1 两个直连插件

| 插件 | 版本 | 要求的 DSH 内核 | 设置卡片 | 备注 |
|---|---|---|---|---|
| `dsh-workbuddy-connect` | `0.7.1` | 仅 `0.2.0-rc.2`，且 `@earendil-works/pi-ai` 收窄为 `^0.87.1` | ❌ 0.2.0 上无卡片 | 0.6.x 原地升级会解析到 pi-ai 0.87.1；0.7.1 起不再支持 `0.2.0-rc.1` |
| `dsh-workbuddy-connect` | `0.7.0` | `0.2.0-rc.1` / `0.2.0-rc.2` | ❌ | 0.1.x 用户请停在 `0.6.5` |
| `dsh-workbuddy-connect` | `0.6.5` | `0.1.5` / `0.1.6` / `0.1.7` / `0.2.0-rc.1` | ✅（旧界面） | `0.1.x` 线最终版 |
| `dsh-workbuddy-connect` | `0.6.0` | `0.1.5-rc.1` ~ `0.1.7`（含 `-alpha.*`） | ✅（双界面自适应） | 跨 `0.2.0` 的 prerelease 需显式扩展 peer |
| `dsh-connect-workbuddy` | `3.6.0` | 全部 `dsh-*` peer = `>=0.1.7-rc.1 <0.3.0-0`；`pi-ai >=0.85.0 <0.88.0` | ✅ | 自 `2.1.0` 起只支持 `0.1.7-rc.1+`；`2.1.2` 起上界写 `<0.3.0-0` 并实测 `0.2.0` 全线 |
| `dsh-connect-workbuddy` | `≤2.0.15` | `0.1.5` 及更早 | ✅（旧界面） | 新宿主装不上（依赖解析失败） |

### 2.2 同一次调研里的其他候选

| 插件 | 版本(发布日) | peer 关键点 | 对 `0.2.0-rc.2` |
|---|---|---|---|
| `dsh-workbuddy-console` | 2.0.38 (2026-10-05) | `@deepseek-ai/dsh-host-webserver: >=0.1.1-rc.1 <0.2.0` | ❌ 明确排除 0.2.0 |
| `dsh-workbuddy-bridge` | 0.3.1 (2026-10-03) | 全部 `>=0.1.7-rc.2`（无上界） | ⚠️ 依赖能装，但 0.2.0 支持未在 README 明写（兼容说明在仓库 `docs/COMPATIBILITY.md`） |
| `dsh-workbuddy-xdpool` | 1.8.0 | `>=0.1.1-rc.1 <0.3.0` | ✅ 范围覆盖 |
| `dsh-workbuddy-connect-functy` | 0.13.9 | `^0.1.7-alpha.1 \|\| ^0.2.0-rc.1` | ✅ 覆盖 rc.2 |
| `dsh-llm-codebuddy` | 1.3.10 | `<0.2.0` | ❌ |
| `@axiaohungry/dsh-llm-workbuddy` | 1.3.19 | 排除 `0.2.0` | ❌ |

挑版本时可以直接看 npm 上的 `peerDependencies`，把每个 `dsh-*` 包当成跟随内核版本即可。`>=0.1.7-rc.1 <0.3.0-0` 这种写法通常意味着 0.2.x 也在范围内。

## 3. 安装

### 3.1 脚本（推荐）

```powershell
# 默认：装 dsh-connect-workbuddy@3.6.0 到 desktop profile，并移除 dsh-workbuddy-connect
pwsh -File .\scripts\install-workbuddy-plugin.ps1

# 只看看会改什么，不动文件
pwsh -File .\scripts\install-workbuddy-plugin.ps1 -DryRun

# 指定版本/插件
pwsh -File .\scripts\install-workbuddy-plugin.ps1 -Plugin dsh-workbuddy-connect -Version 0.7.1 -Remove @()
```

脚本做四件事：备份 `package.json`，改 `dependencies` 和 `dsh.profile.bundles`，用 App 自带的 node+pnpm 跑 `install`，打印后续验证命令。

### 3.2 手动

profile 目录形如 `%USERPROFILE%\.dsh\profiles\<profile>\`（这里实测是 `desktop`）。需要改两处：

```jsonc
{
  "dependencies": {
    "dsh-connect-workbuddy": "3.6.0"   // ← 版本必须匹配内核
  },
  "dsh": {
    "profile": {
      "bundles": [
        // ...
        "dsh-connect-workbuddy"        // ← 按加载顺序写，通常放末尾
      ]
    }
  }
}
```

然后用 App 自带的 node + pnpm 安装，不要用系统的：

```powershell
$node = "<安装目录>\resources\runtime\primary-runtime\dependencies\node\bin\node.exe"
$pnpm = "<安装目录>\resources\runtime\pnpm\bin\pnpm.mjs"
& $node $pnpm install --reporter=append-only
```

### 3.3 官方 CLI 路径

DSH 自带一个 CLI 包装器（用 `ELECTRON_RUN_AS_NODE` 起 Electron）：

```powershell
<安装目录>\resources\runtime\cli\bin\dsh.cmd plugin --profile desktop add dsh-connect-workbuddy
```

`dsh plugin ...` 只是把参数透传给 pnpm（`dsh plugin --profile desktop --help` 会直接吐出 pnpm 的帮助），它不会替你写 `dsh.profile.bundles`，装完还得手工加条目。

## 4. 验证

### 4.1 不看界面，确认插件到底有没有加载

心跳文件最省事。两个 WorkBuddy 插件都会写 `%USERPROFILE%\.dsh\.workbuddy-host-heartbeat.json`：

```json
{"version":1,"package":"dsh-connect-workbuddy","pluginVersion":"3.6.0","registeredAt":1791250669257,"pid":17508}
```

`package` / `pluginVersion` 就是真正挂载的那个插件。文件不存在，或者包名还是旧的，说明它没起来，多半被 `skippedBundles` 跳过了。

### 4.2 一键体检

```powershell
pwsh -File .\scripts\verify-workbuddy-plugin.ps1
```

它会打印内核版本、profile 里实际解析到的插件版本、lockfile 条目、心跳文件，并逐个探测插件的 HTTP 路由。

### 4.3 状态路由（视插件而定）

- `dsh-workbuddy-connect` 注册了 `GET http://127.0.0.1:19387/plugins/dsh-workbuddy-connect/status`，无需 GUI 认证，直接返回账号、域名（`www.codebuddy.cn`）、模型列表与积分。
- `dsh-connect-workbuddy@3.6.0` 没有注册任何 `/plugins/...` 路由（全部 404），积分和账号只能在它的设置卡片里看。
- DSH 自己的 `/api/*` 需要 GUI 认证，不带凭据时返回 401。

## 5. 排错

### 5.1 装完什么都没发生，界面上也没有报错

几乎都是 peer 门禁把整个 bundle 跳过了。对着第 2 节的表核一遍，`skippedBundles` 只打印到 stderr，GUI 不显示。

另一个常见原因是忘了把包名加进 `dsh.profile.bundles`，只加 `dependencies` 不会加载。

### 5.2 模型能用了，但「设置 → 插件」里没有卡片

0.2.0 把设置服务换成了 Config 表单门面（只暴露 `.volatile()` 字段），并移除了旧的 `installSection` 接口。老插件在这个内核上会降级成没有设置项的 provider：

```js
// dsh-workbuddy-connect@0.7.1 lib/index.js
const legacy = legacySettingsOf(settingsCtx.settings);
if (legacy === void 0) {
  ctx.logger.warn("...host settings service has no installSection API; per-variant settings and the maximum-context preference are unavailable");
  return;   // ← 设置分区根本没注册
}
```

判断一个插件有没有适配 0.2.0：看它的 `lib/*.js` 里有没有用 schemastery 的 `Config` 加 `asVolatile(...)`，也就是 `volatile` 关键字命中数是否大于 0。`dsh-connect-workbuddy@3.6.0` 命中 18 次，代码里也写着自 2.1.0 起 `installSection` 路径已移除，所以卡片在 0.2.0 上正常渲染。

### 5.3 `dsh plugin exec` 跑插件命令报 `ERR_MODULE_NOT_FOUND`

```
Error [ERR_MODULE_NOT_FOUND]: Cannot find package '@deepseek-ai/dsh-atomic-write'
imported from ...\node_modules\dsh-workbuddy-connect\lib\host-heartbeat-*.js
```

`pnpm exec` 用普通 node 拉起插件 CLI，拿不到 App 内部的 `@deepseek-ai/*` 包。这个桌面版上不要用 CLI 跑插件命令，改用插件自己的 HTTP 路由或设置卡片。

宿主正常加载插件时会自己解析这些内部包：profile 的 `node_modules\@deepseek-ai\` 里只有 `cosmokit` 和 `schemastery`，插件照样能 import `dsh-credentials` 之类。

### 5.4 两个插件一起装

两个直连插件注册的 provider id 都是 `workbuddy`（代码里是 `options.provider ?? "workbuddy"` 和 `options.providerId ?? "workbuddy"`）。要替换，别并存，脚本默认会从 `dependencies` 和 `bundles` 里移除 `dsh-workbuddy-connect`。

### 5.5 回退

脚本每次都会把改动前的 `package.json` 备份成 `package.json.bak-<时间戳>`：

```powershell
Copy-Item $env:USERPROFILE\.dsh\profiles\desktop\package.json.bak-20261006-094500 `
          $env:USERPROFILE\.dsh\profiles\desktop\package.json -Force
& $node $pnpm install
```

然后重启 DSH。

## 6. 本次实测记录

| 项 | 值 |
|---|---|
| 时间 / 平台 | 2026-10-06，Windows 11 |
| DSH 内核 | `0.2.0-rc.2`（桌面版，`runtime.json` 读出） |
| 试用插件 A | `dsh-workbuddy-connect@0.7.1` |
| 试用插件 B | `dsh-connect-workbuddy@3.6.0`（最终采用） |
| WorkBuddy App | 已安装并登录，登录域名 `www.codebuddy.cn` |
| 模型 | 17 个：`hy4-preview-f`、`hy3`、`hy3-x`、`space-bunny`、`deepseek-v4.1-flash`、`deepseek-v4-pro`、`glm-5.3`、`glm-5.3-flash`、`glm-5.2`、`glm-5.1`、`glm-5v-turbo`、`minimax-m3`、`minimax-m2.7`、`kimi-k3-1`、`kimi-k2.8-preview`、`kimi-k2.7`、`kimi-k2.6` |
| 安装耗时 | `pnpm install` 1.6–2.2s（`Packages: +1 -29`，会顺手清掉孤立包） |
| 心跳确认 | `{"package":"dsh-connect-workbuddy","pluginVersion":"3.6.0",...}`，重启后约 5s 写入 |

### A 换成 B 的原因

- A 在 0.2.0 上没有设置卡片（原因见 5.2），账号、令牌有效期、剩余积分、模型显隐都没地方看。
- B 的 peer 范围明确包含 0.2.x，实现上确实走了 0.2.0 的 Config 表单门面。
- 两者 provider id 相同，所以做成替换而不是叠加。

## 7. 目录

```
README.md
scripts/
  install-workbuddy-plugin.ps1   # 安装/替换插件（支持 -DryRun）
  verify-workbuddy-plugin.ps1    # 内核版本、解析版本、心跳、路由体检
```

## 8. 参考

- `dsh-workbuddy-connect`：<https://www.npmjs.com/package/dsh-workbuddy-connect>
- `dsh-connect-workbuddy`：<https://www.npmjs.com/package/dsh-connect-workbuddy>
- 门禁实现路径（宿主源码）：`packages/boot/app-boot/src/plugin-compatibility.ts` → `evaluatePluginCompatibility`

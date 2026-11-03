# Mihomo

Omarchy 栏上的 mihomo 流量小组件。默认只读展示状态；面板上的两个按钮会调用控制器 API。按钮显示当前值和下一个目标，节点按钮按当前模式选择目标组。

## 功能

- 栏上显示下行速率。离线时显示 `off`，尚未收到采样时显示 `…`。
- 采样超过 8 秒没有更新时，速率标签变淡，状态变为 stale。
- 悬停显示当前模式和当前节点。
- 节点按模式取：`rule` 显示配置组的当前节点，`global` 显示 `GLOBAL` 的当前节点，`direct` 显示 `DIRECT`。
- `rule` 下的节点是默认组的选中节点，不代表所有连接都走它。
- 左键打开明细面板，显示模式、节点、下行、上行、累计下行、累计上行、连接数和最后更新秒数。
- 面板顶部显示实时、数据过期、离线或启动中。`rule` 会提示节点来自默认组，`direct` 会提示节点按钮不可用。
- 面板内按 `r` 重启采样进程，按 `Esc` 关闭。按 `Tab`/`Shift+Tab` 在两个按钮间移动焦点，按 `Enter`/`Space` 执行当前按钮。
- 面板底部两个按钮显示当前模式和节点与下一个目标：节点按钮在 `rule` 下切配置组，在 `global` 下切 `GLOBAL`；模式按钮在 `rule` 与 `global` 间切换。节点按钮在配置不完整或 `direct` 下禁用；离线、数据过期、启动中或操作进行中两个按钮都禁用。
- 操作完成后显示控制器返回的实际切换结果，失败时显示错误。
- 采样进程退出后 30 秒自动重启。

## 依赖

- Omarchy 4 的 Quickshell 桌面。
- `bash`、`curl` 和 `jq`。
- 已开启外部控制器的 mihomo，默认地址 `http://127.0.0.1:9090`。
- `rule` 模式的代理组由 `MIHOMO_GROUP` 指定，`global` 模式使用 `GLOBAL`。对应组不存在时，节点一栏显示 `—`。

## 安装

把仓库复制为插件目录，重新扫描插件，然后启用。

```sh
cp -r mihomo-omaplugin ~/.config/omarchy/plugins/io.github.zzhan111.mihomo
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.zzhan111.mihomo
```

或者直接 clone 到插件目录，之后用 `git pull` 更新。插件扫描不跟随符号链接，目录必须是真实目录。

```sh
git clone https://github.com/zzhan111/mihomo-omaplugin ~/.config/omarchy/plugins/io.github.zzhan111.mihomo
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.zzhan111.mihomo
```

启用操作会写 `~/.config/omarchy/shell.json`。本仓库不执行启用，也不写该文件。

## 配置

组件读取 Omarchy shell 会话环境中的变量；节点和组名称仅保存在自己的本地配置中，不要提交到公开仓库。

| 变量 | 默认值 | 用途 |
|---|---|---|
| `MIHOMO_API` | `http://127.0.0.1:9090` | 外部控制器地址 |
| `MIHOMO_SECRET` | 空 | 非空时作为 Bearer token 发送 |
| `MIHOMO_GROUP` | 空 | `rule` 模式的选择组名称 |
| `MIHOMO_NODE_A` | 空 | 切换目标之一 |
| `MIHOMO_NODE_B` | 空 | 另一个切换目标 |

例如，在 `~/.config/environment.d/mihomo-widget.conf` 中填写以下虚构示例并替换为自己的名称：

```ini
MIHOMO_GROUP=Proxy Group
MIHOMO_NODE_A=Node A
MIHOMO_NODE_B=Node B
```

修改会话环境通常需要重新登录；仅在终端设置变量不会改变已运行的 shell。请限制含凭据的配置文件权限。

## IPC

栏挂载后可用以下命令。

```sh
omarchy-shell io.github.zzhan111.mihomo open
omarchy-shell io.github.zzhan111.mihomo close
omarchy-shell io.github.zzhan111.mihomo toggle
omarchy-shell io.github.zzhan111.mihomo refresh
omarchy-shell io.github.zzhan111.mihomo toggleNode
omarchy-shell io.github.zzhan111.mihomo toggleMode
omarchy-shell io.github.zzhan111.mihomo state
```

`state` 返回单行 JSON，包含 `status`、`ok`、`mode`、`node`、`up`、`down`、`upTotal`、`downTotal`、`conns`、`ts` 和 `age`。状态为 `offline` 时还会包含 `error`。

## 数据契约

`bin/mihomo-watch` 每 `--interval` 秒向 stdout 输出一行 JSON。默认间隔为 2 秒。

```json
{"ok":true,"mode":"rule","node":"Node A","up":0,"down":0,"upTotal":0,"downTotal":0,"conns":0,"ts":1700000000}
```

失败时输出错误对象，循环继续。

```json
{"ok":false,"error":"connections request failed (curl 7)"}
```

字段说明：

| 字段 | 含义 |
|---|---|
| `ok` | 本次采样是否成功 |
| `mode` | mihomo 当前模式，例如 `rule` |
| `node` | 按模式取节点：`rule` 为配置组的当前节点，`global` 为 `GLOBAL` 的当前节点，`direct` 为 `DIRECT` |
| `up` | 上行速率，字节每秒 |
| `down` | 下行速率，字节每秒 |
| `upTotal` | 累计上行字节数 |
| `downTotal` | 累计下行字节数 |
| `conns` | 当前连接数 |
| `ts` | 采样时间，Unix 秒 |

`up` 和 `down` 由相邻两次采样的累计值差除以实际经过秒数得到。第一次采样没有基准，速率为 0。模式和节点每个采样都重新读取，所以切换后下一次采样就会反映出来。

## 测试

`tests/test_watch.py` 用 Python 标准库启动模拟控制器，运行真实的 `bin/mihomo-watch`，检查 `rule`、`global`、`direct` 以及模式和节点切换时的输出。

`tests/test_toggle.py` 用同样的模拟控制器运行真实的 `bin/mihomo-toggle`，检查 `global` 切 `GLOBAL`、`rule` 切 `Proxy Group`、`direct` 拒绝且不写入，以及 API 拒绝时返回错误。

```sh
python3 tests/test_watch.py
python3 tests/test_toggle.py
```

## 状态

`Widget.qml` 用一个派生状态驱动栏标签、提示和面板。

| 状态 | 条件 | 栏标签 |
|---|---|---|
| `starting` | 还没收到采样 | `…` |
| `live` | `ok` 为 true 且快照年龄不超过 8 秒 | 下行速率 |
| `stale` | `ok` 为 true 且快照年龄超过 8 秒 | 下行速率，45% 透明度 |
| `offline` | `ok` 为 false | `off` |

## 文件

| 文件 | 用途 |
|---|---|
| `manifest.json` | Omarchy 插件清单 |
| `Widget.qml` | 栏条目、明细面板和 IPC |
| `bin/mihomo-watch` | 采样循环，输出单行 JSON |
| `bin/mihomo-toggle` | 按实时模式切换节点或模式 |
| `tests/test_watch.py` | 模拟控制器的采样回归测试 |
| `tests/test_toggle.py` | 模拟控制器的切换回归测试 |
| `README.md` | 本文件 |
| `LICENSE` | MIT 许可证 |

## 限制

- 采样脚本只发 `GET`。切换脚本先读 `/configs`，再按模式对 `GLOBAL` 或配置组发 `PUT`，模式切换发 `PATCH /configs`。
- 节点按钮在 `MIHOMO_NODE_A` 与 `MIHOMO_NODE_B` 之间切换；`rule` 使用 `MIHOMO_GROUP`，`global` 使用 `GLOBAL`，`direct` 拒绝切换。模式按钮只在 `rule` 与 `global` 间切换；当前为 `direct` 时切到 `global`。
- 速率是采样区间的平均值，不是瞬时值。
- 插件没有设置项，因此清单里没有 `schema` 和 `defaults`。

# Mihomo

Omarchy 栏上的 mihomo 流量小组件。它只读取 mihomo 外部控制器的数据，不修改配置、不切换节点、不写入文件。

## 功能

- 栏上显示下行速率。离线时显示 `off`，尚未收到采样时显示 `…`。
- 采样超过 8 秒没有更新时，速率标签变淡，状态变为 stale。
- 悬停显示当前模式和当前节点。
- 左键打开明细面板，显示模式、当前节点、下行、上行、累计下行、累计上行、连接数和最后更新秒数。
- 面板内按 `r` 重启采样进程，按 `Esc` 关闭。
- 采样进程退出后 30 秒自动重启。

## 依赖

- Omarchy 4 的 Quickshell 桌面。
- `bash`、`curl` 和 `jq`。
- 已开启外部控制器的 mihomo，默认地址 `http://127.0.0.1:9090`。
- 代理组 `🚀 节点选择`。该组不存在时，节点一栏显示 `—`。

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

`bin/mihomo-watch` 读取两个环境变量。

| 变量 | 默认值 | 用途 |
|---|---|---|
| `MIHOMO_API` | `http://127.0.0.1:9090` | 外部控制器地址 |
| `MIHOMO_SECRET` | 空 | 非空时作为 Bearer token 发送 |

组件通过 `Process` 启动脚本，脚本继承 Omarchy shell 的环境。修改环境变量后需要重启 shell 才生效。

## IPC

栏挂载后可用以下命令。

```sh
omarchy-shell io.github.zzhan111.mihomo open
omarchy-shell io.github.zzhan111.mihomo close
omarchy-shell io.github.zzhan111.mihomo toggle
omarchy-shell io.github.zzhan111.mihomo refresh
omarchy-shell io.github.zzhan111.mihomo state
```

`state` 返回单行 JSON，包含 `status`、`ok`、`mode`、`node`、`up`、`down`、`upTotal`、`downTotal`、`conns`、`ts` 和 `age`。状态为 `offline` 时还会包含 `error`。

## 数据契约

`bin/mihomo-watch` 每 `--interval` 秒向 stdout 输出一行 JSON。默认间隔为 2 秒。

```json
{"ok":true,"mode":"rule","node":"Enet-FB","up":593,"down":25770,"upTotal":3298504308,"downTotal":4536775327,"conns":8,"ts":1792809900}
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
| `node` | `🚀 节点选择` 的当前节点 |
| `up` | 上行速率，字节每秒 |
| `down` | 下行速率，字节每秒 |
| `upTotal` | 累计上行字节数 |
| `downTotal` | 累计下行字节数 |
| `conns` | 当前连接数 |
| `ts` | 采样时间，Unix 秒 |

`up` 和 `down` 由相邻两次采样的累计值差除以实际经过秒数得到。第一次采样没有基准，速率为 0。节点每 15 次采样刷新一次，其余采样沿用上次结果。

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
| `README.md` | 本文件 |
| `LICENSE` | MIT 许可证 |

## 限制

- 只读。脚本只发 `GET` 请求。
- 节点名固定为 `🚀 节点选择`。改名后需要同步修改脚本。
- 速率是采样区间的平均值，不是瞬时值。
- 插件没有设置项，因此清单里没有 `schema` 和 `defaults`。

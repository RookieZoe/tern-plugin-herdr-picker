# Herdr Picker

[English](README.md) | 简体中文

一个用于 [herdr-core](https://herdr.dev)（`hc`）的 Tern 插件：挑选一个正在运行的 herdr-core 窗格、新建一个
herdr space，或者给某个 space 加一个标签页，然后在 Tern 的 block 里打开它。

## 用法

按 **⌘⇧H** 在当前窗格下方打开 Herdr block，按 **⌘⌥H** 在右侧打开（Linux 和 Windows 上是
**Ctrl+Alt+H** 和 **Ctrl+Alt+Shift+H**），也可以在命令面板里运行这两个命令。会话里还没有任何 block 时，
两个键都会在单独的标签页里打开它。block 提供 **Open a pane**、**New space** 和 **New tab** 三项；每一项都在同一个
block 里继续，Esc 返回上一步，在第一步时则关闭 block。block 较矮时，选单会铺满整个 block，而不是像命令面板那样浮在中间。

| 命令 | macOS | Linux、Windows | Action 名 |
|---|---|---|---|
| **Herdr: open below** | ⌘⇧H | Ctrl+Alt+H | `plugin.herdr-picker.open` |
| **Herdr: open right** | ⌘⌥H | Ctrl+Alt+Shift+H | `plugin.herdr-picker.open-right` |

Linux 和 Windows 上不用 Ctrl+Shift+H，因为 Tern 自己的快捷键已经占用了它。

要改快捷键，在 Tern 的 `settings.json` 的 `keybinds` 里映射对应的 action 名；给一个空列表
（`"cmd+shift+h": []`）即可关掉这个键。

最后得到的窗格运行 `hc attach <address>`，并取代 block 的位置。关闭它不会询问是否结束 `hc`，而且只是断开连接：
herdr-core 里的终端会继续运行。

### Open a pane

列出所有存活的 herdr-core 窗格，并用标签筛选：**All**、**Agents** 和 **Terminals**（←/→ 或 Tab 切换）。
每个标签里的窗格按 herdr space 排成树：有多个窗格的 space 自成一行，下面是它的各个标签页，agent 和普通 shell
混在一起；只有一个窗格的 space 只占一行。在 space 上按 ↵ 折叠或展开；搜索时所有匹配项都保持展开。

- **Agent CLI**，比如 `claude-code` 或 `codex`，显示其图标、状态（working、needs input、done、idle）和目录。
- **Terminals**，即普通 shell（`zsh`、`bash`、`pwsh`、`cmd`…），显示 shell 和目录。

直接输入即可过滤，↑/↓ 移动（到两端会循环），↵ 连接。

```
Find a herdr-core pane…
 All 13   Agents 4   Terminals 9

  ▾ ▸  media-xray-oss         3 panes  ·  ~/Codes/AI/media-xray
    │ ✳  Tab 1     done       claude-code
    │ >_ Tab 2                zsh
    │ >_ Tab 3                zsh
  ✦  api / 1       working    codex  ·  ~/Codes/api
  >_ my-app / 1               zsh  ·  ~/Codes/my-app
                                                 Close   Open
```

已经在某个 Tern block 里连接着的窗格（不论是不是本插件打开的）会显示一个勾。选中它会关闭 Herdr block
并聚焦那个 block，而不是再连接一次。

### New space

在当前窗格的目录打开一个文件夹浏览器：

```
New space  ~/Codes
Filter folders, or type a path…

  >_ Use ~/Codes          start the new space here
  ▸  ..                   ~
  ▸  api/
  ▸  my-app/
                                Back   Create here   Choose
```

在文件夹上按 ↵ 进入，（没输入内容时）按 Backspace 返回上一级，**Use …** 或 **Create here**（⌘↵）在当前位置新建
space。输入文字可过滤文件夹，输入以 `/` 或 `~` 开头的路径可直接跳过去（Windows 上还可以是 `D:\…`，或只输
`D:`）。以 `.` 开头的文件夹不会列出，需要直接输入路径。

在 Windows 主机上，在盘符根目录（`C:\`）选 **..** 会列出所有驱动器及其卷标；在驱动器上按 ↵ 进入它的根目录，
Esc 或 Backspace 回到原来的文件夹。未就绪的驱动器（比如空的读卡器）会显示，但不能选。

插件通过 `hc` 在该文件夹里启动一个 shell，并在 block 的位置打开它。Herdr app 会把它显示为一个以该文件夹或仓库命名的新
space，但不会切换当前显示的 space。要在那里运行 agent，就在新 shell 里启动它。

### New tab

列出所有有存活窗格的 herdr space，附上标签页数和目录，这样同名的两个 space 也能区分开：

```
Add a tab to a herdr space…

  ▸  my-app            2 tabs  ·  ~/Codes/my-app
  ▸  api               1 tab  ·  ~/Codes/api
```

插件在该 space 第一个窗格的目录里启动一个 shell，并在 block 的位置打开它。Herdr app 会把它显示为该 space 的下一个标签页
（`my-app / 3`）。所有窗格都已结束的 space 不会列出。

### 远程主机和手机

Herdr block 运行在会话所属的主机上。在连接到远程 Tern 主机的窗口里，它列出的是那台主机的 herdr-core 窗格，浏览的是那台主机的
文件夹，新 space 也建在那台主机上，`hc attach` 同样在那台主机上运行。它打开的窗格会出现在你的窗口里并获得焦点，和本地会话一样。

插件分为两半，分别来自不同的机器：

| 安装在 | 提供 |
|---|---|
| 你正在用的机器（客户端） | 快捷键、"Herdr: open …" 命令，以及下文的兜底方式 |
| 远程主机 | Herdr block 本身，以及命令面板里的 **New Herdr block** |

所以两边都要装（见[在远程主机上](#在远程主机上)）。只装一边时：

- **只装在客户端：** 快捷键会提示 "Herdr Picker isn't installed on this host"。
- **只装在主机：** 在该主机的会话里快捷键没有反应，但命令面板里的 **New Herdr block** 可用。

herdr-core 也必须在主机上运行：block 只能看到会话所属主机上的 herdr-core，看不到客户端或其他机器上的。

在 Tern for iOS 上，从侧边栏的搜索里打开：**New Herdr block**。手机上不需要安装任何东西；手机所连接主机上的插件会完成所有工作。

在 iPhone 和 iPad 上，block 只能用触摸操作：iOS 上没有按键能传到 block，所以没有过滤，**New space** 里也不能输入路径。
其余操作都可以点按：各行、**All**、**Agents** 和 **Terminals** 标签、**Create here** 以及 **..**。选单的 **Done**
按钮（或把选单往下拖）返回上一步，在第一步时则关闭 block。在 iPhone 上点一下一行就相当于按 ↵；在 iPad 上第一下选中，第二下才生效。

在手机上也装一份插件是可选的，只在用外接键盘、想要 **⌘⇧H** 和 **⌘⌥H** 时才值得。从
[Releases](https://github.com/RookieZoe/tern-plugin-herdr-picker/releases) 下载 `herdr-picker-<version>.zip`，
解压，把 `herdr-picker` 文件夹放进 文件 › 我的 iPhone（或 iPad）› Tern › Plugins（如果是在别处解压的，可以通过
iCloud 云盘或隔空投送传过去）。如果没有出现，彻底关闭 Tern 再重新打开。在主机上运行 `tern plugin install … --force`
不会更新手机上的那份：要更新，就用新版本的文件夹替换手机上的。

## 环境要求

- 支持插件的 Tern
- herdr-core 的 `hc` CLI，版本需支持 `hc ls --json`、`hc connect`（`terminal.list`）、`hc attach` 和 `hc run --label`
- Herdr app 可选。没有它，新 space 的 shell 照样会在 Tern 里打开；app 运行后该 space 才会显示出来。

支持 macOS、Linux 和 Windows。

## 安装

```sh
tern plugin install github.com/RookieZoe/tern-plugin-herdr-picker/plugin
```

这会安装 `main` 上的最新提交，只复制 `plugin/` 文件夹。要更新，加 `--force` 再运行一次。0.4.0 之前从仓库根目录安装过？
加 `--force` 运行一次，换成精简版。

要固定某个版本，从 [Releases](https://github.com/RookieZoe/tern-plugin-herdr-picker/releases) 下载
`herdr-picker-<version>.zip`，解压后安装该文件夹：

```sh
tern plugin install ./herdr-picker --force
```

或者从本地克隆安装，边改边用：

```sh
git clone https://github.com/RookieZoe/tern-plugin-herdr-picker
tern plugin link ./tern-plugin-herdr-picker/plugin
tern plugin reload herdr-picker
```

### 在远程主机上

要在连接到另一台机器的 Tern（`tern remote`）的窗口里使用插件，除了你自己的机器，那台机器上也要装。在主机的 shell 里
（通过 `ssh`，或在该主机会话的某个窗格里）运行同样的命令：

```sh
tern plugin install github.com/RookieZoe/tern-plugin-herdr-picker/plugin --force
tern plugin list   # herdr-picker <version> … ready
```

然后在主机上：

- 确认那里装了 `hc`，并且 block 能找到它（[见下文](#查找-hc-和-tern)）；如果它在别的位置，给主机的 daemon 设置 `HC_BIN`。
- 两台机器保持同一个插件版本；Tern 不会检查两边是否一致。两边都用 `--force` 更新。

支持 macOS、Linux 和 Windows 主机。在该主机的会话上打开一个窗口，按快捷键或在命令面板运行 **New Herdr block**：
列表里应该是主机的窗格，而不是你本机的。

## 查找 `hc` 和 `tern`

block 运行在 Tern 的会话 daemon 里，它的 `PATH` 是系统默认值，所以插件按以下顺序查找 `hc`：

1. 环境变量 `HC_BIN`
2. `~/.local/bin/hc`
3. `/opt/homebrew/bin/hc`、`/usr/local/bin/hc`
4. `%LOCALAPPDATA%\Programs\herdr-core\hc.exe` 或 `%LOCALAPPDATA%\Programs\herdr-app\hc.exe`（Windows）
5. `PATH` 上的 `hc`（仅 Windows）

如果 block 提示找不到 `hc`，在 daemon 启动的环境里把 `HC_BIN` 设为它的完整路径。

插件用 `tern` CLI 打开窗格（依次查找 `TERN_EXE`、`/Applications/Tern.app`、`~/.local/bin`、`/usr/local/bin`、
`/usr/bin`、`%LOCALAPPDATA%\Programs\Tern`）。找不到时，改由你的窗口打开窗格，运行主机上的 `hc`。这需要你的机器上也装了插件，
而且不会检查该窗格是否已经在别处打开。

## 窗格如何分类

`hc ls --json` 报告每个窗格的前台程序；herdr-core 的 `terminal.list` 补充标签，说明它属于哪个 herdr space。
前台程序是已知 shell（`sh`、`bash`、`zsh`、`fish`、`nu`、`pwsh`、`powershell`、`cmd`…）的窗格算作终端；
其他程序，或任何报告了 agent 状态的窗格，都算作 agent CLI。已结束的窗格不会列出。

## 限制

- Tern 插件无法在命令面板里添加分类，所以插件打开的是自己的 block。
- 新 space 使用 Herdr 自动起的名字；要命名需借助 Herdr app（在那里重命名）。

## 许可证

[MIT](LICENSE)

# Herdr Picker

[English](README.md) | 简体中文

一个用于 [herdr-core](https://herdr.dev)（`hc`）的 Tern 插件：挑选一个正在运行的 herdr-core 窗格、新建一个
herdr space，或者给某个 space 加一个标签页，然后在 Tern 的 block 里打开它。

```sh
tern plugin install github.com/RookieZoe/tern-plugin-herdr-picker/plugin
```

在连接到远程 Tern 主机的窗口里使用时，两台机器都要安装：[在远程主机上](plugin/README.zh-CN.md#在远程主机上)。

用法、环境要求和限制：[plugin/README.zh-CN.md](plugin/README.zh-CN.md)。

## 仓库结构

- `plugin/`：插件包，也是 Tern 唯一会安装的文件夹。
- `docs/`：Tern 插件 API 的调研结论、各项调研笔记（`docs/research/`）和决策记录（英文）。
- `GLOSSARY.md`：代码和文档里用到的术语（英文）。

## 许可证

[MIT](LICENSE)

# macsvn

在访达里对 Subversion 工作副本做更新、提交、比较和查看日志。主窗口在扩展没启用时也能做同样的事。

需求见《需求文档》，编码顺序见《开发计划》。

## 环境

- macOS 13 或更新
- 本机的 `svn` 可执行文件。图形程序看不到 Homebrew 的 `PATH`，默认按下面的顺序探测：
  - `/opt/homebrew/bin/svn`
  - `/usr/local/bin/svn`
  - `/usr/bin/svn`

## 构建

```bash
make test
make
open build/macsvn.app
```

产物在 `build/macsvn.app`，已做 ad-hoc 签名。`build/` 不提交。

> **不需要 Apple 开发者证书。** 访达扩展登记不上，和证书无关，实际是两件事：
> 扩展二进制必须是 `MH_EXECUTE`（入口 `_NSExtensionMain`），且 `app-sandbox` entitlement 真的写进了签名
> —— 若用 `-Xlinker -bundle` 编成 `MH_BUNDLE`，`codesign` 会静默丢弃 entitlements，`pkd` 随即以
> `plug-ins must be sandboxed` 拒绝登记，`pluginkit` 里永远查不到；
> 以及宿主 App 先被 LaunchServices 登记。`make` 与 `install.sh` 已包含这两步，构建末尾还会自检。
> 证书只在分发给别人时有用，本机自用 ad-hoc 足够。

## 安装

```bash
./scripts/install.sh
```

脚本会构建、装到 `/Applications/macsvn.app`、签名、登记扩展并自检。
有开发证书时会自动使用；没有则退回 ad-hoc，同样能登记。

## 启用访达菜单

建议把应用放在 `/Applications/macsvn.app`，不要长期从 `build/` 直接打开，否则系统设置里的扩展和访达加载的不是同一份包。

1. 打开 macsvn，确认 svn 路径能保存。
2. **先登记一个工作副本**（或检出）。未登记时访达不会出现 macsvn 菜单，这是 Finder Sync 的机制，不是 bug。
3. 系统设置 → 隐私与安全性 → 扩展 → 点 **「macsvn 扩展」那一行**（副标题「已安装 1 个扩展」），在下一页勾选 **访达 / Finder**，再点「完成」。
4. **不要**只打开下面的「文件提供程序」开关。那是网盘类能力，和 SVN 右键无关。
5. 勾选后执行一次 `killall Finder`（或用访达重新启动），再进入已登记的工作副本目录右键。
6. 工具栏按钮：访达工具栏右键 →「自定义工具栏…」→ 拖入 macsvn。

终端可自检扩展是否已被系统启用（应有 `local.macsvn.FinderSync` 一行）：

```bash
pluginkit -m -v -p com.apple.FinderSync | grep macsvn
```

iCloud 云盘、以及 Dropbox / OneDrive 等由 File Provider 接管的目录里，访达不会显示这个菜单。这类目录仍可在主窗口操作。

## 数据

都在 `~/Library/Application Support/macsvn/`：

| 文件 | 内容 |
|---|---|
| `settings.json` | svn 路径、菜单选项、提交说明历史 |
| `working-copies.json` | 已登记的工作副本 |
| `status.json` | 角标 |
| `macsvn.log` | 命令和退出码，没有密码 |

密码在钥匙串，服务名 `local.macsvn`。

## 这一版有什么

登记、检出、角标、更新、更新到指定版本、增加、撤销增加、恢复、删除、与 BASE 比较、比较两项、信息、检视修改、日志、清理、刷新图标、复制 URL、复制/移动与粘贴、加锁/解锁、稍后比较。

提交窗口是一棵可勾选的树：改动项默认勾上，同目录下**尚未加入版本控制的文件和文件夹**
也会列出来，勾选后会自动 `svn add --parents` 再一起提交。

更新完成后弹出「更新结果」，按动作列出改了什么；没有改动则只在状态栏提示「已是最新」。
命令成功时默认不再弹执行窗口，失败才弹（可在设置里改）。

还没有：改名、复制/移动、忽略、属性、锁定、切换、分支、合并、搁置、版本库浏览器。

## 限制

- 角标只反映本地 `svn status`，不显示「服务器上有更新」。
- 访达扩展按系统要求开启了沙盒，因此它只负责菜单与角标；真正执行 `svn` 的是主程序。
- 拷到另一台 Mac 之前建议换 Developer ID 签名并公证（自己用 ad-hoc 也仍可登记）。
